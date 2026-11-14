import Foundation

/// QMK keycode numbering. QMK 0.19 (Dec 2022) reshuffled everything above 0x00FF.
public enum KeycodeVersion: String, Codable, Sendable {
    /// Legacy numbering (VIA protocol < 11, Vial protocol < 6).
    case v5
    /// Current numbering (VIA protocol >= 11, Vial protocol >= 6).
    case v6
}

public enum KeycodeGroup: String, CaseIterable, Sendable {
    case basic, modifiers, navigation, function, numpad, media, mouse, international, quantum, lighting
}

/// One named keycode.
public struct KeycodeEntry: Sendable {
    public let code: UInt16
    /// Short QMK name (also what VIA uses), e.g. `KC_BSPC`.
    public let name: String
    /// Name Vial writes into `.vil` files, e.g. `KC_BSPACE`.
    public let vialName: String
    /// Other accepted spellings.
    public let aliases: [String]
    /// Legend shown on the key cap. A `\n` separates shifted / unshifted legends.
    public let label: String
    public let group: KeycodeGroup
    public let title: String

    init(_ code: UInt16, _ name: String, vial: String? = nil, aliases: [String] = [], label: String, group: KeycodeGroup, title: String? = nil) {
        self.code = code
        self.name = name
        self.vialName = vial ?? name
        self.aliases = aliases
        self.label = label
        self.group = group
        self.title = title ?? name
    }
}

enum KeycodeTables {
    // MARK: Basic keycodes (0x00 - 0xFF). Identical in v5 and v6 except mouse / app keys.

