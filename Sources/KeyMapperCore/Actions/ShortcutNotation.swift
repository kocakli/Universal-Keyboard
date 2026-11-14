import Foundation

/// Parses shortcut notation such as "⌘⇧T", "⌃`", "⌥Space", "Esc", "↩" or "⌘→" into a `KeyCombo`.
/// Used to write the preset catalogue readably; unknown keys return nil (caught by tests).
public enum ShortcutNotation {
    /// macOS virtual key codes (ANSI positions) by legend.
    static let keyCodes: [String: UInt16] = {
        var map: [String: UInt16] = [
            "A": 0x00, "S": 0x01, "D": 0x02, "F": 0x03, "H": 0x04, "G": 0x05, "Z": 0x06, "X": 0x07, "C": 0x08, "V": 0x09,
            "B": 0x0B, "Q": 0x0C, "W": 0x0D, "E": 0x0E, "R": 0x0F, "Y": 0x10, "T": 0x11, "1": 0x12, "2": 0x13, "3": 0x14,
            "4": 0x15, "6": 0x16, "5": 0x17, "=": 0x18, "9": 0x19, "7": 0x1A, "-": 0x1B, "8": 0x1C, "0": 0x1D, "]": 0x1E,
            "O": 0x1F, "U": 0x20, "[": 0x21, "I": 0x22, "P": 0x23, "L": 0x25, "J": 0x26, "'": 0x27, "K": 0x28, ";": 0x29,
            "\\": 0x2A, ",": 0x2B, "/": 0x2C, "N": 0x2D, "M": 0x2E, ".": 0x2F, "`": 0x32,
            "↩": 0x24, "Return": 0x24, "Enter": 0x24, "⇥": 0x30, "Tab": 0x30, "Space": 0x31, "⌫": 0x33, "Esc": 0x35, "⎋": 0x35,
            "⌦": 0x75, "Home": 0x73, "End": 0x77, "PgUp": 0x74, "PgDn": 0x79,
            "←": 0x7B, "→": 0x7C, "↓": 0x7D, "↑": 0x7E,
        ]
        let fKeys: [UInt16] = [0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64, 0x65, 0x6D, 0x67, 0x6F,
                               0x69, 0x6B, 0x71, 0x6A, 0x40, 0x4F, 0x50, 0x5A]
        for (index, code) in fKeys.enumerated() { map["F\(index + 1)"] = code }
        return map
    }()

    public static func parse(_ notation: String) -> KeyCombo? {
        var modifiers: KeyCombo.Modifiers = []
        var rest = Substring(notation)
        while let first = rest.first, "⌃⌥⇧⌘".contains(first), rest.count > 1 {
            switch first {
            case "⌃": modifiers.insert(.control)
            case "⌥": modifiers.insert(.option)
            case "⇧": modifiers.insert(.shift)
            default: modifiers.insert(.command)
            }
            rest = rest.dropFirst()
        }
        let key = String(rest)
        guard let code = keyCodes[key] ?? keyCodes[key.uppercased()] else { return nil }
        return KeyCombo(keyCode: code, modifiers: modifiers, key: key == "Enter" || key == "Return" ? "↩" : key)
    }
}
