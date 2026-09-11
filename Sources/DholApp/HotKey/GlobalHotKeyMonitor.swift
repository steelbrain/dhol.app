import Carbon.HIToolbox
import Foundation

enum HotKeyFailure: LocalizedError {
    /// The Carbon event handler could not be installed, so no shortcut can
    /// ever call back — distinct from a shortcut being taken, and the two must
    /// not be reported as the same thing.
    case cannotListen
    case alreadyTaken(HotKey)

    var errorDescription: String? {
        switch self {
        case .cannotListen:
            "Dhol can't listen for keyboard shortcuts. Restarting usually fixes this."
        case .alreadyTaken(let hotKey):
            "\(hotKey.displayName) is already taken by another app."
        }
    }
}

final class GlobalHotKeyMonitor {
    var onPressed: (() -> Void)?
    var onReleased: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var handlerStatus: OSStatus = noErr
    private let identifier = EventHotKeyID(signature: 0x4448_4F4C, id: 1) // 'DHOL'

    init() {
        var events = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            ),
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyReleased)
            )
        ]

        let userData = Unmanaged.passUnretained(self).toOpaque()
        handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                let monitor = Unmanaged<GlobalHotKeyMonitor>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                return monitor.handle(event)
            },
            events.count,
            &events,
            userData,
            &eventHandlerRef
        )
    }

    deinit {
        unregister()
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
    }

    func register(_ hotKey: HotKey) throws {
        // Without the handler installed the hot key would register fine and
        // then never call back, leaving the app looking ready but deaf.
        guard handlerStatus == noErr else { throw HotKeyFailure.cannotListen }
        unregister()
        let status = RegisterEventHotKey(
            UInt32(hotKey.keyCode),
            hotKey.carbonModifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard status == noErr else { throw HotKeyFailure.alreadyTaken(hotKey) }
    }

    /// Gives the shortcut back to the system. A registered hot key is consumed
    /// before its key press reaches the app's own event stream, so a shortcut
    /// recorder has to release it to be able to record it.
    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    private func handle(_ event: EventRef) -> OSStatus {
        var receivedID = EventHotKeyID()
        var size = MemoryLayout<EventHotKeyID>.size
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            size,
            &size,
            &receivedID
        )
        guard status == noErr, receivedID.signature == identifier.signature,
              receivedID.id == identifier.id else { return OSStatus(eventNotHandledErr) }

        let action = GetEventKind(event) == UInt32(kEventHotKeyPressed) ? onPressed : onReleased
        DispatchQueue.main.async { action?() }
        return noErr
    }
}