    static let common: [KeycodeEntry] = {
        var list: [KeycodeEntry] = [
            .init(0x00, "KC_NO", aliases: ["XXXXXXX", "KC_NONE"], label: "", group: .basic, title: LK("Boş (hiçbir şey)")),
            .init(0x01, "KC_TRNS", aliases: ["_______", "KC_TRANSPARENT"], label: "▽", group: .basic, title: LK("Şeffaf (alt katmana geçer)")),
        ]
        for (i, letter) in "ABCDEFGHIJKLMNOPQRSTUVWXYZ".enumerated() {
            list.append(.init(UInt16(0x04 + i), "KC_\(letter)", label: String(letter), group: .basic))
        }
        let digits: [(String, String)] = [("1", "!"), ("2", "@"), ("3", "#"), ("4", "$"), ("5", "%"), ("6", "^"), ("7", "&"), ("8", "*"), ("9", "("), ("0", ")")]
        for (i, pair) in digits.enumerated() {
            list.append(.init(UInt16(0x1E + i), "KC_\(pair.0)", label: "\(pair.1)\n\(pair.0)", group: .basic))
        }
        list += [
            .init(0x28, "KC_ENT", vial: "KC_ENTER", aliases: ["KC_ENTER"], label: "Enter", group: .basic),
            .init(0x29, "KC_ESC", vial: "KC_ESCAPE", aliases: ["KC_ESCAPE"], label: "Esc", group: .basic),
            .init(0x2A, "KC_BSPC", vial: "KC_BSPACE", aliases: ["KC_BSPACE", "KC_BACKSPACE"], label: "⌫", group: .basic, title: LK("Backspace")),
            .init(0x2B, "KC_TAB", label: "Tab", group: .basic),
            .init(0x2C, "KC_SPC", vial: "KC_SPACE", aliases: ["KC_SPACE"], label: "Space", group: .basic),
            .init(0x2D, "KC_MINS", vial: "KC_MINUS", aliases: ["KC_MINUS"], label: "_\n-", group: .basic),
            .init(0x2E, "KC_EQL", vial: "KC_EQUAL", aliases: ["KC_EQUAL"], label: "+\n=", group: .basic),
            .init(0x2F, "KC_LBRC", vial: "KC_LBRACKET", aliases: ["KC_LBRACKET", "KC_LEFT_BRACKET"], label: "{\n[", group: .basic),
            .init(0x30, "KC_RBRC", vial: "KC_RBRACKET", aliases: ["KC_RBRACKET", "KC_RIGHT_BRACKET"], label: "}\n]", group: .basic),
            .init(0x31, "KC_BSLS", vial: "KC_BSLASH", aliases: ["KC_BSLASH", "KC_BACKSLASH"], label: "|\n\\", group: .basic),
            .init(0x32, "KC_NUHS", vial: "KC_NONUS_HASH", aliases: ["KC_NONUS_HASH"], label: "~\n#", group: .international, title: LK("ISO #")),
            .init(0x33, "KC_SCLN", vial: "KC_SCOLON", aliases: ["KC_SCOLON", "KC_SEMICOLON"], label: ":\n;", group: .basic),
            .init(0x34, "KC_QUOT", vial: "KC_QUOTE", aliases: ["KC_QUOTE"], label: "\"\n'", group: .basic),
            .init(0x35, "KC_GRV", vial: "KC_GRAVE", aliases: ["KC_GRAVE", "KC_GESC_KEY"], label: "~\n`", group: .basic),
            .init(0x36, "KC_COMM", vial: "KC_COMMA", aliases: ["KC_COMMA"], label: "<\n,", group: .basic),
            .init(0x37, "KC_DOT", label: ">\n.", group: .basic),
            .init(0x38, "KC_SLSH", vial: "KC_SLASH", aliases: ["KC_SLASH"], label: "?\n/", group: .basic),
            .init(0x39, "KC_CAPS", vial: "KC_CAPSLOCK", aliases: ["KC_CAPSLOCK", "KC_CAPS_LOCK", "KC_CLCK"], label: "Caps", group: .basic, title: LK("Caps Lock")),
        ]
        for i in 0..<12 {
            list.append(.init(UInt16(0x3A + i), "KC_F\(i + 1)", label: "F\(i + 1)", group: .function))
        }
        list += [
            .init(0x46, "KC_PSCR", vial: "KC_PSCREEN", aliases: ["KC_PSCREEN", "KC_PRINT_SCREEN"], label: "PrtSc", group: .navigation),
            .init(0x47, "KC_SCRL", vial: "KC_SCROLLLOCK", aliases: ["KC_SCROLLLOCK", "KC_SLCK", "KC_SCROLL_LOCK", "KC_BRMD"], label: "ScrLk", group: .navigation),
            .init(0x48, "KC_PAUS", vial: "KC_PAUSE", aliases: ["KC_PAUSE", "KC_BRK", "KC_BRMU"], label: "Pause", group: .navigation),
            .init(0x49, "KC_INS", vial: "KC_INSERT", aliases: ["KC_INSERT"], label: "Ins", group: .navigation),
            .init(0x4A, "KC_HOME", label: "Home", group: .navigation),
            .init(0x4B, "KC_PGUP", aliases: ["KC_PAGE_UP"], label: "PgUp", group: .navigation),
            .init(0x4C, "KC_DEL", vial: "KC_DELETE", aliases: ["KC_DELETE"], label: "Del", group: .navigation),
            .init(0x4D, "KC_END", label: "End", group: .navigation),
            .init(0x4E, "KC_PGDN", vial: "KC_PGDOWN", aliases: ["KC_PGDOWN", "KC_PAGE_DOWN"], label: "PgDn", group: .navigation),
            .init(0x4F, "KC_RGHT", vial: "KC_RIGHT", aliases: ["KC_RIGHT"], label: "→", group: .navigation),
            .init(0x50, "KC_LEFT", label: "←", group: .navigation),
            .init(0x51, "KC_DOWN", label: "↓", group: .navigation),
            .init(0x52, "KC_UP", label: "↑", group: .navigation),
            .init(0x53, "KC_NUM", vial: "KC_NUMLOCK", aliases: ["KC_NUMLOCK", "KC_NLCK", "KC_NUM_LOCK"], label: "Num", group: .numpad),
            .init(0x54, "KC_PSLS", vial: "KC_KP_SLASH", aliases: ["KC_KP_SLASH"], label: "/", group: .numpad),
            .init(0x55, "KC_PAST", vial: "KC_KP_ASTERISK", aliases: ["KC_KP_ASTERISK"], label: "*", group: .numpad),
            .init(0x56, "KC_PMNS", vial: "KC_KP_MINUS", aliases: ["KC_KP_MINUS"], label: "-", group: .numpad),
            .init(0x57, "KC_PPLS", vial: "KC_KP_PLUS", aliases: ["KC_KP_PLUS"], label: "+", group: .numpad),
            .init(0x58, "KC_PENT", vial: "KC_KP_ENTER", aliases: ["KC_KP_ENTER"], label: "Enter", group: .numpad, title: LK("Numpad Enter")),
        ]
        for i in 0..<9 {
            list.append(.init(UInt16(0x59 + i), "KC_P\(i + 1)", vial: "KC_KP_\(i + 1)", aliases: ["KC_KP_\(i + 1)"], label: "\(i + 1)", group: .numpad, title: "Numpad \(i + 1)"))
        }
        list += [
            .init(0x62, "KC_P0", vial: "KC_KP_0", aliases: ["KC_KP_0"], label: "0", group: .numpad, title: LK("Numpad 0")),
            .init(0x63, "KC_PDOT", vial: "KC_KP_DOT", aliases: ["KC_KP_DOT"], label: ".", group: .numpad),
            .init(0x64, "KC_NUBS", vial: "KC_NONUS_BSLASH", aliases: ["KC_NONUS_BSLASH", "KC_NONUS_BACKSLASH"], label: "|\n\\", group: .international, title: LK("ISO \\")),
            .init(0x65, "KC_APP", vial: "KC_APPLICATION", aliases: ["KC_APPLICATION"], label: "Menu", group: .navigation),
            .init(0x66, "KC_KB_POWER", vial: "KC_POWER", aliases: ["KC_POWER"], label: "Power", group: .media),
            .init(0x67, "KC_PEQL", vial: "KC_KP_EQUAL", aliases: ["KC_KP_EQUAL"], label: "=", group: .numpad),
        ]
        for i in 0..<12 {
            list.append(.init(UInt16(0x68 + i), "KC_F\(i + 13)", label: "F\(i + 13)", group: .function))
        }
        list += [
            .init(0x74, "KC_EXEC", vial: "KC_EXECUTE", aliases: ["KC_EXECUTE"], label: "Exec", group: .media),
            .init(0x75, "KC_HELP", label: "Help", group: .media),
            .init(0x76, "KC_MENU", label: "Menu", group: .media),
            .init(0x77, "KC_SLCT", vial: "KC_SELECT", aliases: ["KC_SELECT"], label: "Select", group: .media),
            .init(0x78, "KC_STOP", label: "Stop", group: .media),
            .init(0x79, "KC_AGIN", vial: "KC_AGAIN", aliases: ["KC_AGAIN"], label: "Again", group: .media),
            .init(0x7A, "KC_UNDO", label: "Undo", group: .media),
            .init(0x7B, "KC_CUT", label: "Cut", group: .media),
            .init(0x7C, "KC_COPY", label: "Copy", group: .media),
            .init(0x7D, "KC_PSTE", vial: "KC_PASTE", aliases: ["KC_PASTE"], label: "Paste", group: .media),
            .init(0x7E, "KC_FIND", label: "Find", group: .media),
            .init(0x7F, "KC_KB_MUTE", vial: "KC__MUTE", aliases: ["KC__MUTE"], label: "Mute", group: .media),
            .init(0x80, "KC_KB_VOLUME_UP", vial: "KC__VOLUP", aliases: ["KC__VOLUP"], label: "Vol+", group: .media),
            .init(0x81, "KC_KB_VOLUME_DOWN", vial: "KC__VOLDOWN", aliases: ["KC__VOLDOWN"], label: "Vol-", group: .media, title: LK("Ses −")),
            .init(0x85, "KC_PCMM", vial: "KC_KP_COMMA", aliases: ["KC_KP_COMMA"], label: ",", group: .numpad),
        ]
        let intlVial = ["KC_RO", "KC_KANA", "KC_JYEN", "KC_HENK", "KC_MHEN", "KC_INT6", "KC_INT7", "KC_INT8", "KC_INT9"]
        for i in 0..<9 {
            list.append(.init(UInt16(0x87 + i), "KC_INT\(i + 1)", vial: intlVial[i], aliases: [intlVial[i], "KC_INTERNATIONAL_\(i + 1)"], label: "Int\(i + 1)", group: .international))
        }
        for i in 0..<9 {
            list.append(.init(UInt16(0x90 + i), "KC_LNG\(i + 1)", vial: "KC_LANG\(i + 1)", aliases: ["KC_LANG\(i + 1)", "KC_LANGUAGE_\(i + 1)"], label: "Lng\(i + 1)", group: .international))
        }
        list += [
            .init(0xA5, "KC_PWR", vial: "KC_SYSTEM_POWER", aliases: ["KC_SYSTEM_POWER"], label: "Pwr", group: .media),
            .init(0xA6, "KC_SLEP", vial: "KC_SYSTEM_SLEEP", aliases: ["KC_SYSTEM_SLEEP"], label: "Sleep", group: .media),
            .init(0xA7, "KC_WAKE", vial: "KC_SYSTEM_WAKE", aliases: ["KC_SYSTEM_WAKE"], label: "Wake", group: .media),
            .init(0xA8, "KC_MUTE", vial: "KC_AUDIO_MUTE", aliases: ["KC_AUDIO_MUTE"], label: "Mute", group: .media, title: LK("Sessiz")),
            .init(0xA9, "KC_VOLU", vial: "KC_AUDIO_VOL_UP", aliases: ["KC_AUDIO_VOL_UP"], label: "Vol+", group: .media, title: LK("Ses +")),
            .init(0xAA, "KC_VOLD", vial: "KC_AUDIO_VOL_DOWN", aliases: ["KC_AUDIO_VOL_DOWN"], label: "Vol-", group: .media),
            .init(0xAB, "KC_MNXT", vial: "KC_MEDIA_NEXT_TRACK", aliases: ["KC_MEDIA_NEXT_TRACK"], label: "⏭", group: .media, title: LK("Sonraki parça")),
            .init(0xAC, "KC_MPRV", vial: "KC_MEDIA_PREV_TRACK", aliases: ["KC_MEDIA_PREV_TRACK"], label: "⏮", group: .media, title: LK("Önceki parça")),
            .init(0xAD, "KC_MSTP", vial: "KC_MEDIA_STOP", aliases: ["KC_MEDIA_STOP"], label: "⏹", group: .media, title: LK("Durdur")),
            .init(0xAE, "KC_MPLY", vial: "KC_MEDIA_PLAY_PAUSE", aliases: ["KC_MEDIA_PLAY_PAUSE"], label: "⏯", group: .media, title: LK("Oynat / Duraklat")),
            .init(0xAF, "KC_MSEL", vial: "KC_MEDIA_SELECT", aliases: ["KC_MEDIA_SELECT"], label: "Media", group: .media),
            .init(0xB0, "KC_EJCT", vial: "KC_MEDIA_EJECT", aliases: ["KC_MEDIA_EJECT"], label: "⏏", group: .media, title: LK("Eject")),
            .init(0xB1, "KC_MAIL", label: "Mail", group: .media),
            .init(0xB2, "KC_CALC", vial: "KC_CALCULATOR", aliases: ["KC_CALCULATOR"], label: "Calc", group: .media),
            .init(0xB3, "KC_MYCM", vial: "KC_MY_COMPUTER", aliases: ["KC_MY_COMPUTER"], label: "PC", group: .media),
            .init(0xB4, "KC_WSCH", vial: "KC_WWW_SEARCH", aliases: ["KC_WWW_SEARCH"], label: "Search", group: .media),
            .init(0xB5, "KC_WHOM", vial: "KC_WWW_HOME", aliases: ["KC_WWW_HOME"], label: "Home", group: .media, title: LK("Web Home")),
            .init(0xB6, "KC_WBAK", vial: "KC_WWW_BACK", aliases: ["KC_WWW_BACK"], label: "Back", group: .media),
            .init(0xB7, "KC_WFWD", vial: "KC_WWW_FORWARD", aliases: ["KC_WWW_FORWARD"], label: "Fwd", group: .media),
            .init(0xB8, "KC_WSTP", vial: "KC_WWW_STOP", aliases: ["KC_WWW_STOP"], label: "Stop", group: .media, title: LK("Web Stop")),
            .init(0xB9, "KC_WREF", vial: "KC_WWW_REFRESH", aliases: ["KC_WWW_REFRESH"], label: "Refr", group: .media),
            .init(0xBA, "KC_WFAV", vial: "KC_WWW_FAVORITES", aliases: ["KC_WWW_FAVORITES"], label: "Fav", group: .media),
            .init(0xBB, "KC_MFFD", vial: "KC_MEDIA_FAST_FORWARD", aliases: ["KC_MEDIA_FAST_FORWARD"], label: "⏩", group: .media),
            .init(0xBC, "KC_MRWD", vial: "KC_MEDIA_REWIND", aliases: ["KC_MEDIA_REWIND"], label: "⏪", group: .media),
            .init(0xBD, "KC_BRIU", vial: "KC_BRIGHTNESS_UP", aliases: ["KC_BRIGHTNESS_UP"], label: "Bri+", group: .media, title: LK("Parlaklık +")),
            .init(0xBE, "KC_BRID", vial: "KC_BRIGHTNESS_DOWN", aliases: ["KC_BRIGHTNESS_DOWN"], label: "Bri-", group: .media, title: LK("Parlaklık −")),
            .init(0xE0, "KC_LCTL", vial: "KC_LCTRL", aliases: ["KC_LCTRL", "KC_LEFT_CTRL"], label: "⌃ Ctrl", group: .modifiers, title: LK("Sol Control")),
            .init(0xE1, "KC_LSFT", vial: "KC_LSHIFT", aliases: ["KC_LSHIFT", "KC_LEFT_SHIFT"], label: "⇧ Shift", group: .modifiers, title: LK("Sol Shift")),
            .init(0xE2, "KC_LALT", aliases: ["KC_LOPT", "KC_LEFT_ALT"], label: "⌥ Opt", group: .modifiers, title: LK("Sol Option / Alt")),
            .init(0xE3, "KC_LGUI", aliases: ["KC_LCMD", "KC_LWIN", "KC_LEFT_GUI"], label: "⌘ Cmd", group: .modifiers, title: LK("Sol Command / Win")),
            .init(0xE4, "KC_RCTL", vial: "KC_RCTRL", aliases: ["KC_RCTRL", "KC_RIGHT_CTRL"], label: "⌃ Ctrl", group: .modifiers, title: LK("Sağ Control")),
            .init(0xE5, "KC_RSFT", vial: "KC_RSHIFT", aliases: ["KC_RSHIFT", "KC_RIGHT_SHIFT"], label: "⇧ Shift", group: .modifiers, title: LK("Sağ Shift")),
            .init(0xE6, "KC_RALT", aliases: ["KC_ROPT", "KC_ALGR", "KC_RIGHT_ALT"], label: "⌥ Opt", group: .modifiers, title: LK("Sağ Option / AltGr")),
            .init(0xE7, "KC_RGUI", aliases: ["KC_RCMD", "KC_RWIN", "KC_RIGHT_GUI"], label: "⌘ Cmd", group: .modifiers, title: LK("Sağ Command / Win")),
        ]
        return list
    }()

