import AppKit
import Testing
@testable import DholApp

@Test func hotKeyDisplayUsesMacModifierOrder() {
    let hotKey = HotKey(
        keyCode: 0,
        modifierRawValue: (NSEvent.ModifierFlags.command.union(.option).union(.shift)).rawValue,
        keyLabel: "A"
    )
    #expect(hotKey.displayName == "⌥⇧⌘A")
}

@Test func hotKeyRoundTripsThroughJSON() throws {
    let value = HotKey.default
    let data = try JSONEncoder().encode(value)
    #expect(try JSONDecoder().decode(HotKey.self, from: data) == value)
}
