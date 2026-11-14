import KeyMapperCore

/// One-click settings for a rotary knob: what turning left / right sends.
struct KnobPreset {
    let title: String
    /// Keycode expressions (parsed with the keyboard's keycode set).
    let ccw: String
    let cw: String

    static let all: [KnobPreset] = [
        KnobPreset(title: LK("Ses"), ccw: "KC_VOLD", cw: "KC_VOLU"),
        KnobPreset(title: LK("Parlaklık"), ccw: "KC_BRID", cw: "KC_BRIU"),
        KnobPreset(title: LK("Kaydırma"), ccw: "MS_WHLU", cw: "MS_WHLD"),
        KnobPreset(title: LK("Yatay kaydırma"), ccw: "MS_WHLL", cw: "MS_WHLR"),
        KnobPreset(title: LK("Parça değiştir"), ccw: "KC_MPRV", cw: "KC_MNXT"),
        KnobPreset(title: LK("Yakınlaştırma"), ccw: "LGUI(KC_MINS)", cw: "LGUI(KC_EQL)"),
        KnobPreset(title: LK("Geri al / Yinele"), ccw: "LGUI(KC_Z)", cw: "LGUI(LSFT(KC_Z))"),
        KnobPreset(title: LK("Sekme değiştir"), ccw: "LCTL(LSFT(KC_TAB))", cw: "LCTL(KC_TAB)"),
    ]
}
