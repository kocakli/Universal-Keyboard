import Foundation

// LEOBOG AMG65 key layout and key table actions.
// Ported from AMG65 Studio (github.com/kocakli/amg65-studio), which builds on aumbro/leobog_amg65_rgb (MIT).
// Slot bytes and tables match Studio's Keymap.swift (checked against Fixtures/amg65-media-golden.json).
// Names are English source names; the app translates them.

/// One physical switch of the AMG65.
public struct AMG65Key: Identifiable, Hashable, Sendable {
    /// key_index: the slot in the key table (command 0x11) and in the per-key colour table (0x23).
    public let slot: Int
    /// Factory HID keyboard usage.
    public let code: UInt8
    public let name: String
    /// Studio's layout coordinates (points, origin top left; the keys span 796 × 254).
    public let rect: CGRect

    public init(slot: Int, code: UInt8, name: String, rect: CGRect) {
        self.slot = slot
        self.code = code
        self.name = name
        self.rect = rect
    }

    public var id: Int { slot }
    /// Fn and the volume knob aren't remappable (Fn would lose its layer).
    public var remappable: Bool { code != 0xAF && !isKnob }
    /// The volume knob is listed as two "keys" (vol +/−) with no light, drawn off the keyboard image.
    public var isKnob: Bool { code == 0xE9 || code == 0xEA }
}

public enum AMG65Layout {
    public static let keys: [AMG65Key] = [
        key(0, 41, "Esc", 0, 0, 46, 46),
        key(17, 30, "1", 50, 0, 46, 46),
        key(18, 31, "2", 100, 0, 46, 46),
        key(19, 32, "3", 150, 0, 46, 46),
        key(20, 33, "4", 200, 0, 46, 46),
        key(21, 34, "5", 250, 0, 46, 46),
        key(22, 35, "6", 300, 0, 46, 46),
        key(23, 36, "7", 350, 0, 46, 46),
        key(24, 37, "8", 400, 0, 46, 46),
        key(25, 38, "9", 450, 0, 46, 46),
        key(26, 39, "0", 500, 0, 46, 46),
        key(27, 45, "-", 550, 0, 46, 46),
        key(28, 46, "=", 600, 0, 46, 46),
        key(92, 42, "Backspace", 650, 0, 96, 46),
        key(104, 74, "Home", 750, 0, 46, 46),
        key(32, 43, "Tab", 0, 52, 71, 46),
        key(33, 20, "Q", 75, 52, 46, 46),
        key(34, 26, "W", 125, 52, 46, 46),
        key(35, 8, "E", 175, 52, 46, 46),
        key(36, 21, "R", 225, 52, 46, 46),
        key(37, 23, "T", 275, 52, 46, 46),
        key(38, 28, "Y", 325, 52, 46, 46),
        key(39, 24, "U", 375, 52, 46, 46),
        key(40, 12, "I", 425, 52, 46, 46),
        key(41, 18, "O", 475, 52, 46, 46),
        key(42, 19, "P", 525, 52, 46, 46),
        key(43, 47, "[", 575, 52, 46, 46),
        key(44, 48, "]", 625, 52, 46, 46),
        key(60, 49, "\\", 675, 52, 71, 46),
        key(106, 76, "Del", 750, 52, 46, 46),
        key(48, 57, "Caps", 0, 104, 83.5, 46),
        key(49, 4, "A", 87.5, 104, 46, 46),
        key(50, 22, "S", 137.5, 104, 46, 46),
        key(51, 7, "D", 187.5, 104, 46, 46),
        key(52, 9, "F", 237.5, 104, 46, 46),
        key(53, 10, "G", 287.5, 104, 46, 46),
        key(54, 11, "H", 337.5, 104, 46, 46),
        key(55, 13, "J", 387.5, 104, 46, 46),
        key(56, 14, "K", 437.5, 104, 46, 46),
        key(57, 15, "L", 487.5, 104, 46, 46),
        key(58, 51, ";", 537.5, 104, 46, 46),
        key(59, 52, "'", 587.5, 104, 46, 46),
        key(76, 40, "Enter", 637.5, 104, 108.5, 46),
        key(105, 75, "PgUp", 750, 104, 46, 46),
        key(64, 225, "Shift", 0, 156, 108.5, 46),
        key(65, 29, "Z", 112.5, 156, 46, 46),
        key(66, 27, "X", 162.5, 156, 46, 46),
        key(67, 6, "C", 212.5, 156, 46, 46),
        key(68, 25, "V", 262.5, 156, 46, 46),
        key(69, 5, "B", 312.5, 156, 46, 46),
        key(70, 17, "N", 362.5, 156, 46, 46),
        key(71, 16, "M", 412.5, 156, 46, 46),
        key(72, 54, ",", 462.5, 156, 46, 46),
        key(73, 55, ".", 512.5, 156, 46, 46),
        key(74, 56, "/", 562.5, 156, 46, 46),
        key(75, 229, "Shift", 612.5, 156, 83.5, 46),
        key(90, 82, "↑", 700, 156, 46, 46),
        key(108, 78, "PgDn", 750, 156, 46, 46),
        key(80, 224, "Ctrl", 0, 208, 58.5, 46),
        key(81, 227, "⌘", 62.5, 208, 58.5, 46),
        key(82, 226, "⌥", 125, 208, 58.5, 46),
        key(83, 44, "Space", 187.5, 208, 308.5, 46),
        key(85, 175, "Fn", 500, 208, 46, 46),
        key(87, 228, "Ctrl", 550, 208, 46, 46),
        key(88, 80, "←", 600, 208, 46, 46),
        key(89, 81, "↓", 650, 208, 46, 46),
        key(91, 79, "→", 700, 208, 46, 46),
    ]

