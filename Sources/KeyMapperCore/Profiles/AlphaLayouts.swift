import Foundation

/// Alphabet layouts (QWERTY, Colemak, Dvorak, ...) described by what each QWERTY position types.
public struct AlphaLayout: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    /// HID usages, aligned with `AlphaLayout.qwerty.keys`.
    public let keys: [UInt16]

    init(id: String, name: String, characters: String) {
        self.id = id
        self.name = name
        self.keys = characters.map { AlphaLayout.usage(for: $0) }
    }

    private static let characterUsages: [Character: UInt16] = {
        var map: [Character: UInt16] = [:]
        for (i, c) in "abcdefghijklmnopqrstuvwxyz".enumerated() { map[c] = UInt16(0x04 + i) }
        let symbols: [Character: UInt16] = ["[": 0x2F, "]": 0x30, ";": 0x33, "'": 0x34, ",": 0x36, ".": 0x37, "/": 0x38, "-": 0x2D, "=": 0x2E]
        map.merge(symbols) { a, _ in a }
        return map
    }()

    static func usage(for character: Character) -> UInt16 { characterUsages[character] ?? 0 }

    // Positions: top row (12), home row (11), bottom row (10), number row extras (2).
    public static let qwerty = AlphaLayout(id: "qwerty", name: "QWERTY", characters: "qwertyuiop[]asdfghjkl;'zxcvbnm,./-=")
    public static let colemak = AlphaLayout(id: "colemak", name: "Colemak", characters: "qwfpgjluy;[]arstdhneio'zxcvbkm,./-=")
    public static let colemakDH = AlphaLayout(id: "colemak-dh", name: "Colemak-DH", characters: "qwfpbjluy;[]arstgmneio'zxcdvkh,./-=")
    public static let dvorak = AlphaLayout(id: "dvorak", name: "Dvorak", characters: "',.pyfgcrl/=aoeuidhtns-;qjkxbmwvz[]")
    public static let workman = AlphaLayout(id: "workman", name: "Workman", characters: "qdrwbjfup;[]ashtgyneoi'zxmcvkl,./-=")

    public static let all: [AlphaLayout] = [qwerty, colemak, colemakDH, dvorak, workman]

    /// Converts one layer from `source` to `target`, keeping hold actions
    /// (home row mods `LSFT_T(KC_A)`, layer taps, modifier combos) intact.
    public static func convert(layer: [[UInt16]], from source: AlphaLayout, to target: AlphaLayout, keycodes: KeycodeSet) -> [[UInt16]] {
        var lookup: [UInt16: UInt16] = [:]
        for (index, usage) in source.keys.enumerated() where index < target.keys.count { lookup[usage] = target.keys[index] }
        return layer.map { row in
            row.map { code in
                switch keycodes.decode(code) {
                case .named(let c) where c <= 0xFF:
                    return lookup[c] ?? code
                case let .mods(mods, kc):
                    guard let mapped = lookup[kc] else { return code }
                    return keycodes.encode(.mods(mods, mapped)) ?? code
                case let .modTap(mods, kc):
                    guard let mapped = lookup[kc] else { return code }
                    return keycodes.encode(.modTap(mods, mapped)) ?? code
                case let .layerTap(l, kc):
                    guard let mapped = lookup[kc] else { return code }
                    return keycodes.encode(.layerTap(l, mapped)) ?? code
                default:
                    return code
                }
            }
        }
    }

    /// macOS remaps that turn a physical QWERTY keyboard into `target`.
    public static func remaps(to target: AlphaLayout) -> [KeyRemap] {
        zip(qwerty.keys, target.keys).compactMap { from, to in from == to ? nil : KeyRemap(from: from, to: to) }
    }
}
