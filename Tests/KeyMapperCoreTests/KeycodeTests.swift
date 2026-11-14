import Testing
@testable import KeyMapperCore

@Suite struct KeycodeTests {
    let v6 = KeycodeSet.v6
    let v5 = KeycodeSet.v5

    @Test func basicNames() {
        #expect(v6.parse("KC_A") == 0x04)
        #expect(v6.parse("kc_bspc") == 0x2A)
        #expect(v6.parse("KC_BSPACE") == 0x2A)
        #expect(v6.parse("KC_BACKSPACE") == 0x2A)
        #expect(v6.parse("_______") == 0x01)
        #expect(v6.name(for: 0x2A) == "KC_BSPC")
        #expect(v6.name(for: 0x2A, style: .vial) == "KC_BSPACE")
    }

    @Test func compoundV6() {
        #expect(v6.parse("LT(1, KC_SPC)") == 0x412C)
        #expect(v6.parse("LT1(KC_SPACE)") == 0x412C)
        #expect(v6.parse("LSFT_T(KC_A)") == 0x2204)
        #expect(v6.parse("MT(MOD_LCTL | MOD_LSFT, KC_A)") == 0x2304)
        #expect(v6.parse("LCTL(KC_C)") == 0x0106)
        #expect(v6.parse("C(KC_C)") == 0x0106)
        #expect(v6.parse("LCTL(LSFT(KC_A))") == 0x0304)
        #expect(v6.parse("HYPR(KC_A)") == 0x0F04)
        #expect(v6.parse("MO(1)") == 0x5221)
        #expect(v6.parse("TO(2)") == 0x5202)
        #expect(v6.parse("TG(3)") == 0x5263)
        #expect(v6.parse("OSM(MOD_LSFT)") == 0x52A2)
        #expect(v6.parse("QK_BOOT") == 0x7C00)
        #expect(v6.parse("RESET") == 0x7C00)
        #expect(v6.parse("M3") == 0x7703)
        #expect(v6.parse("USER02") == 0x7E02)
        #expect(v6.name(for: 0x2304) == "C_S_T(KC_A)")
        #expect(v6.name(for: 0x412C) == "LT(1, KC_SPC)")
        #expect(v6.name(for: 0x412C, style: .vial) == "LT1(KC_SPACE)")
    }

    @Test func compoundV5() {
        #expect(v5.parse("LSFT_T(KC_A)") == 0x6204)
        #expect(v5.parse("MO(1)") == 0x5101)
        #expect(v5.parse("TO(2)") == 0x5012)
        #expect(v5.parse("RESET") == 0x5C00)
        #expect(v5.parse("KC_MS_U") == 0xF0)
    }

    @Test(arguments: [KeycodeVersion.v6, .v5])
    func everyCodeRoundTrips(version: KeycodeVersion) {
        let set = KeycodeSet(version: version, customKeycodes: [CustomKeycode(name: "BT0")])
        var failures: [String] = []
        for raw in 0...0xFFFF {
            let code = UInt16(raw)
            for style in [KeycodeNameStyle.qmk, .vial] {
                let name = set.name(for: code, style: style)
                if set.parse(name) != code { failures.append(String(format: "0x%04X → %@", raw, name)) }
            }
        }
        #expect(failures.isEmpty, "\(failures.prefix(20))")
    }

    @Test func customKeycodes() {
        let set = KeycodeSet(version: .v6, customKeycodes: [CustomKeycode(name: "BT0", shortName: "BT0"), CustomKeycode(name: "BT1")])
        #expect(set.parse("BT1") == 0x7E01)
        #expect(set.label(for: 0x7E00).main == "BT0")
    }

    @Test func labels() {
        #expect(v6.label(for: 0x1E) == KeyLabel(top: "!", main: "1"))
        #expect(v6.label(for: 0x2204) == KeyLabel(main: "A", sub: "⇧"))
        #expect(v6.label(for: 0x412C) == KeyLabel(main: "Space", sub: "L1"))
        #expect(v6.label(for: 0x0106).main == "⌃C")
    }
}
