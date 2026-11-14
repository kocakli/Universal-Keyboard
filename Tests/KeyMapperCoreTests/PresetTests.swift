import Testing
@testable import KeyMapperCore

@Suite struct PresetTests {
    @Test func notationParses() {
        #expect(ShortcutNotation.parse("⌘⇧T") == KeyCombo(keyCode: 0x11, modifiers: [.command, .shift], key: "T"))
        #expect(ShortcutNotation.parse("⌃`") == KeyCombo(keyCode: 0x32, modifiers: [.control], key: "`"))
        #expect(ShortcutNotation.parse("Esc") == KeyCombo(keyCode: 0x35, key: "Esc"))
        #expect(ShortcutNotation.parse("↩")?.keyCode == 0x24)
        #expect(ShortcutNotation.parse("⌘⌥←")?.modifiers == [.command, .option])
        #expect(ShortcutNotation.parse("F16")?.keyCode == 0x6A)
        #expect(ShortcutNotation.parse("⌘Space")?.keyCode == 0x31)
        #expect(ShortcutNotation.parse("⌘") == nil)
        #expect(ShortcutNotation.parse("⌘Ğ") == nil)
    }

    @Test func catalogueIsConsistent() {
        let ids = ActionPresets.apps.map(\.bundleID)
        #expect(Set(ids).count == ids.count, "duplicate bundle ids")
        for preset in ActionPresets.apps {
            #expect(!preset.shortcuts.isEmpty, "\(preset.appName)")
            let titles = preset.shortcuts.map(\.title)
            #expect(Set(titles).count == titles.count, "duplicate titles in \(preset.appName)")
        }
        #expect(ActionPresets.system.count == 5)
    }

    @Test func claudeApprovalNeverUsesShiftTab() {
        // Shift+Tab approves plans / allows for the whole session in Claude Code.
        let shiftTab = ShortcutNotation.parse("⇧⇥")
        for preset in ActionPresets.apps {
            #expect(!preset.shortcuts.contains { $0.combo == shiftTab }, "\(preset.appName)")
        }
    }
}
