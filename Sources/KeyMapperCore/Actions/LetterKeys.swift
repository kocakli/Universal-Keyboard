import Foundation

/// A letter KeyMapper types itself (ğ, ş, ñ…), for letters the Mac's input source has no key for.
/// The keyboard sends the letter's slot code (a reserved modifier + F-key combination); KeyMapper
/// catches it and types `lower`, or `upper` while Shift or Caps Lock is on.
public struct LetterKey: Codable, Hashable, Sendable, Identifiable {
    public var slot: Int
    public var lower: String
    public var upper: String

    public var id: Int { slot }

    public init(slot: Int, lower: String, upper: String? = nil) {
        self.slot = slot
        self.lower = lower
        self.upper = upper ?? LetterKey.uppercase(lower)
    }

    /// Capital form. `uppercased()` gets two offered letters wrong for a single key: i → I (a letter key
    /// for "i" exists only to reach İ, since the I key already types i and I) and ß → SS.
    public static func uppercase(_ text: String) -> String {
        switch text {
        case "i": return "İ"
        case "ß": return "ẞ"
        default: return text.uppercased()
        }
    }

    /// What the key shows: the capital for i (its reason to exist), otherwise the letter itself.
    public var legend: String { lower == "i" ? upper : lower }

    /// Accepts 1–8 printable characters (a letter, or a short sequence like "ñ" or "€").
    public static func sanitized(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...8).contains(trimmed.count),
              !trimmed.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
        return trimmed
    }
}

/// One reserved code a keyboard can send for a letter: modifiers + F-key.
public struct LetterSlot: Hashable, Sendable {
    public let index: Int
    /// HID usage / QMK basic keycode of the F-key.
    public let usage: UInt16
    /// macOS virtual key code of the F-key.
    public let keyCode: UInt16
    /// QMK modifier bits: control 0x01, shift 0x02, option 0x04, command 0x08.
    public let mods: UInt8

    public var modifiers: LetterKeyFilter.Modifiers {
        var out: LetterKeyFilter.Modifiers = []
        if mods & 0x01 != 0 { out.insert(.control) }
        if mods & 0x04 != 0 { out.insert(.option) }
        if mods & 0x08 != 0 { out.insert(.command) }
        return out
    }
}

public enum LetterKeys {
    /// F13 and F16–F20 (F14/F15 are display brightness on macOS), each under ⌃⌥⌘ and ⌃⌥.
    /// Shift stays free so it can pick the capital.
    public static let slots: [LetterSlot] = {
        let fKeys: [(usage: UInt16, keyCode: UInt16)] = [
            (0x68, 0x69), (0x6B, 0x6A), (0x6C, 0x40), (0x6D, 0x4F), (0x6E, 0x50), (0x6F, 0x5A),
        ]
        var slots: [LetterSlot] = []
        for mods: UInt8 in [0x0D, 0x05] {
            for key in fKeys {
                slots.append(LetterSlot(index: slots.count, usage: key.usage, keyCode: key.keyCode, mods: mods))
            }
        }
        return slots
    }()

    /// Letters offered in the picker. "i" is there for İ.
    public static let turkish = ["ç", "ğ", "ı", "i", "ö", "ş", "ü"]
    public static let other = ["ä", "ß", "ñ", "á", "é", "í", "ó", "ú", "à", "è", "ê", "â", "¿", "¡", "€"]

    /// Firmware keycode that sends `slot` (e.g. LCAG(KC_F13)).
    public static func code(for slot: LetterSlot, keycodes: KeycodeSet) -> UInt16? {
        keycodes.encode(.mods(slot.mods, slot.usage))
    }

    /// The slot a firmware keycode sends, if it is one of the reserved letter codes.
    public static func slot(forCode code: UInt16, keycodes: KeycodeSet) -> LetterSlot? {
        guard case let .mods(mods, usage) = keycodes.decode(code) else { return nil }
        return slots.first { $0.mods == mods && $0.usage == usage }
    }

    /// The letter a firmware keycode types.
    public static func letter(forCode code: UInt16, keycodes: KeycodeSet, in letters: [LetterKey]) -> LetterKey? {
        guard let slot = slot(forCode: code, keycodes: keycodes) else { return nil }
        return letters.first { $0.slot == slot.index }
    }

    /// The slot to use for `lower`: the one already typing it, else the first free one.
    public static func slotIndex(for lower: String, in letters: [LetterKey]) -> Int? {
        if let existing = letters.first(where: { $0.lower == lower }) { return existing.slot }
        let used = Set(letters.map(\.slot))
        return slots.first { !used.contains($0.index) }?.index
    }
}

/// Decides, for each key event, whether it is a letter key: the event tap calls it on its own thread.
/// Pure, so the matching rules are unit tested without an event tap.
public struct LetterKeyFilter: Sendable {
    public struct Modifiers: OptionSet, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let command = Modifiers(rawValue: 1 << 2)
        public static let shift = Modifiers(rawValue: 1 << 3)
        public static let capsLock = Modifiers(rawValue: 1 << 4)

        /// The modifiers a slot is told apart by (Shift and Caps Lock only choose the case).
        var slotPart: Modifiers { intersection([.control, .option, .command]) }
    }

    public enum Decision: Equatable, Sendable {
        /// Not a letter key: deliver the event unchanged.
        case pass
        /// The release of a letter key: drop it.
        case swallow
        /// A letter key press: drop it and type this text instead.
        case type(String)
    }

    private var letters: [Int: LetterKey] = [:]
    /// Key codes whose press was turned into a letter; their release is dropped even if the
    /// modifiers were let go first.
    private var held: Set<UInt16> = []

    public init(letters: [LetterKey] = []) { update(letters: letters) }

    public var isEmpty: Bool { letters.isEmpty }

    public mutating func update(letters: [LetterKey]) {
        self.letters = Dictionary(letters.map { ($0.slot, $0) }, uniquingKeysWith: { _, last in last })
    }

    public mutating func handle(keyCode: UInt16, isDown: Bool, modifiers: Modifiers) -> Decision {
        guard isDown else { return held.remove(keyCode) == nil ? .pass : .swallow }
        guard let slot = LetterKeys.slots.first(where: { $0.keyCode == keyCode && $0.modifiers == modifiers.slotPart }),
              let letter = letters[slot.index] else { return .pass }
        held.insert(keyCode)
        let capital = !modifiers.isDisjoint(with: [.shift, .capsLock])
        return .type(capital ? letter.upper : letter.lower)
    }
}

/// Persists letter keys in `~/Library/Application Support/KeyMapper/letters.json`.
public final class LetterKeyStore: @unchecked Sendable {
    public static let shared = LetterKeyStore()

    private let url: URL
    private let lock = NSLock()

    public init(url: URL = AppPaths.root.appendingPathComponent("letters.json")) {
        self.url = url
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    public func load() -> [LetterKey] {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? Data(contentsOf: url),
              let letters = try? JSONDecoder().decode([LetterKey].self, from: data) else { return [] }
        return letters.filter { LetterKeys.slots.indices.contains($0.slot) && LetterKey.sanitized($0.lower) != nil }
    }

    public func save(_ letters: [LetterKey]) throws {
        lock.lock(); defer { lock.unlock() }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(letters).write(to: url, options: .atomic)
    }
}