    // MARK: Version specific named keycodes

    static let v6Only: [KeycodeEntry] = [
        .init(0xBF, "KC_CPNL", vial: "KC_CONTROL_PANEL", aliases: ["KC_CONTROL_PANEL"], label: "Panel", group: .media),
        .init(0xC0, "KC_ASST", vial: "KC_ASSISTANT", aliases: ["KC_ASSISTANT"], label: "Asst", group: .media),
        .init(0xC1, "KC_MCTL", vial: "KC_MISSION_CONTROL", aliases: ["KC_MISSION_CONTROL"], label: "MCtl", group: .media, title: LK("Mission Control")),
        .init(0xC2, "KC_LPAD", vial: "KC_LAUNCHPAD", aliases: ["KC_LAUNCHPAD"], label: "LPad", group: .media, title: LK("Launchpad")),
        .init(0xCD, "MS_UP", vial: "KC_MS_UP", aliases: ["KC_MS_U", "KC_MS_UP", "QK_MOUSE_CURSOR_UP"], label: "🖱↑", group: .mouse, title: LK("Fare yukarı")),
        .init(0xCE, "MS_DOWN", vial: "KC_MS_DOWN", aliases: ["KC_MS_D", "KC_MS_DOWN"], label: "🖱↓", group: .mouse, title: LK("Fare aşağı")),
        .init(0xCF, "MS_LEFT", vial: "KC_MS_LEFT", aliases: ["KC_MS_L", "KC_MS_LEFT"], label: "🖱←", group: .mouse, title: LK("Fare sol")),
        .init(0xD0, "MS_RGHT", vial: "KC_MS_RIGHT", aliases: ["KC_MS_R", "KC_MS_RIGHT"], label: "🖱→", group: .mouse, title: LK("Fare sağ")),
        .init(0xD1, "MS_BTN1", vial: "KC_MS_BTN1", aliases: ["KC_BTN1", "KC_MS_BTN1"], label: "Click1", group: .mouse, title: LK("Sol tık")),
        .init(0xD2, "MS_BTN2", vial: "KC_MS_BTN2", aliases: ["KC_BTN2", "KC_MS_BTN2"], label: "Click2", group: .mouse, title: LK("Sağ tık")),
        .init(0xD3, "MS_BTN3", vial: "KC_MS_BTN3", aliases: ["KC_BTN3", "KC_MS_BTN3"], label: "Click3", group: .mouse, title: LK("Orta tık")),
        .init(0xD4, "MS_BTN4", vial: "KC_MS_BTN4", aliases: ["KC_BTN4", "KC_MS_BTN4"], label: "Click4", group: .mouse),
        .init(0xD5, "MS_BTN5", vial: "KC_MS_BTN5", aliases: ["KC_BTN5", "KC_MS_BTN5"], label: "Click5", group: .mouse),
        .init(0xD9, "MS_WHLU", vial: "KC_MS_WH_UP", aliases: ["KC_WH_U", "KC_MS_WH_UP"], label: "Whl↑", group: .mouse, title: LK("Tekerlek yukarı")),
        .init(0xDA, "MS_WHLD", vial: "KC_MS_WH_DOWN", aliases: ["KC_WH_D", "KC_MS_WH_DOWN"], label: "Whl↓", group: .mouse, title: LK("Tekerlek aşağı")),
        .init(0xDB, "MS_WHLL", vial: "KC_MS_WH_LEFT", aliases: ["KC_WH_L", "KC_MS_WH_LEFT"], label: "Whl←", group: .mouse),
        .init(0xDC, "MS_WHLR", vial: "KC_MS_WH_RIGHT", aliases: ["KC_WH_R", "KC_MS_WH_RIGHT"], label: "Whl→", group: .mouse),
        .init(0xDD, "MS_ACL0", vial: "KC_MS_ACCEL0", aliases: ["KC_ACL0", "KC_MS_ACCEL0"], label: "Acl0", group: .mouse),
        .init(0xDE, "MS_ACL1", vial: "KC_MS_ACCEL1", aliases: ["KC_ACL1", "KC_MS_ACCEL1"], label: "Acl1", group: .mouse),
        .init(0xDF, "MS_ACL2", vial: "KC_MS_ACCEL2", aliases: ["KC_ACL2", "KC_MS_ACCEL2"], label: "Acl2", group: .mouse),

        .init(0x7C00, "QK_BOOT", vial: "QK_BOOT", aliases: ["RESET", "QK_BOOTLOADER"], label: "Boot", group: .quantum, title: LK("Bootloader (firmware yükleme modu)")),
        .init(0x7C01, "QK_RBT", aliases: ["QK_REBOOT"], label: "Reboot", group: .quantum),
        .init(0x7C02, "DB_TOGG", aliases: ["QK_DEBUG_TOGGLE", "DEBUG"], label: "Debug", group: .quantum),
        .init(0x7C03, "EE_CLR", aliases: ["QK_CLEAR_EEPROM", "EEPROM_RESET"], label: "EE Clr", group: .quantum, title: LK("EEPROM temizle")),
        .init(0x7C10, "AS_DOWN", aliases: ["QK_AUTO_SHIFT_DOWN", "KC_ASDN"], label: "AS-", group: .quantum),
        .init(0x7C11, "AS_UP", aliases: ["QK_AUTO_SHIFT_UP", "KC_ASUP"], label: "AS+", group: .quantum),
        .init(0x7C12, "AS_RPT", aliases: ["QK_AUTO_SHIFT_REPORT", "KC_ASRP"], label: "ASRpt", group: .quantum),
        .init(0x7C13, "AS_ON", aliases: ["QK_AUTO_SHIFT_ON", "KC_ASON"], label: "AS On", group: .quantum),
        .init(0x7C14, "AS_OFF", aliases: ["QK_AUTO_SHIFT_OFF", "KC_ASOFF"], label: "AS Off", group: .quantum),
        .init(0x7C15, "AS_TOGG", aliases: ["QK_AUTO_SHIFT_TOGGLE", "KC_ASTG"], label: "AS Tg", group: .quantum),
        .init(0x7C16, "QK_GESC", vial: "QK_GESC", aliases: ["KC_GESC", "GRAVE_ESC", "QK_GRAVE_ESCAPE"], label: "~\nEsc", group: .quantum, title: LK("Grave Escape")),
        .init(0x7C18, "SC_LCPO", aliases: ["KC_LCPO"], label: "LCtl\n(", group: .quantum),
        .init(0x7C19, "SC_RCPC", aliases: ["KC_RCPC"], label: "RCtl\n)", group: .quantum),
        .init(0x7C1A, "SC_LSPO", aliases: ["KC_LSPO"], label: "LSft\n(", group: .quantum),
        .init(0x7C1B, "SC_RSPC", aliases: ["KC_RSPC"], label: "RSft\n)", group: .quantum),
        .init(0x7C1C, "SC_LAPO", aliases: ["KC_LAPO"], label: "LAlt\n(", group: .quantum),
        .init(0x7C1D, "SC_RAPC", aliases: ["KC_RAPC"], label: "RAlt\n)", group: .quantum),
        .init(0x7C1E, "SC_SENT", aliases: ["KC_SFTENT"], label: "Sft\nEnt", group: .quantum),
        .init(0x7C73, "CW_TOGG", aliases: ["QK_CAPS_WORD_TOGGLE", "CAPSWRD"], label: "Caps\nWord", group: .quantum),
        .init(0x7C79, "QK_REP", aliases: ["QK_REPEAT_KEY"], label: "Rep", group: .quantum, title: LK("Repeat Key")),
        .init(0x7C7A, "QK_AREP", aliases: ["QK_ALT_REPEAT_KEY"], label: "ARep", group: .quantum, title: LK("Alt Repeat Key")),

        .init(0x7800, "BL_ON", aliases: ["QK_BACKLIGHT_ON"], label: "BL On", group: .lighting),
        .init(0x7801, "BL_OFF", aliases: ["QK_BACKLIGHT_OFF"], label: "BL Off", group: .lighting),
        .init(0x7802, "BL_TOGG", aliases: ["QK_BACKLIGHT_TOGGLE"], label: "BL Tg", group: .lighting),
        .init(0x7803, "BL_DOWN", aliases: ["BL_DEC", "QK_BACKLIGHT_DOWN"], label: "BL-", group: .lighting),
        .init(0x7804, "BL_UP", aliases: ["BL_INC", "QK_BACKLIGHT_UP"], label: "BL+", group: .lighting),
        .init(0x7805, "BL_STEP", aliases: ["QK_BACKLIGHT_STEP"], label: "BL Step", group: .lighting),
        .init(0x7806, "BL_BRTG", aliases: ["QK_BACKLIGHT_TOGGLE_BREATHING"], label: "BL Brth", group: .lighting),
        .init(0x7820, "RGB_TOG", aliases: ["UG_TOGG"], label: "RGB Tg", group: .lighting),
        .init(0x7821, "RGB_MOD", aliases: ["UG_NEXT", "RGB_MODE_FORWARD"], label: "RGB →", group: .lighting),
        .init(0x7822, "RGB_RMOD", aliases: ["UG_PREV", "RGB_MODE_REVERSE"], label: "RGB ←", group: .lighting),
        .init(0x7823, "RGB_HUI", aliases: ["UG_HUEU"], label: "Hue+", group: .lighting),
        .init(0x7824, "RGB_HUD", aliases: ["UG_HUED"], label: "Hue-", group: .lighting),
        .init(0x7825, "RGB_SAI", aliases: ["UG_SATU"], label: "Sat+", group: .lighting),
        .init(0x7826, "RGB_SAD", aliases: ["UG_SATD"], label: "Sat-", group: .lighting),
        .init(0x7827, "RGB_VAI", aliases: ["UG_VALU"], label: "Bri+", group: .lighting, title: LK("RGB parlaklık +")),
        .init(0x7828, "RGB_VAD", aliases: ["UG_VALD"], label: "Bri-", group: .lighting, title: LK("RGB parlaklık -")),
        .init(0x7829, "RGB_SPI", aliases: ["UG_SPDU"], label: "Spd+", group: .lighting),
        .init(0x782A, "RGB_SPD", aliases: ["UG_SPDD"], label: "Spd-", group: .lighting),
    ]

