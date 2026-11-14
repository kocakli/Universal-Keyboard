import Testing
@testable import KeyMapperCore

@Suite struct SmartKeyTests {
    let set = KeycodeSet.v6

    @Test func lettersAndCombosAreReproduced() {
        #expect(SmartKeys.emulation(of: 0x04, keycodes: set) == .keystroke(KeyCombo(keyCode: 0x00, key: "A")))
        let copy = SmartKeys.emulation(of: set.parse("LCTL(KC_C)")!, keycodes: set)
        #expect(copy == .keystroke(KeyCombo(keyCode: 0x08, modifiers: [.control], key: "C")))
        let palette = SmartKeys.emulation(of: set.parse("LGUI(LSFT(KC_P))")!, keycodes: set)
        #expect(palette == .keystroke(KeyCombo(keyCode: 0x23, modifiers: [.command, .shift], key: "P")))
    }

    @Test func mediaKeysBecomeSystemKeys() {
        #expect(SmartKeys.emulation(of: set.parse("KC_MUTE")!, keycodes: set) == .systemKey(.mute))
        #expect(SmartKeys.emulation(of: set.parse("KC_VOLU")!, keycodes: set) == .systemKey(.volumeUp))
        #expect(SmartKeys.emulation(of: set.parse("KC_MPLY")!, keycodes: set) == .systemKey(.playPause))
    }

    @Test func keysThatMustStayInFirmwareAreRefused() {
        #expect(SmartKeys.refusal(for: set.parse("KC_LSFT")!, keycodes: set) != nil)
        #expect(SmartKeys.refusal(for: set.parse("MO(1)")!, keycodes: set) != nil)
        #expect(SmartKeys.refusal(for: set.parse("LT(1, KC_SPC)")!, keycodes: set) != nil)
        #expect(SmartKeys.refusal(for: set.parse("LSFT_T(KC_A)")!, keycodes: set) != nil)
        #expect(SmartKeys.refusal(for: set.parse("KC_A")!, keycodes: set) == nil)
        #expect(SmartKeys.refusal(for: set.parse("KC_F16")!, keycodes: set) == nil)
    }

    @Test func everyLetterAndDigitHasADistinctMacKey() {
        let codes = (0x04...0x27).compactMap { MacKeyCodes.virtualKey(forUsage: UInt16($0)) }
        #expect(codes.count == 36)
        #expect(Set(codes).count == 36)
        #expect(MacKeyCodes.virtualKey(forUsage: 0x6B) == 0x6A) // F16
    }
}
