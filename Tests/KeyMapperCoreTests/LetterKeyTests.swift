import Foundation
import Testing
@testable import KeyMapperCore

@Suite struct LetterKeyTests {
    private let ctrlOptCmd: LetterKeyFilter.Modifiers = [.control, .option, .command]

    @Test func turkishCapitalsAreRight() {
        #expect(LetterKey(slot: 0, lower: "ı").upper == "I")
        #expect(LetterKey(slot: 0, lower: "i").upper == "İ")
        #expect(LetterKey(slot: 0, lower: "ğ").upper == "Ğ")
        #expect(LetterKey(slot: 0, lower: "ş").upper == "Ş")
        #expect(LetterKey(slot: 0, lower: "ß").upper == "ẞ")
        #expect(LetterKeys.turkish.allSatisfy { LetterKey.uppercase($0).count == 1 })
        #expect(LetterKeys.other.allSatisfy { LetterKey.uppercase($0).count == 1 })
        #expect(LetterKey(slot: 0, lower: "i").legend == "İ")
        #expect(LetterKey(slot: 0, lower: "ğ").legend == "ğ")
    }

    @Test func lettersAreCleanedUp() {
        #expect(LetterKey.sanitized(" ğ \n") == "ğ")
        #expect(LetterKey.sanitized("") == nil)
        #expect(LetterKey.sanitized("   ") == nil)
        #expect(LetterKey.sanitized("abcdefghi") == nil)
        #expect(LetterKey.sanitized("a\u{7}") == nil)
    }

