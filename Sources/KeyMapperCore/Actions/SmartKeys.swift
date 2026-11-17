import Foundation

/// Media and system keys that are not part of the HID keyboard page.
public enum SystemKey: String, Codable, CaseIterable, Sendable, Identifiable {
    case volumeUp, volumeDown, mute, playPause, next, previous, brightnessUp, brightnessDown

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .volumeUp: return L("Ses +")
        case .volumeDown: return L("Ses −")
        case .mute: return L("Sessiz")
        case .playPause: return L("Oynat / Duraklat")
        case .next: return L("Sonraki parça")
        case .previous: return L("Önceki parça")
        case .brightnessUp: return L("Parlaklık +")
        case .brightnessDown: return L("Parlaklık −")
        }
    }

    /// Volume and brightness keep stepping while their trigger is held, like the real keys.
    public var repeatsWhileHeld: Bool {
        switch self {
        case .volumeUp, .volumeDown, .brightnessUp, .brightnessDown: return true
        case .mute, .playPause, .next, .previous: return false
        }
    }

    /// NX_KEYTYPE_* value used in system-defined events.
    public var nxKeyType: Int32 {
        switch self {
        case .volumeUp: return 0
        case .volumeDown: return 1
        case .brightnessUp: return 2
        case .brightnessDown: return 3
        case .mute: return 7
        case .playPause: return 16
        case .next: return 17
        case .previous: return 18
        }
    }

    /// QMK keycodes (shared by v5 and v6) for these keys.
    static let byUsage: [UInt16: SystemKey] = [
        0xA8: .mute, 0xA9: .volumeUp, 0xAA: .volumeDown, 0xAB: .next, 0xAC: .previous, 0xAE: .playPause,
        0xBD: .brightnessUp, 0xBE: .brightnessDown,
        0x7F: .mute, 0x80: .volumeUp, 0x81: .volumeDown,
    ]
}

/// HID keyboard usage → macOS virtual key code (ANSI positions).
public enum MacKeyCodes {
    static let byUsage: [UInt16: UInt16] = {
        var map: [UInt16: UInt16] = [:]
        let letters: [UInt16] = [0x00, 0x0B, 0x08, 0x02, 0x0E, 0x03, 0x05, 0x04, 0x22, 0x26, 0x28, 0x25, 0x2E,
                                 0x2D, 0x1F, 0x23, 0x0C, 0x0F, 0x01, 0x11, 0x20, 0x09, 0x0D, 0x07, 0x10, 0x06]
        for (index, code) in letters.enumerated() { map[UInt16(0x04 + index)] = code }
        let digits: [UInt16] = [0x12, 0x13, 0x14, 0x15, 0x17, 0x16, 0x1A, 0x1C, 0x19, 0x1D]
        for (index, code) in digits.enumerated() { map[UInt16(0x1E + index)] = code }
        let rest: [UInt16: UInt16] = [
            0x28: 0x24, 0x29: 0x35, 0x2A: 0x33, 0x2B: 0x30, 0x2C: 0x31, 0x2D: 0x1B, 0x2E: 0x18, 0x2F: 0x21,
            0x30: 0x1E, 0x31: 0x2A, 0x32: 0x2A, 0x33: 0x29, 0x34: 0x27, 0x35: 0x32, 0x36: 0x2B, 0x37: 0x2F,
            0x38: 0x2C, 0x39: 0x39,
            0x3A: 0x7A, 0x3B: 0x78, 0x3C: 0x63, 0x3D: 0x76, 0x3E: 0x60, 0x3F: 0x61, 0x40: 0x62, 0x41: 0x64,
            0x42: 0x65, 0x43: 0x6D, 0x44: 0x67, 0x45: 0x6F,
            0x49: 0x72, 0x4A: 0x73, 0x4B: 0x74, 0x4C: 0x75, 0x4D: 0x77, 0x4E: 0x79,
            0x4F: 0x7C, 0x50: 0x7B, 0x51: 0x7D, 0x52: 0x7E,
            0x53: 0x47, 0x54: 0x4B, 0x55: 0x43, 0x56: 0x4E, 0x57: 0x45, 0x58: 0x4C, 0x59: 0x53, 0x5A: 0x54,
            0x5B: 0x55, 0x5C: 0x56, 0x5D: 0x57, 0x5E: 0x58, 0x5F: 0x59, 0x60: 0x5B, 0x61: 0x5C, 0x62: 0x52,
            0x63: 0x41, 0x64: 0x0A, 0x67: 0x51,
        ]
        map.merge(rest) { a, _ in a }
        for trigger in TriggerKey.all { map[trigger.usage] = trigger.keyCode }
        return map
    }()

    public static func virtualKey(forUsage usage: UInt16) -> UInt16? { byUsage[usage] }
}

/// "Smart keys": a physical key turned into a trigger so it can act differently per app.
public enum SmartKeys {
    /// Why a key cannot become a smart key, or nil when it can.
    public static func refusal(for code: UInt16, keycodes: KeycodeSet) -> String? {
        if LetterKeys.slot(forCode: code, keycodes: keycodes) != nil {
            return L("Harf tuşları her uygulamada aynı harfi yazar; akıllı tuşa çevrilemez.")
        }
        if TriggerKey.forUsage(code) != nil { return nil }
        switch keycodes.decode(code) {
        case .named(0x00), .named(0x01): return nil
        case let .named(c) where (0xE0...0xE7).contains(c):
            return L("Değiştirici tuşlar (⌘ ⌥ ⌃ ⇧) basılı tutulabilmeli; akıllı tuşa çevrilemez.")
        case .layer, .layerTap, .layerMod, .oneShotMod:
            return L("Katman tuşları firmware'de çalışır; akıllı tuşa çevrilemez.")
        case .modTap:
            return L("Mod-tap tuşları akıllı tuşa çevrilemez; önce basılı tutma işlevini kaldırın.")
        default:
            return nil
        }
    }

    /// The action that reproduces what `code` did, so the key keeps working in apps without a rule.
    public static func emulation(of code: UInt16, keycodes: KeycodeSet) -> KeyAction? {
        if let system = SystemKey.byUsage[code] { return .systemKey(system) }
        switch keycodes.decode(code) {
        case let .named(c) where c <= 0xFF:
            return combo(usage: c, modifiers: [], keycodes: keycodes).map(KeyAction.keystroke)
        case let .raw(c) where c <= 0xFF:
            return combo(usage: c, modifiers: [], keycodes: keycodes).map(KeyAction.keystroke)
        case let .mods(mods, kc):
            var modifiers: KeyCombo.Modifiers = []
            if mods & 0x01 != 0 { modifiers.insert(.control) }
            if mods & 0x02 != 0 { modifiers.insert(.shift) }
            if mods & 0x04 != 0 { modifiers.insert(.option) }
            if mods & 0x08 != 0 { modifiers.insert(.command) }
            return combo(usage: kc, modifiers: modifiers, keycodes: keycodes).map(KeyAction.keystroke)
        default:
            return nil
        }
    }

    static func combo(usage: UInt16, modifiers: KeyCombo.Modifiers, keycodes: KeycodeSet) -> KeyCombo? {
        guard let virtualKey = MacKeyCodes.virtualKey(forUsage: usage) else { return nil }
        let legend = keycodes.shortLabel(usage)
        return KeyCombo(keyCode: virtualKey, modifiers: modifiers, key: legend.isEmpty ? keycodes.name(for: usage) : legend)
    }
}