    /// Keys that have a backlight LED (everything except the knob).
    public static var litKeys: [AMG65Key] { keys.filter { !$0.isKnob } }

    private static func key(_ slot: Int, _ code: UInt8, _ name: String,
                            _ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> AMG65Key {
        AMG65Key(slot: slot, code: code, name: name, rect: CGRect(x: x, y: y, width: width, height: height))
    }
}

/// What a key can be remapped to: one 4 byte slot of the key table (`AMG65Protocol.keyTable`).
/// The case names and labels are Studio's, so the Codable form is the same as Studio's saved key maps.
public enum AMG65KeyAction: Codable, Hashable, Sendable {
    /// Type 02: modifier bits + HID keyboard usage (confirmed on the keyboard).
    case key(modifiers: UInt8, code: UInt8)
    /// Type 03: HID consumer usage (decoded from the vendor app, untested).
    case media(UInt16)
    /// Type 01 01: mouse button mask (decoded, untested).
    case mouseButton(UInt8)
    /// Type 01 03: wheel +1 / -1 (decoded, untested).
    case wheel(up: Bool)

    /// The slot's 4 bytes. A modifier usage (0xE0…0xE7) is sent as its modifier bit, without a usage.
    public var slotBytes: [UInt8] {
        switch self {
        case let .key(mods, code):
            if (0xE0...0xE7).contains(code) { return [0x02, mods | (1 << (code - 0xE0)), 0x00, 0x00] }
            return [0x02, mods, code, 0x00]
        case let .media(u): return [0x03, UInt8(u & 0xFF), UInt8(u >> 8), 0x00]
        case let .mouseButton(mask): return [0x01, 0x01, mask, 0x00]
        case let .wheel(up): return [0x01, 0x03, up ? 0x01 : 0xFF, 0x00]
        }
    }

    /// Only plain keys were seen working on the keyboard.
    public var tested: Bool { if case .key = self { true } else { false } }
}

public enum AMG65Modifier: CaseIterable, Sendable {
    case control, shift, option, command

    /// Bit in the slot's modifier byte.
    public var bit: UInt8 {
        switch self { case .control: 0x01; case .shift: 0x02; case .option: 0x04; case .command: 0x08 }
    }

    public var symbol: String {
        switch self { case .control: "⌃"; case .shift: "⇧"; case .option: "⌥"; case .command: "⌘" }
    }

    /// English source name.
    public var name: String {
        switch self { case .control: "Control"; case .shift: "Shift"; case .option: "Option / Alt"; case .command: "Command / Win" }
    }
}

/// HID keyboard usages offered for remapping, grouped as in Studio. Names are English source names.
public enum AMG65HIDKeys {
    public struct Entry: Identifiable, Hashable, Sendable {
        public let code: UInt8
        public let name: String
        public var id: UInt8 { code }
    }

    public struct Group: Identifiable, Hashable, Sendable {
        public let name: String
        public let keys: [Entry]
        public var id: String { name }
    }