    @Test func slotsAreDistinctAndAvoidActionTriggers() {
        let slots = LetterKeys.slots
        #expect(slots.count == 12)
        #expect(Set(slots.map { "\($0.keyCode)-\($0.mods)" }).count == slots.count)
        #expect(slots.allSatisfy { $0.modifiers.contains([.control, .option]) })
        // Bare F-keys stay action triggers; brightness keys F14/F15 are not used.
        #expect(!slots.contains { $0.usage == 0x69 || $0.usage == 0x6A })
        for slot in slots { #expect(TriggerKey.forUsage(slot.usage) != nil) }
    }

    @Test func slotCodesRoundTrip() throws {
        for set in [KeycodeSet.v6, KeycodeSet.v5] {
            for slot in LetterKeys.slots {
                let code = try #require(LetterKeys.code(for: slot, keycodes: set))
                #expect(LetterKeys.slot(forCode: code, keycodes: set) == slot)
            }
        }
        let first = try #require(LetterKeys.code(for: LetterKeys.slots[0], keycodes: .v6))
        #expect(first == KeycodeSet.v6.parse("LCTL(LALT(LGUI(KC_F13)))"))
        #expect(LetterKeys.slot(forCode: KeycodeSet.v6.parse("KC_F13")!, keycodes: .v6) == nil)
        #expect(LetterKeys.slot(forCode: KeycodeSet.v6.parse("LCTL(KC_F13)")!, keycodes: .v6) == nil)
    }

    @Test func pressTypesTheLetterAndShiftOrCapsTheCapital() {
        let slot = LetterKeys.slots[0]
        var filter = LetterKeyFilter(letters: [LetterKey(slot: 0, lower: "ğ")])
        #expect(filter.handle(keyCode: slot.keyCode, isDown: true, modifiers: ctrlOptCmd) == .type("ğ"))
        #expect(filter.handle(keyCode: slot.keyCode, isDown: false, modifiers: ctrlOptCmd) == .swallow)
        #expect(filter.handle(keyCode: slot.keyCode, isDown: true, modifiers: ctrlOptCmd.union(.shift)) == .type("Ğ"))
        #expect(filter.handle(keyCode: slot.keyCode, isDown: false, modifiers: []) == .swallow)
        #expect(filter.handle(keyCode: slot.keyCode, isDown: true, modifiers: ctrlOptCmd.union(.capsLock)) == .type("Ğ"))
        #expect(filter.handle(keyCode: slot.keyCode, isDown: true, modifiers: ctrlOptCmd.union(.capsLock)) == .type("Ğ"))
        #expect(filter.handle(keyCode: slot.keyCode, isDown: false, modifiers: ctrlOptCmd) == .swallow)
    }

    @Test func dottedAndDotlessICapitalize() {
        var filter = LetterKeyFilter(letters: [LetterKey(slot: 0, lower: "ı"), LetterKey(slot: 1, lower: "i")])
        let shifted = ctrlOptCmd.union(.shift)
        #expect(filter.handle(keyCode: LetterKeys.slots[0].keyCode, isDown: true, modifiers: shifted) == .type("I"))
        #expect(filter.handle(keyCode: LetterKeys.slots[1].keyCode, isDown: true, modifiers: shifted) == .type("İ"))
        #expect(filter.handle(keyCode: LetterKeys.slots[1].keyCode, isDown: true, modifiers: ctrlOptCmd) == .type("i"))
    }

    @Test func otherKeysPassUntouched() {
        let slot = LetterKeys.slots[0]
        var filter = LetterKeyFilter(letters: [LetterKey(slot: 0, lower: "ğ")])
        // Bare F13 is an action trigger, ⌃⌥F13 is another (unassigned) slot, A is a letter.
        #expect(filter.handle(keyCode: slot.keyCode, isDown: true, modifiers: []) == .pass)
        #expect(filter.handle(keyCode: slot.keyCode, isDown: false, modifiers: []) == .pass)
        #expect(filter.handle(keyCode: slot.keyCode, isDown: true, modifiers: [.control, .option]) == .pass)
        #expect(filter.handle(keyCode: slot.keyCode, isDown: true, modifiers: [.control, .option, .command, .shift]) == .type("Ğ"))
        #expect(filter.handle(keyCode: 0x00, isDown: true, modifiers: ctrlOptCmd) == .pass)
        #expect(filter.handle(keyCode: 0x00, isDown: false, modifiers: ctrlOptCmd) == .pass)
    }

    @Test func secondModifierSetIsItsOwnSlot() {
        let second = LetterKeys.slots[6]
        var filter = LetterKeyFilter(letters: [LetterKey(slot: 0, lower: "ğ"), LetterKey(slot: 6, lower: "ñ")])
        #expect(second.keyCode == LetterKeys.slots[0].keyCode)
        #expect(filter.handle(keyCode: second.keyCode, isDown: true, modifiers: [.control, .option]) == .type("ñ"))
        #expect(filter.handle(keyCode: second.keyCode, isDown: true, modifiers: ctrlOptCmd) == .type("ğ"))
    }

    @Test func slotsAreReusedPerLetterAndRunOut() {
        var letters = [LetterKey(slot: 0, lower: "ğ"), LetterKey(slot: 2, lower: "ş")]
        #expect(LetterKeys.slotIndex(for: "ş", in: letters) == 2)
        #expect(LetterKeys.slotIndex(for: "ü", in: letters) == 1)
        letters = LetterKeys.slots.map { LetterKey(slot: $0.index, lower: "x\($0.index)") }
        #expect(LetterKeys.slotIndex(for: "ü", in: letters) == nil)
        #expect(LetterKeys.slotIndex(for: "x3", in: letters) == 3)
    }

    @Test func letterCodesCannotBecomeSmartKeys() throws {
        let code = try #require(LetterKeys.code(for: LetterKeys.slots[0], keycodes: .v6))
        #expect(SmartKeys.refusal(for: code, keycodes: .v6) != nil)
        #expect(SmartKeys.refusal(for: KeycodeSet.v6.parse("LCTL(KC_C)")!, keycodes: .v6) == nil)
    }

    @Test func storeRoundTripsAndDropsBadEntries() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("letters-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = LetterKeyStore(url: url)
        #expect(store.load().isEmpty)
        try store.save([LetterKey(slot: 0, lower: "ğ"), LetterKey(slot: 99, lower: "ş"), LetterKey(slot: 1, lower: "")])
        #expect(store.load() == [LetterKey(slot: 0, lower: "ğ")])
    }
}
