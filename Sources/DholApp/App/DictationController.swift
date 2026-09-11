import AppKit
import Carbon.HIToolbox
import Combine
import ServiceManagement

/// Owns the dictation lifecycle: the hot key, the microphone, the model, and
/// the text going into the target app.
@MainActor
final class DictationController: ObservableObject {
    enum Phase: Equatable {
        case preparing(Transcriber.Preparation)
        case ready
        case listening
        case transcribing
        case failed(String)
    }

    /// How often a live pass runs while you speak. Words need two agreeing
    /// passes before they are typed, so this interval sets how far behind your
    /// voice the text lands — roughly twice this at best.
    ///
    /// Each pass decodes the whole recording, so passes get slower as a
    /// dictation gets longer. That is self-regulating rather than a problem:
    /// the loop simply ticks less often, and the final pass is unaffected.
    private static let livePassInterval = Duration.milliseconds(500)

    /// Below this there is not enough audio to be worth a decode, and short
    /// clips tend to hallucinate a word out of silence.
    private static let minimumDecodeSamples = Int(AudioCapture.sampleRate * 0.4)

    @Published private(set) var phase: Phase = .preparing(.loading)
    @Published private(set) var hotKey = AppDefaults.hotKey
    @Published private(set) var startsAtLogin = false
    @Published private(set) var loginItemNeedsApproval = false
    @Published private(set) var microphoneGranted = AudioCapture.isPermissionGranted
    @Published private(set) var accessibilityGranted = TextWriter.isAccessibilityGranted
    @Published private(set) var inputLevel: Float = 0

    /// Why the chosen shortcut could not be registered, if it couldn't. Kept
    /// out of `phase` because it outlives whatever the app is doing, and
    /// because a conflict found at launch would otherwise be overwritten the
    /// moment the model starts loading.
    @Published private(set) var shortcutProblem: String?

    /// Why Login Items could not be updated, if it failed. Also kept out of
    /// `phase`: a settings error arriving mid-dictation used to overwrite
    /// `.listening`, after which the hot key release no longer stopped
    /// anything and the microphone stayed live until the app quit.
    @Published private(set) var loginItemProblem: String?

    let modelID = Transcriber.modelID

    private let capture = AudioCapture()
    private let transcriber = Transcriber()
    private let hotKeyMonitor = GlobalHotKeyMonitor()

    private var writer: TextWriter?
    private var liveTask: Task<Void, Never>?
    private var finalTask: Task<Void, Never>?
    private var levelTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var modelIsReady = false

    /// True while a new shortcut is being captured, so the key being pressed
    /// sets the shortcut instead of starting dictation.
    ///
    /// The capture monitor lives here rather than in the SwiftUI field because
    /// the settings window is reused rather than released, so onDisappear
    /// cannot be relied on to take it down. Left installed it would swallow
    /// every key press Dhol receives and silently rebind the shortcut.
    @Published private(set) var isCapturingShortcut = false
    private var shortcutMonitor: Any?

    var isDictating: Bool { phase == .listening }

    var canDictate: Bool {
        modelIsReady && (phase == .ready || isFailed)
    }

    private var isFailed: Bool {
        if case .failed = phase { return true }
        return false
    }

    init() {
        hotKeyMonitor.onPressed = { [weak self] in self?.hotKeyPressed() }
        hotKeyMonitor.onReleased = { [weak self] in self?.hotKeyReleased() }
        applyHotKey(hotKey)
        refreshLoginItemStatus()
    }

    // MARK: - Model