    public static let groups: [Group] = [
        Group(name: "Letters", keys: (0..<26).map { Entry(code: 0x04 + UInt8($0), name: String(UnicodeScalar(65 + $0)!)) }),
        Group(name: "Numbers", keys: (1...10).map { Entry(code: 0x1D + UInt8($0), name: $0 == 10 ? "0" : "\($0)") }),
        Group(name: "Function", keys: (1...12).map { Entry(code: 0x39 + UInt8($0), name: "F\($0)") }
            + (13...24).map { Entry(code: 0x5B + UInt8($0), name: "F\($0)") }),
        Group(name: "Editing", keys: [
            Entry(code: 0x29, name: "Esc"), Entry(code: 0x2B, name: "Tab"), Entry(code: 0x39, name: "Caps Lock"),
            Entry(code: 0x2C, name: "Space"), Entry(code: 0x28, name: "Enter"), Entry(code: 0x2A, name: "Backspace"),
            Entry(code: 0x4C, name: "Delete"), Entry(code: 0x49, name: "Insert"),
        ]),
        Group(name: "Navigation", keys: [
            Entry(code: 0x4A, name: "Home"), Entry(code: 0x4D, name: "End"), Entry(code: 0x4B, name: "Page Up"),
            Entry(code: 0x4E, name: "Page Down"), Entry(code: 0x50, name: "←"), Entry(code: 0x4F, name: "→"),
            Entry(code: 0x52, name: "↑"), Entry(code: 0x51, name: "↓"),
        ]),
        Group(name: "Symbols", keys: [
            Entry(code: 0x35, name: "`"), Entry(code: 0x2D, name: "-"), Entry(code: 0x2E, name: "="),
            Entry(code: 0x2F, name: "["), Entry(code: 0x30, name: "]"), Entry(code: 0x31, name: "\\"),
            Entry(code: 0x33, name: ";"), Entry(code: 0x34, name: "'"), Entry(code: 0x36, name: ","),
            Entry(code: 0x37, name: "."), Entry(code: 0x38, name: "/"),
        ]),
        Group(name: "Modifiers", keys: [
            Entry(code: 0xE0, name: "Left Ctrl"), Entry(code: 0xE1, name: "Left Shift"), Entry(code: 0xE2, name: "Left Alt/⌥"),
            Entry(code: 0xE3, name: "Left Win/⌘"), Entry(code: 0xE4, name: "Right Ctrl"), Entry(code: 0xE5, name: "Right Shift"),
            Entry(code: 0xE6, name: "Right Alt/⌥"), Entry(code: 0xE7, name: "Right Win/⌘"),
        ]),
        Group(name: "Other", keys: [
            Entry(code: 0x46, name: "Print Screen"), Entry(code: 0x47, name: "Scroll Lock"), Entry(code: 0x48, name: "Pause"),
        ]),
    ]

    /// Name of a usage in `groups`; nil for any other usage (Studio shows "Key %02X").
    public static func name(_ code: UInt8) -> String? {
        for group in groups { if let entry = group.keys.first(where: { $0.code == code }) { return entry.name } }
        return nil
    }
}

/// HID consumer usages offered for remapping. Names are English source names.
public enum AMG65MediaKeys {
    public struct Entry: Identifiable, Hashable, Sendable {
        public let usage: UInt16
        public let name: String
        public var id: UInt16 { usage }
    }

    public static let all: [Entry] = [
        Entry(usage: 0xCD, name: "Play / Pause"), Entry(usage: 0xB5, name: "Next track"),
        Entry(usage: 0xB6, name: "Previous track"), Entry(usage: 0xB7, name: "Stop"),
        Entry(usage: 0xE9, name: "Volume up"), Entry(usage: 0xEA, name: "Volume down"),
        Entry(usage: 0xE2, name: "Mute"),
    ]
}

/// Mouse buttons offered for remapping. Names are English source names.
public enum AMG65MouseActions {
    public struct Button: Identifiable, Hashable, Sendable {
        public let mask: UInt8
        public let name: String
        public var id: UInt8 { mask }
    }

    public static let buttons: [Button] = [
        Button(mask: 0x01, name: "Left click"), Button(mask: 0x02, name: "Right click"),
        Button(mask: 0x04, name: "Middle click"), Button(mask: 0x08, name: "Back"), Button(mask: 0x10, name: "Forward"),
    ]
}

// MARK: - macOS remapping

extension AMG65Layout {
    /// The keys for macOS remapping, placed as on the keyboard: Studio's 50 pt grid (rows 52 pt apart) in key units,
    /// `col` = the factory HID usage. Fn has `col` -1: the keyboard handles it itself and macOS never sees it.
    public static var remapKeys: [LayoutKey] {
        litKeys.map { key in
            LayoutKey(row: 0, col: key.remappable ? Int(key.code) : -1,
                      x: key.rect.minX / 50, y: key.rect.minY / 52, w: (key.rect.width + 4) / 50)
        }
    }

    /// Usages of a full-size layout the keyboard has no key for (`, the F row, PrtSc, ScrLk, Pause, Ins, End, Menu,
    /// right ⌥ and ⌘). A macOS remap still catches one when the keyboard sends it, as a 65% board does through Fn;
    /// which Fn combinations send what isn't known here. Two rows in key units, as `remapKeys`.
    public static var offBoardKeys: [LayoutKey] {
        let rows: [[Int]] = [[0x35] + Array(0x3A...0x45), [0x46, 0x47, 0x48, 0x49, 0x4D, 0x65, 0xE6, 0xE7]]
        return rows.enumerated().flatMap { y, usages in
            usages.enumerated().map { x, usage in LayoutKey(row: 0, col: usage, x: Double(x), y: Double(y)) }
        }
    }
}
