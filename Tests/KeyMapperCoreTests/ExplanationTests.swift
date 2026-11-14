import Testing
@testable import KeyMapperCore

@Suite struct ExplanationTests {
    @Test(arguments: [KeycodeVersion.v6, .v5])
    func everyPaletteKeycodeIsExplainedInWords(version: KeycodeVersion) {
        let set = KeycodeSet(version: version)
        for entry in set.entries {
            let text = set.explanation(for: entry.code)
            #expect(!text.isEmpty, "\(entry.name)")
            #expect(!text.contains("KC_"), "\(entry.name): \(text)")
            #expect(text != entry.name && text != entry.vialName, "\(entry.name)")
            let title = set.title(for: entry.code)
            #expect(!title.hasPrefix("KC_"), "\(entry.name) title: \(title)")
        }
    }

    @Test func compoundKeycodesAreDescribed() {
        let set = KeycodeSet.v6
        #expect(set.explanation(for: set.parse("LSFT_T(KC_A)")!) == "Dokununca A, basılı tutunca ⇧ Shift.")
        #expect(set.explanation(for: set.parse("LT(1, KC_SPC)")!) == "Dokununca Space, basılı tutunca 1. katman.")
        #expect(set.explanation(for: set.parse("MO(2)")!) == "Basılı tuttuğun sürece 2. katman etkin olur.")
        #expect(set.explanation(for: set.parse("LGUI(KC_C)")!) == "Tek tuşla ⌘C kısayolunu gönderir.")
        #expect(set.explanation(for: set.parse("KC_VOLU")!) == "Sesi açar.")
        #expect(set.explanation(for: set.parse("KC_1")!) == "1 rakamı; Shift ile !.")
        #expect(set.explanation(for: set.parse("KC_F16")!).contains("tetik"))
        #expect(set.title(for: set.parse("KC_A")!) == "A")
        #expect(set.title(for: set.parse("LCTL(KC_C)")!) == "⌃C")
    }

    @Test func customKeycodesUseTheirVendorTitle() {
        let set = KeycodeSet(version: .v6, customKeycodes: [CustomKeycode(name: "BT0", title: "Bluetooth Channel 0", shortName: "BT0")])
        #expect(set.explanation(for: 0x7E00) == "Bluetooth Channel 0")
        #expect(set.title(for: 0x7E00) == "BT0")
    }

    @Test func actionTypesHaveExplanations() {
        for kind in KeyAction.Kind.allCases { #expect(!kind.explanation.isEmpty) }
    }
}