    func prepareModel() {
        guard loadTask == nil, !modelIsReady else { return }
        phase = .preparing(.loading)
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await transcriber.load { progress in
                    Task { @MainActor [weak self] in
                        guard let self, case .preparing = phase else { return }
                        phase = .preparing(progress)
                    }
                }
                modelIsReady = true
                phase = .ready
                Log.shared.notice("Model ready: \(Transcriber.modelID, privacy: .public)")
            } catch {
                Log.shared.error("Model load failed: \(error.localizedDescription, privacy: .public)")
                phase = .failed("Couldn't load the speech model: \(error.localizedDescription)")
            }
            loadTask = nil
        }
    }

    // MARK: - Dictation

    func toggleDictation() {
        if isDictating { endDictation() } else { beginDictation() }
    }

    private func hotKeyPressed() {
        guard !isCapturingShortcut, !isDictating else { return }
        beginDictation()
    }

    private func hotKeyReleased() {
        guard !isCapturingShortcut else { return }
        endDictation()
    }

    private func beginDictation() {
        guard canDictate, liveTask == nil, finalTask == nil else { return }

        // Claim the target before anything can steal focus — a microphone
        // permission prompt would otherwise make Dhol itself the frontmost app.
        do {
            writer = try TextWriter(ignoring: hotKey)
        } catch {
            phase = .failed(error.localizedDescription)
            if error as? TextWriter.Failure == .accessibilityRequired {
                TextWriter.requestAccessibility()
            }
            return
        }

        phase = .listening
        liveTask = Task { [weak self] in await self?.runLivePasses() }
    }

    private func endDictation() {
        guard isDictating else { return }
        liveTask?.cancel()
        liveTask = nil

        let samples = stopCapture()
        guard let writer else {
            phase = .ready
            return
        }
        phase = .transcribing
        finalTask = Task { [weak self] in await self?.runFinalPass(samples: samples, writer: writer) }
    }

    /// Re-transcribes the whole recording every tick and types whatever has
    /// settled since the last one.
    ///
    /// Each pass sees the entire clip, so there are no chunk seams to stitch
    /// back together and a later pass can revise an earlier guess freely.
    private func runLivePasses() async {
        let granted = await AudioCapture.requestPermission()
        // Record the answer before the cancellation check. Letting go of the key
        // to deal with the permission prompt is the normal way to answer it, and
        // dropping the answer left Settings offering "Allow…" for a permission
        // the user had just granted.
        microphoneGranted = granted
        // The key may have been released while the permission prompt was up, in
        // which case endDictation has already handed the writer to the final
        // pass and tearing it down here would pull it out from under it.
        guard !Task.isCancelled else { return }
        guard granted else {
            fail(with: "Dhol needs microphone access to hear you.")
            return
        }

        do {
            try capture.start()
        } catch {
            fail(with: error.localizedDescription)
            return
        }
        startLevelUpdates()

        var previous = ""
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.livePassInterval)
            guard !Task.isCancelled else { return }

            if capture.isAtCapacity {
                // Only reachable if a key release was never delivered. Stopping
                // for real matters: merely refusing more audio would leave the
                // engine running and re-decode the same buffer forever.
                Log.shared.notice("Recording hit its length limit; finishing.")
                endDictation()
                return
            }

            let samples = capture.capturedSamples
            guard samples.count >= Self.minimumDecodeSamples else { continue }

            do {
                let hypothesis = try await transcriber.transcribe(samples)
                guard !Task.isCancelled else { return }
                try writer?.write(Transcript.stablePrefix(previous: previous, current: hypothesis))
                previous = hypothesis
            } catch {
                // A write already in flight can fail after the key was released
                // and the final pass took ownership; let that pass report.
                guard !Task.isCancelled else { return }
                fail(with: error.localizedDescription)
                return
            }
        }
    }

    private func runFinalPass(samples: [Float], writer: TextWriter) async {
        defer {
            writer.stop()
            self.writer = nil
            finalTask = nil
        }
        do {
            let text = samples.count >= Self.minimumDecodeSamples
                ? try await transcriber.transcribe(samples)
                : ""
            try writer.finish(with: text)
            phase = .ready
        } catch {
            Log.shared.error("Final pass failed: \(error.localizedDescription, privacy: .public)")
            phase = .failed(error.localizedDescription)
        }
    }

    private func startLevelUpdates() {
        levelTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                inputLevel = capture.level
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    @discardableResult
    private func stopCapture() -> [Float] {
        levelTask?.cancel()
        levelTask = nil
        inputLevel = 0
        return capture.stop()
    }

    private func fail(with message: String) {
        Log.shared.error("Dictation stopped: \(message, privacy: .public)")
        stopCapture()
        writer?.stop()
        writer = nil
        liveTask = nil
        phase = .failed(message)
    }

    func dismissFailure() {
        guard isFailed else { return }
        phase = modelIsReady ? .ready : .preparing(.loading)
        if !modelIsReady { prepareModel() }
    }

    // MARK: - Settings

    func setHotKey(_ candidate: HotKey) {
        guard applyHotKey(candidate) else {
            // Putting the old shortcut back succeeds, which would clear the
            // message explaining why the new one was refused — leaving the
            // field to silently snap back with no reason given.
            let refusal = shortcutProblem
            // register() unregisters before it re-registers, so a refusal has
            // already dropped the old shortcut. If putting it back also fails
            // there is now no hot key at all, and saying so matters more than
            // explaining why the new one was refused.
            if applyHotKey(hotKey) { shortcutProblem = refusal }
            return
        }
        hotKey = candidate
        AppDefaults.hotKey = candidate
    }

    @discardableResult
    private func applyHotKey(_ candidate: HotKey) -> Bool {
        do {
            try hotKeyMonitor.register(candidate)
            shortcutProblem = nil
            return true
        } catch {
            Log.shared.error(
                "Could not register \(candidate.displayName, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            // Report what actually went wrong. Hardcoding the conflict message
            // here hid the "can't listen" case entirely, so a failed event
            // handler looked like every shortcut being taken and the user would
            // cycle through combinations forever.
            shortcutProblem = error.localizedDescription
            return false
        }
    }

    func beginShortcutCapture() {
        guard !isCapturingShortcut else { return }
        isCapturingShortcut = true
        // A registered Carbon hot key is consumed before its key press reaches
        // a local monitor, which made the shortcut already in use the one
        // combination that could not be re-recorded: pressing it produced no
        // capture, no beep and no cancel, just "Press keys…" until the user
        // gave up. endShortcutCapture puts it back.
        hotKeyMonitor.unregister()
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == UInt16(kVK_Escape) {
                endShortcutCapture()
            } else if let captured = HotKey(event: event) {
                // Ending the capture first restores the old shortcut, so
                // setHotKey then runs exactly as it does from anywhere else —
                // including putting the old one back, and saying why, if the
                // new one is refused.
                endShortcutCapture()
                setHotKey(captured)
            } else {
                // A key with no modifier beyond Shift would fire constantly
                // while you type, so refuse it rather than accept an unusable
                // shortcut. See HotKey.init(event:).
                NSSound.beep()
            }
            return nil
        }
    }

    func endShortcutCapture() {
        // Keyed off the flag rather than the monitor: the hot key is released
        // before the monitor is installed, so a monitor that failed to install
        // must still leave a way to put the shortcut back.
        guard isCapturingShortcut else { return }
        if let shortcutMonitor { NSEvent.removeMonitor(shortcutMonitor) }
        shortcutMonitor = nil
        isCapturingShortcut = false
        // Put back what beginShortcutCapture released. Every way out of a
        // capture comes through here — Escape, the window closing, switching
        // apps, clicking the field again — so this is the only place that has
        // to re-register, and a shortcut that has since been taken by another
        // app is reported rather than silently leaving the app deaf.
        applyHotKey(hotKey)
    }

    func setStartsAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status != .notRegistered {
                    try SMAppService.mainApp.unregister()
                }
            }
            loginItemProblem = nil
        } catch {
            Log.shared.error(
                "Login Items update failed: \(error.localizedDescription, privacy: .public)"
            )
            loginItemProblem = error.localizedDescription
        }
        refreshLoginItemStatus()
    }

    func openLoginItemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func requestMicrophone() {
        Task { [weak self] in
            guard let self else { return }
            let granted = await AudioCapture.requestPermission()
            microphoneGranted = granted
            if !granted { Self.openPrivacySettings(pane: "Privacy_Microphone") }
        }
    }

    func requestAccessibility() {
        TextWriter.requestAccessibility()
        Self.openPrivacySettings(pane: "Privacy_Accessibility")
    }

    /// Permissions and login-item approval are granted in System Settings, so
    /// their real state is only knowable by re-reading it when we come forward.
    func refreshSystemState() {
        microphoneGranted = AudioCapture.isPermissionGranted
        accessibilityGranted = TextWriter.isAccessibilityGranted
        refreshLoginItemStatus()
    }

    private func refreshLoginItemStatus() {
        let status = SMAppService.mainApp.status
        startsAtLogin = status == .enabled || status == .requiresApproval
        loginItemNeedsApproval = status == .requiresApproval
    }

    private static func openPrivacySettings(pane: String) {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(pane)"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