    static let v5Only: [KeycodeEntry] = [
        .init(0xF0, "KC_MS_U", vial: "KC_MS_UP", aliases: ["KC_MS_UP", "MS_UP"], label: "🖱↑", group: .mouse, title: LK("Fare yukarı")),
        .init(0xF1, "KC_MS_D", vial: "KC_MS_DOWN", aliases: ["KC_MS_DOWN", "MS_DOWN"], label: "🖱↓", group: .mouse, title: LK("Fare aşağı")),
        .init(0xF2, "KC_MS_L", vial: "KC_MS_LEFT", aliases: ["KC_MS_LEFT", "MS_LEFT"], label: "🖱←", group: .mouse, title: LK("Fare sol")),
        .init(0xF3, "KC_MS_R", vial: "KC_MS_RIGHT", aliases: ["KC_MS_RIGHT", "MS_RGHT"], label: "🖱→", group: .mouse, title: LK("Fare sağ")),
        .init(0xF4, "KC_BTN1", vial: "KC_MS_BTN1", aliases: ["KC_MS_BTN1", "MS_BTN1"], label: "Click1", group: .mouse, title: LK("Sol tık")),
        .init(0xF5, "KC_BTN2", vial: "KC_MS_BTN2", aliases: ["KC_MS_BTN2", "MS_BTN2"], label: "Click2", group: .mouse, title: LK("Sağ tık")),
        .init(0xF6, "KC_BTN3", vial: "KC_MS_BTN3", aliases: ["KC_MS_BTN3", "MS_BTN3"], label: "Click3", group: .mouse, title: LK("Orta tık")),
        .init(0xF7, "KC_BTN4", vial: "KC_MS_BTN4", aliases: ["KC_MS_BTN4", "MS_BTN4"], label: "Click4", group: .mouse),
        .init(0xF8, "KC_BTN5", vial: "KC_MS_BTN5", aliases: ["KC_MS_BTN5", "MS_BTN5"], label: "Click5", group: .mouse),
        .init(0xF9, "KC_WH_U", vial: "KC_MS_WH_UP", aliases: ["KC_MS_WH_UP", "MS_WHLU"], label: "Whl↑", group: .mouse, title: LK("Tekerlek yukarı")),
        .init(0xFA, "KC_WH_D", vial: "KC_MS_WH_DOWN", aliases: ["KC_MS_WH_DOWN", "MS_WHLD"], label: "Whl↓", group: .mouse, title: LK("Tekerlek aşağı")),
        .init(0xFB, "KC_WH_L", vial: "KC_MS_WH_LEFT", aliases: ["KC_MS_WH_LEFT", "MS_WHLL"], label: "Whl←", group: .mouse),
        .init(0xFC, "KC_WH_R", vial: "KC_MS_WH_RIGHT", aliases: ["KC_MS_WH_RIGHT", "MS_WHLR"], label: "Whl→", group: .mouse),
        .init(0xFD, "KC_ACL0", vial: "KC_MS_ACCEL0", aliases: ["KC_MS_ACCEL0", "MS_ACL0"], label: "Acl0", group: .mouse),
        .init(0xFE, "KC_ACL1", vial: "KC_MS_ACCEL1", aliases: ["KC_MS_ACCEL1", "MS_ACL1"], label: "Acl1", group: .mouse),
        .init(0xFF, "KC_ACL2", vial: "KC_MS_ACCEL2", aliases: ["KC_MS_ACCEL2", "MS_ACL2"], label: "Acl2", group: .mouse),

        .init(0x5C00, "RESET", vial: "RESET", aliases: ["QK_BOOT", "QK_BOOTLOADER"], label: "Boot", group: .quantum, title: LK("Bootloader (firmware yükleme modu)")),
        .init(0x5C01, "DEBUG", aliases: ["DB_TOGG"], label: "Debug", group: .quantum),
        .init(0x5C16, "KC_GESC", vial: "KC_GESC", aliases: ["QK_GESC", "GRAVE_ESC"], label: "~\nEsc", group: .quantum, title: LK("Grave Escape")),
        .init(0x5CD7, "KC_LSPO", aliases: ["SC_LSPO"], label: "LSft\n(", group: .quantum),
        .init(0x5CD8, "KC_RSPC", aliases: ["SC_RSPC"], label: "RSft\n)", group: .quantum),
        .init(0x5CD9, "KC_SFTENT", aliases: ["SC_SENT"], label: "Sft\nEnt", group: .quantum),
        .init(0x5CBB, "BL_ON", label: "BL On", group: .lighting),
        .init(0x5CBC, "BL_OFF", label: "BL Off", group: .lighting),
        .init(0x5CBD, "BL_DEC", aliases: ["BL_DOWN"], label: "BL-", group: .lighting),
        .init(0x5CBE, "BL_INC", aliases: ["BL_UP"], label: "BL+", group: .lighting),
        .init(0x5CBF, "BL_TOGG", label: "BL Tg", group: .lighting),
        .init(0x5CC0, "BL_STEP", label: "BL Step", group: .lighting),
        .init(0x5CC1, "BL_BRTG", label: "BL Brth", group: .lighting),
        .init(0x5CC2, "RGB_TOG", label: "RGB Tg", group: .lighting),
        .init(0x5CC3, "RGB_MOD", label: "RGB →", group: .lighting),
        .init(0x5CC4, "RGB_RMOD", label: "RGB ←", group: .lighting),
        .init(0x5CC5, "RGB_HUI", label: "Hue+", group: .lighting),
        .init(0x5CC6, "RGB_HUD", label: "Hue-", group: .lighting),
        .init(0x5CC7, "RGB_SAI", label: "Sat+", group: .lighting),
        .init(0x5CC8, "RGB_SAD", label: "Sat-", group: .lighting),
        .init(0x5CC9, "RGB_VAI", label: "Bri+", group: .lighting, title: LK("RGB parlaklık +")),
        .init(0x5CCA, "RGB_VAD", label: "Bri-", group: .lighting, title: LK("RGB parlaklık -")),
        .init(0x5CCB, "RGB_SPI", label: "Spd+", group: .lighting),
        .init(0x5CCC, "RGB_SPD", label: "Spd-", group: .lighting),
    ]

