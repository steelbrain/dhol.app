import AppKit
import Carbon.HIToolbox

struct HotKey: Codable, Equatable, Sendable {
    static let `default` = HotKey(
        keyCode: UInt16(kVK_Space),
        modifierRawValue: NSEvent.ModifierFlags.option.rawValue,
        keyLabel: "Space"
    )

    let keyCode: UInt16
    let modifierRawValue: UInt
    let keyLabel: String

    var modifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierRawValue).intersection(.deviceIndependentFlagsMask)
    }

    var displayName: String {
        let flags = modifiers
        var result = ""
        if flags.contains(.control) { result += "⌃" }
        if flags.contains(.option) { result += "⌥" }
        if flags.contains(.shift) { result += "⇧" }
        if flags.contains(.command) { result += "⌘" }
        result += keyLabel
        return result
    }

    var carbonModifiers: UInt32 {
        var result: UInt32 = 0
        if modifiers.contains(.control) { result |= UInt32(controlKey) }
        if modifiers.contains(.option) { result |= UInt32(optionKey) }
        if modifiers.contains(.shift) { result |= UInt32(shiftKey) }
        if modifiers.contains(.command) { result |= UInt32(cmdKey) }
        return result
    }

}

extension HotKey {
    /// Builds a shortcut from a key press, or returns nil if the press can't be
    /// used as one.
    init?(event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .intersection([.command, .option, .control, .shift])
        // Shift is no modifier at all as far as ordinary typing goes: ⇧A is
        // just a capital A, so a Shift-only shortcut fires — and is swallowed,
        // so the letter never arrives — every time the user types one, in every
        // app. Require a modifier that does not appear in running text.
        guard !modifiers.intersection([.command, .option, .control]).isEmpty,
              !Self.isModifierKey(event.keyCode) else { return nil }

        self.init(
            keyCode: event.keyCode,
            modifierRawValue: modifiers.rawValue,
            keyLabel: Self.label(for: event)
        )
    }

    private static func isModifierKey(_ keyCode: UInt16) -> Bool {
        [kVK_Command, kVK_RightCommand, kVK_Shift, kVK_RightShift,
         kVK_Option, kVK_RightOption, kVK_Control, kVK_RightControl,
         kVK_CapsLock, kVK_Function].contains(Int(keyCode))
    }

    private static func label(for event: NSEvent) -> String {
        let special: [UInt16: String] = [
            UInt16(kVK_Space): "Space", UInt16(kVK_Return): "Return",
            UInt16(kVK_Tab): "Tab", UInt16(kVK_Delete): "Delete",
            UInt16(kVK_ForwardDelete): "⌦", UInt16(kVK_Escape): "Escape",
            UInt16(kVK_LeftArrow): "←", UInt16(kVK_RightArrow): "→",
            UInt16(kVK_UpArrow): "↑", UInt16(kVK_DownArrow): "↓",
            UInt16(kVK_Home): "Home", UInt16(kVK_End): "End",
            UInt16(kVK_PageUp): "Page Up", UInt16(kVK_PageDown): "Page Down"
        ]
        if let name = special[event.keyCode] { return name }
        let functionKeys = [
            kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7,
            kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12, kVK_F13,
            kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20
        ]
        if let index = functionKeys.firstIndex(of: Int(event.keyCode)) {
            return "F\(index + 1)"
        }
        return event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
    }
}
