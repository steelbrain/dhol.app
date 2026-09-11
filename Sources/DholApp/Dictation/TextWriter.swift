import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Types dictated text into whichever app was frontmost when dictation started.
///
/// Everything goes in as synthesised keystrokes. That is the one insertion
/// method every target understands equally — terminals, native text fields,
/// Electron apps and web views — so there is no per-app special casing and no
/// list of "supported" bundle identifiers to keep up to date.
@MainActor
final class TextWriter {
    enum Failure: LocalizedError {
        case accessibilityRequired
        case noTarget
        case targetLost

        var errorDescription: String? {
            switch self {
            case .accessibilityRequired:
                "Dhol needs Accessibility access to type for you."
            case .noTarget:
                "Bring the app you want to dictate into first."
            case .targetLost:
                "Dictation stopped because you switched apps."
            }
        }
    }

    /// Tags the events we post so the interruption monitor can tell our own
    /// typing apart from the user's.
    private static let syntheticMarker: Int64 = 0x4448_4F4C_0001

    private let target: pid_t
    private let source: CGEventSource?
    private var monitor: Any?

    /// What this writer has typed into the target so far.
    private(set) var typed = ""

    /// Set once the user types or clicks during the session, after which we
    /// stop correcting so a backspace can never eat their own input.
    private var userIntervened = false

    static var isAccessibilityGranted: Bool { AXIsProcessTrusted() }

    static func requestAccessibility() {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
    }

    init(ignoring hotKey: HotKey) throws {
        guard Self.isAccessibilityGranted else { throw Failure.accessibilityRequired }
        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              frontmost.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { throw Failure.noTarget }

        target = frontmost.processIdentifier
        source = CGEventSource(stateID: .hidSystemState)

        monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            let isOurs = event.cgEvent?
                .getIntegerValueField(.eventSourceUserData) == Self.syntheticMarker
            let isDictationKey = event.type == .keyDown
                && event.keyCode == hotKey.keyCode
                && event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    .intersection([.command, .option, .control, .shift]) == hotKey.modifiers
            guard !isOurs, !isDictationKey else { return }
            self?.userIntervened = true
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// Brings the target up to date with the latest settled text.
    ///
    /// Live passes correct as well as append. An earlier version only appended,
    /// which deadlocked the moment the model revised a word it had already
    /// committed: the new text was no longer an extension of what had been
    /// typed, so every later pass was refused and live typing stopped for the
    /// rest of the session.
    func write(_ text: String) throws {
        let settled = Transcript.sanitized(text)
        // An empty stable prefix means "nothing is settled yet", not "the text
        // is empty" — treating it as the latter would wipe the line.
        guard !settled.isEmpty else { return }
        try apply(
            Transcript.edit(from: typed, to: settled, mayTrim: false, mayDelete: !userIntervened)
        )
    }

    /// Reconciles the target with the final transcript and leaves a trailing
    /// space, ready for the next dictation.
    ///
    /// This pass hears the whole recording at once, so it is authoritative and
    /// may shorten the text as well as extend it. It never deletes more
    /// characters than this writer typed itself.
    func finish(with text: String) throws {
        let final = Transcript.sanitized(text)
        // Nothing was said and nothing was typed — don't leave a stray space
        // behind for a hot key that was tapped by accident.
        guard !typed.isEmpty || !final.isEmpty else { return }
        // The trailing space only exists to separate this dictation from the
        // next one. When the final pass heard nothing there is nothing to
        // separate, and asking for " " would delete everything the live passes
        // typed and then leave that stray space behind anyway.
        let target = final.isEmpty ? "" : final + " "
        try apply(
            Transcript.edit(from: typed, to: target, mayTrim: true, mayDelete: !userIntervened)
        )
    }

    private func apply(_ edit: Transcript.Edit) throws {
        guard !edit.isEmpty else { return }
        try requireTargetFrontmost()
        // A deletion that stopped short leaves the tail of the stale text in
        // place; typing the replacement on top of it would graft the new text
        // onto the old rather than correcting it.
        guard delete(edit.deletions) else { return }
        type(edit.insertion)
    }

    private func requireTargetFrontmost() throws {
        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              frontmost.processIdentifier == target,
              !frontmost.isTerminated
        else { throw Failure.targetLost }
    }

    private func type(_ text: String) {
        for character in text {
            // `typed` is what authorises backspaces later, so it must only ever
            // count keystrokes that really went out. Counting a failed one lets
            // the final pass delete that many characters of the user's own text.
            guard post(virtualKey: 0, text: String(character)) else { return }
            typed.append(character)
        }
    }

    /// Returns false if a backspace could not be sent, leaving the target
    /// part-way through the deletion.
    private func delete(_ count: Int) -> Bool {
        for _ in 0..<count {
            guard post(virtualKey: CGKeyCode(kVK_Delete), text: nil) else { return false }
            typed.removeLast()
        }
        return true
    }

    private func post(virtualKey: CGKeyCode, text: String?) -> Bool {
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: false)
        else {
            Log.shared.error("Could not create a keyboard event; stopping this write.")
            return false
        }

        for event in [down, up] {
            if let text {
                let utf16 = Array(text.utf16)
                utf16.withUnsafeBufferPointer {
                    event.keyboardSetUnicodeString(
                        stringLength: $0.count,
                        unicodeString: $0.baseAddress
                    )
                }
            }
            event.flags = []
            event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
            event.post(tap: .cghidEventTap)
        }
        return true
    }
}