    // MARK: Modifier masks

    /// 5 bit QMK modifier mask (bit 4 = right hand).
    static let modNames: [(mask: UInt8, function: String, tap: String, symbol: String)] = [
        (0x01, "LCTL", "LCTL_T", "⌃"), (0x02, "LSFT", "LSFT_T", "⇧"), (0x04, "LALT", "LALT_T", "⌥"), (0x08, "LGUI", "LGUI_T", "⌘"),
        (0x03, "C_S", "C_S_T", "⌃⇧"), (0x05, "LCA", "LCA_T", "⌃⌥"), (0x06, "LSA", "LSA_T", "⇧⌥"), (0x07, "MEH", "MEH_T", "Meh"),
        (0x09, "LCG", "LCG_T", "⌃⌘"), (0x0A, "LSG", "LSG_T", "⇧⌘"), (0x0C, "LAG", "LAG_T", "⌥⌘"), (0x0D, "LCAG", "LCAG_T", "⌃⌥⌘"),
        (0x0E, "LSAG", "LSAG_T", "⇧⌥⌘"), (0x0F, "HYPR", "HYPR_T", "Hyper"),
        (0x11, "RCTL", "RCTL_T", "⌃"), (0x12, "RSFT", "RSFT_T", "⇧"), (0x14, "RALT", "RALT_T", "⌥"), (0x18, "RGUI", "RGUI_T", "⌘"),
        (0x13, "RCS", "RCS_T", "⌃⇧"), (0x15, "RCA", "RCA_T", "⌃⌥"), (0x16, "RSA", "RSA_T", "⇧⌥"), (0x19, "RCG", "RCG_T", "⌃⌘"),
        (0x1A, "RSG", "RSG_T", "⇧⌘"), (0x1C, "RAG", "RAG_T", "⌥⌘"), (0x1D, "RCAG", "RCAG_T", "⌃⌥⌘"),
    ]

