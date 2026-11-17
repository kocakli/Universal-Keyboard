import Testing
@testable import KeyMapperCore

@Suite struct TriggerRuleTests {
    private let optionZero = KeyCombo(keyCode: 0x1D, modifiers: [.option], key: "0")
    private let optionNine = KeyCombo(keyCode: 0x19, modifiers: [.option], key: "9")

    @Test func shortcutsWithAModifierCanTrigger() {
        #expect(TriggerRules.refusal(for: optionZero, others: []) == nil)
        #expect(TriggerRules.refusal(for: optionNine, others: [optionZero]) == nil)
        #expect(TriggerRules.refusal(for: KeyCombo(keyCode: 0x1D, modifiers: [.control, .shift], key: "0"), others: []) == nil)
        #expect(TriggerRules.refusal(for: KeyCombo(keyCode: 0x6A, modifiers: [.command], key: "F16"), others: []) == nil)
    }

    @Test func reservedFKeysStayValidOnTheirOwn() throws {
        let f16 = try #require(TriggerKey.forKeyCode(0x6A)).combo
        #expect(f16.isReservedKey)
        #expect(TriggerRules.refusal(for: f16, others: [optionZero]) == nil)
        #expect(!optionZero.isReservedKey)
    }

    @Test func plainOrShiftOnlyKeysAreRefused() {
        #expect(TriggerRules.refusal(for: KeyCombo(keyCode: 0x1D, key: "0"), others: []) != nil)
        #expect(TriggerRules.refusal(for: KeyCombo(keyCode: 0x1D, modifiers: [.shift], key: "0"), others: []) != nil)
        // F1 is not one of the reserved trigger keys.
        #expect(TriggerRules.refusal(for: KeyCombo(keyCode: 0x7A, key: "F1"), others: []) != nil)
    }

    @Test func aTriggerCannotBeUsedTwice() {
        // The legend follows the input source; the keys decide.
        let sameKeys = KeyCombo(keyCode: 0x1D, modifiers: [.option], key: "=")
        #expect(TriggerRules.refusal(for: sameKeys, others: [optionZero]) != nil)
        #expect(TriggerRules.refusal(for: optionZero, others: [optionNine]) == nil)
    }

    @Test func letterKeySlotsStayTheirs() {
        let slot = LetterKeys.slots[0]
        let letterCode = KeyCombo(keyCode: slot.keyCode, modifiers: [.control, .option, .command], key: "F13")
        #expect(TriggerRules.refusal(for: letterCode, others: []) != nil)
        // Shift only picks the capital, so it is the same slot.
        #expect(TriggerRules.refusal(for: KeyCombo(keyCode: slot.keyCode, modifiers: [.control, .option, .command, .shift], key: "F13"), others: []) != nil)
        #expect(TriggerRules.refusal(for: KeyCombo(keyCode: slot.keyCode, modifiers: [.control, .option], key: "F13"), others: []) != nil)
        #expect(TriggerRules.refusal(for: KeyCombo(keyCode: slot.keyCode, modifiers: [.control], key: "F13"), others: []) == nil)
    }

    @Test func actionsCannotSendATrigger() {
        // ⌥0 sending ⌥0 would fire itself forever.
        #expect(TriggerRules.sentTrigger(.keystroke(optionZero), triggers: [optionZero]) == optionZero)
        #expect(TriggerRules.sentTrigger(.keystroke(KeyCombo(keyCode: 0x1D, modifiers: [.option], key: "=")), triggers: [optionZero]) != nil)
        #expect(TriggerRules.sentTrigger(.keystroke(optionNine), triggers: [optionZero]) == nil)
        #expect(TriggerRules.sentTrigger(.systemKey(.volumeDown), triggers: [optionZero]) == nil)

        let binding = ActionBinding(name: "Safari", trigger: optionNine, defaultAction: .keystroke(optionZero),
                                    appRules: [AppRule(bundleID: "com.apple.Safari", appName: "Safari", action: .openURL("https://example.com"))])
        #expect(binding.sentKeystrokes == [optionZero])
        #expect(TriggerRules.refusal(for: optionZero, others: [], sent: binding.sentKeystrokes) != nil)
        #expect(TriggerRules.refusal(for: optionNine, others: [], sent: binding.sentKeystrokes) == nil)
    }

    @Test func onlyVolumeAndBrightnessRepeat() {
        #expect(KeyAction.systemKey(.volumeUp).repeatsWhileHeld)
        #expect(KeyAction.systemKey(.volumeDown).repeatsWhileHeld)
        #expect(KeyAction.systemKey(.brightnessDown).repeatsWhileHeld)
        #expect(!KeyAction.systemKey(.mute).repeatsWhileHeld)
        #expect(!KeyAction.systemKey(.playPause).repeatsWhileHeld)
        #expect(!KeyAction.keystroke(optionZero).repeatsWhileHeld)
    }
}
