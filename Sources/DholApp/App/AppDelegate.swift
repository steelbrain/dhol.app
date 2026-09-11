import AppKit
import Combine
import SwiftUI

@main
struct DholApplication {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private let controller = DictationController()
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var hud: DictationHUD?
    private var phaseObserver: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dhol lives in the menu bar. It only takes a Dock icon while the
        // settings window is open; see showSettings and windowWillClose.
        NSApp.setActivationPolicy(.accessory)

        buildMainMenu()
        buildStatusItem()
        hud = DictationHUD(controller: controller)

        phaseObserver = controller.$phase.sink { [weak self] phase in
            self?.updateStatusItem(for: phase)
        }

        controller.prepareModel()

        if !UserDefaults.standard.bool(forKey: Self.hasLaunchedKey) {
            UserDefaults.standard.set(true, forKey: Self.hasLaunchedKey)
            showSettings(nil)
        }
    }

    private static let hasLaunchedKey = "hasLaunchedBefore"

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings(nil)
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        controller.refreshSystemState()
    }

    /// A capture only ever ended on a key press or the window closing, so
    /// switching away mid-capture left it running — and a running capture
    /// suppresses the hot key, so dictation stayed dead with the only clue
    /// hidden behind whatever the user switched to.
    func applicationDidResignActive(_ notification: Notification) {
        controller.endShortcutCapture()
    }

    // MARK: - Settings window and the Dock icon

    @objc private func showSettings(_ sender: Any? = nil) {
        let window = settingsWindow ?? makeSettingsWindow()
        settingsWindow = window

        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.deminiaturize(nil)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === settingsWindow else { return }
        // The window is reused rather than released, so SwiftUI's onDisappear
        // can't be relied on to end an in-progress shortcut capture. Left
        // running, its key monitor would swallow every key press Dhol receives
        // and quietly rebind the shortcut to the next combination pressed.
        controller.endShortcutCapture()
        // The window is still closing at this point; dropping the Dock icon on
        // the next turn of the run loop lets AppKit finish tearing it down and
        // hand focus back to whatever the user was actually working in.
        Task { @MainActor in
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func makeSettingsWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Dhol"
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: SettingsView(controller: controller))
        window.center()
        return window
    }

    // MARK: - Menu bar

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = MenuBarIcon.image
        statusItem.button?.toolTip = "Dhol"

        let menu = NSMenu()
        menu.delegate = self
        // menuNeedsUpdate decides what is available. Left on, AppKit's automatic
        // enabling overrides that and enables anything whose target implements
        // the action, so "Start Dictation" stayed clickable — and did nothing —
        // for the whole of the first launch's model download.
        menu.autoenablesItems = false
        statusItem.menu = menu
        updateStatusItem(for: controller.phase)
    }

    /// Rebuilt each time the menu opens, so it always shows current state
    /// without anything having to observe the controller on its behalf.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let status = NSMenuItem(title: statusSummary, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        let dictate = NSMenuItem(
            title: controller.isDictating ? "Stop Dictation" : "Start Dictation",
            action: #selector(toggleDictation(_:)),
            keyEquivalent: ""
        )
        dictate.target = self
        dictate.isEnabled = controller.canDictate || controller.isDictating
        menu.addItem(dictate)

        let settings = NSMenuItem(
            title: "Settings…",
            action: #selector(showSettings(_:)),
            keyEquivalent: ","
        )
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Dhol", action: #selector(quit(_:)), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private var statusSummary: String {
        if case .ready = controller.phase {
            return "Hold \(controller.hotKey.displayName) to dictate"
        }
        return controller.phase.title
    }

    /// Colours the status item without breaking its template tinting.
    ///
    /// Setting `contentTintColor` at all overrides the automatic tinting that
    /// makes a template image follow the menu bar — and a semantic colour is
    /// the wrong way to dim it, because it resolves against *this app's*
    /// appearance. A menu bar app has no window, so that appearance is always
    /// Aqua, and `disabledControlTextColor` resolves there to black: the glyph
    /// came out black on a dark menu bar while every other icon was white.
    /// Only the states that want a genuinely non-menu-bar colour set a tint;
    /// dimming is alpha.
    private func updateStatusItem(for phase: DictationController.Phase) {
        guard let button = statusItem?.button else { return }
        switch phase {
        case .listening:
            button.contentTintColor = .systemRed
            button.alphaValue = 1
        case .failed:
            button.contentTintColor = .systemOrange
            button.alphaValue = 1
        case .preparing:
            button.contentTintColor = nil
            button.alphaValue = 0.4
        case .ready, .transcribing:
            button.contentTintColor = nil
            button.alphaValue = 1
        }
    }

    // MARK: - Actions

    @objc private func toggleDictation(_ sender: Any?) {
        controller.toggleDictation()
    }

    @objc private func quit(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    private func buildMainMenu() {
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "About Dhol",
            action: #selector(showSettings(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings(_:)), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Hide Dhol",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        appMenu.addItem(withTitle: "Quit Dhol", action: #selector(quit(_:)), keyEquivalent: "q")
        for item in appMenu.items where item.action == #selector(showSettings(_:))
            || item.action == #selector(quit(_:)) {
            item.target = self
        }

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(
            withTitle: "Close",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        windowMenu.addItem(
            withTitle: "Minimize",
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        )

        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)
        let windowItem = NSMenuItem()
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }
}