    static let modFunctionAliases: [String: UInt8] = [
        "C": 0x01, "S": 0x02, "A": 0x04, "G": 0x08, "LOPT": 0x04, "LCMD": 0x08, "LWIN": 0x08,
        "ROPT": 0x14, "ALGR": 0x14, "RCMD": 0x18, "RWIN": 0x18, "SGUI": 0x0A, "SCMD": 0x0A, "SWIN": 0x0A,
        "LCSG": 0x0B, "ALL": 0x0F,
    ]

    static let modTapAliases: [String: UInt8] = [
        "LOPT_T": 0x04, "LCMD_T": 0x08, "LWIN_T": 0x08, "ROPT_T": 0x14, "ALGR_T": 0x14, "RCMD_T": 0x18, "RWIN_T": 0x18,
        "ALL_T": 0x0F, "SGUI_T": 0x0A, "SCMD_T": 0x0A, "SWIN_T": 0x0A, "CTL_T": 0x01, "SFT_T": 0x02, "ALT_T": 0x04,
        "GUI_T": 0x08, "OPT_T": 0x04, "CMD_T": 0x08, "WIN_T": 0x08,
    ]

    static let modBitNames: [String: UInt8] = [
        "MOD_LCTL": 0x01, "MOD_LSFT": 0x02, "MOD_LALT": 0x04, "MOD_LGUI": 0x08,
        "MOD_RCTL": 0x11, "MOD_RSFT": 0x12, "MOD_RALT": 0x14, "MOD_RGUI": 0x18,
        "MOD_HYPR": 0x0F, "MOD_MEH": 0x07,
    ]
}
