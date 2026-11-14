import Foundation

/// A VIA / Vial `customKeycodes` entry. Index n maps to QK_KB_0 + n.
public struct CustomKeycode: Codable, Hashable, Sendable {
    public var name: String
    public var title: String?
    public var shortName: String?

    public init(name: String, title: String? = nil, shortName: String? = nil) {
        self.name = name
        self.title = title
        self.shortName = shortName
    }
}

/// What is printed on a key cap.
public struct KeyLabel: Equatable, Sendable {
    /// Shifted legend (e.g. `!` above `1`), if any.
    public var top: String?
    public var main: String
    /// Secondary function (hold action, layer, ...).
    public var sub: String?

    public init(top: String? = nil, main: String, sub: String? = nil) {
        self.top = top
        self.main = main
        self.sub = sub
    }
}

public enum KeycodeNameStyle: Sendable {
    /// QMK short names (`KC_BSPC`, `LT(1, KC_SPC)`), also understood by VIA.
    case qmk
    /// Names Vial writes into `.vil` files (`KC_BSPACE`, `LT1(KC_SPACE)`).
    case vial
}

/// Structural view of a 16 bit keycode.
public enum DecodedKeycode: Equatable, Sendable {
    case named(UInt16)
    case mods(UInt8, UInt16)
    case modTap(UInt8, UInt16)
    case layerTap(Int, UInt16)
    case layerMod(Int, UInt8)
    case layer(LayerFunction, Int)
    case oneShotMod(UInt8)
    case tapDance(Int)
    case macro(Int)
    case custom(Int)
    case raw(UInt16)
}

public enum LayerFunction: String, CaseIterable, Sendable {
    case MO, TG, TO, TT, OSL, DF, PDF

    public var title: String {
        switch self {
        case .MO: return L("Basılı tutunca katman")
        case .TG: return L("Katmanı aç/kapat")
        case .TO: return L("Katmana geç")
        case .TT: return L("Tap-toggle katman")
        case .OSL: return L("Tek seferlik katman")
        case .DF: return L("Varsayılan katman")
        case .PDF: return L("Kalıcı varsayılan katman")
        }
    }
}

/// Encodes, decodes, names and labels keycodes for one QMK keycode version.
public final class KeycodeSet: @unchecked Sendable {
    public let version: KeycodeVersion
    public let customKeycodes: [CustomKeycode]
    public let entries: [KeycodeEntry]

    private let byCode: [UInt16: KeycodeEntry]
    private let byName: [String: UInt16]

    public static let v6 = KeycodeSet(version: .v6)
    public static let v5 = KeycodeSet(version: .v5)

    public init(version: KeycodeVersion, customKeycodes: [CustomKeycode] = []) {
        self.version = version
        self.customKeycodes = customKeycodes
        let list = KeycodeTables.common + (version == .v6 ? KeycodeTables.v6Only : KeycodeTables.v5Only)
        entries = list
        var codes: [UInt16: KeycodeEntry] = [:]
        var names: [String: UInt16] = [:]
        for entry in list {
            if codes[entry.code] == nil { codes[entry.code] = entry }
            for name in [entry.name, entry.vialName] + entry.aliases where names[name.uppercased()] == nil {
                names[name.uppercased()] = entry.code
            }
        }
        byCode = codes
        byName = names
    }

    public func withCustomKeycodes(_ custom: [CustomKeycode]) -> KeycodeSet {
        KeycodeSet(version: version, customKeycodes: custom)
    }

    public func entry(for code: UInt16) -> KeycodeEntry? { byCode[code] }

    // MARK: Ranges

    private var modTapBase: UInt16 { version == .v6 ? 0x2000 : 0x6000 }
    private var macroBase: UInt16 { version == .v6 ? 0x7700 : 0x5F12 }
    private var macroCount: Int { version == .v6 ? 128 : 16 }
    private var customBase: UInt16 { version == .v6 ? 0x7E00 : 0x5F80 }
    private let customCount = 64

    private func layerBase(_ function: LayerFunction) -> UInt16? {
        switch (version, function) {
        case (.v6, .TO): return 0x5200
        case (.v6, .MO): return 0x5220
        case (.v6, .DF): return 0x5240
        case (.v6, .TG): return 0x5260
        case (.v6, .OSL): return 0x5280
        case (.v6, .TT): return 0x52C0
        case (.v6, .PDF): return 0x52E0
        case (.v5, .TO): return 0x5010
        case (.v5, .MO): return 0x5100
        case (.v5, .DF): return 0x5200
        case (.v5, .TG): return 0x5300
        case (.v5, .OSL): return 0x5400
        case (.v5, .TT): return 0x5800
        case (.v5, .PDF): return nil
        }
    }

    // MARK: Encode

    public func encode(_ decoded: DecodedKeycode) -> UInt16? {
        switch decoded {
        case let .named(code), let .raw(code):
            return code
        case let .mods(mods, kc):
            guard kc <= 0xFF, mods & 0x1F != 0 else { return nil }
            return UInt16(mods & 0x1F) << 8 | kc
        case let .modTap(mods, kc):
            guard kc <= 0xFF else { return nil }
            return modTapBase | UInt16(mods & 0x1F) << 8 | kc
        case let .layerTap(layer, kc):
            guard (0...15).contains(layer), kc <= 0xFF else { return nil }
            return 0x4000 | UInt16(layer) << 8 | kc
        case let .layerMod(layer, mods):
            guard (0...15).contains(layer) else { return nil }
            return version == .v6
                ? 0x5000 | UInt16(layer) << 5 | UInt16(mods & 0x1F)
                : 0x5900 | UInt16(layer) << 4 | UInt16(mods & 0x0F)
        case let .layer(function, layer):
            guard let base = layerBase(function), (0...(version == .v6 ? 31 : 15)).contains(layer) else { return nil }
            return base | UInt16(layer)
        case let .oneShotMod(mods):
            return (version == .v6 ? 0x52A0 : 0x5500) | UInt16(mods & 0x1F)
        case let .tapDance(index):
            guard (0...255).contains(index) else { return nil }
            return 0x5700 | UInt16(index)
        case let .macro(index):
            guard (0..<macroCount).contains(index) else { return nil }
            return macroBase + UInt16(index)
        case let .custom(index):
            guard (0..<customCount).contains(index) else { return nil }
            return customBase + UInt16(index)
        }
    }

    // MARK: Decode

    public func decode(_ code: UInt16) -> DecodedKeycode {
        if byCode[code] != nil { return .named(code) }
        if code <= 0xFF { return .raw(code) }
        if code <= 0x1FFF { return .mods(UInt8(code >> 8 & 0x1F), code & 0xFF) }
        if code >= customBase && code < customBase + UInt16(customCount) { return .custom(Int(code - customBase)) }
        if code >= macroBase && code < macroBase + UInt16(macroCount) { return .macro(Int(code - macroBase)) }

        switch version {
        case .v6:
            switch code {
            case 0x2000...0x3FFF: return .modTap(UInt8(code >> 8 & 0x1F), code & 0xFF)
            case 0x4000...0x4FFF: return .layerTap(Int(code >> 8 & 0x0F), code & 0xFF)
            case 0x5000...0x51FF: return .layerMod(Int(code >> 5 & 0x0F), UInt8(code & 0x1F))
            case 0x52A0...0x52BF: return .oneShotMod(UInt8(code & 0x1F))
            case 0x5200...0x52FF:
                for function in LayerFunction.allCases {
                    if let base = layerBase(function), code >= base, code < base + 0x20 { return .layer(function, Int(code - base)) }
                }
            case 0x5700...0x57FF: return .tapDance(Int(code & 0xFF))
            default: break
            }
        case .v5:
            switch code {
            case 0x6000...0x7FFF: return .modTap(UInt8(code >> 8 & 0x1F), code & 0xFF)
            case 0x4000...0x4FFF: return .layerTap(Int(code >> 8 & 0x0F), code & 0xFF)
            case 0x5010...0x501F: return .layer(.TO, Int(code & 0x0F))
            case 0x5100...0x510F: return .layer(.MO, Int(code & 0x0F))
            case 0x5200...0x520F: return .layer(.DF, Int(code & 0x0F))
            case 0x5300...0x530F: return .layer(.TG, Int(code & 0x0F))
            case 0x5400...0x540F: return .layer(.OSL, Int(code & 0x0F))
            case 0x5500...0x551F: return .oneShotMod(UInt8(code & 0x1F))
            case 0x5700...0x57FF: return .tapDance(Int(code & 0xFF))
            case 0x5800...0x580F: return .layer(.TT, Int(code & 0x0F))
            case 0x5900...0x59FF: return .layerMod(Int(code >> 4 & 0x0F), UInt8(code & 0x0F))
            default: break
            }
        }
        return .raw(code)
    }

    // MARK: Names

    public func name(for code: UInt16, style: KeycodeNameStyle = .qmk) -> String {
        switch decode(code) {
        case let .named(c):
            let entry = byCode[c]!
            return style == .vial ? entry.vialName : entry.name
        case let .raw(c):
            return hex(c)
        case let .mods(mods, _) where mods & 0x0F == 0,
             let .modTap(mods, _) where mods & 0x0F == 0 && mods != 0,
             let .layerMod(_, mods) where mods & 0x0F == 0 && mods != 0,
             let .oneShotMod(mods) where mods & 0x0F == 0:
            // Right-hand flag without any modifier: not expressible by name.
            return hex(code)
        case let .mods(mods, kc):
            return wrapMods(mods, inner: name(for: kc, style: style))
        case let .modTap(mods, kc):
            let inner = name(for: kc, style: style)
            if let tap = KeycodeTables.modNames.first(where: { $0.mask == mods })?.tap { return "\(tap)(\(inner))" }
            return "MT(\(modMaskName(mods)), \(inner))"
        case let .layerTap(layer, kc):
            let inner = name(for: kc, style: style)
            return style == .vial ? "LT\(layer)(\(inner))" : "LT(\(layer), \(inner))"
        case let .layerMod(layer, mods):
            return "LM(\(layer), \(modMaskName(mods)))"
        case let .layer(function, layer):
            return "\(function.rawValue)(\(layer))"
        case let .oneShotMod(mods):
            return "OSM(\(modMaskName(mods)))"
        case let .tapDance(index):
            return "TD(\(index))"
        case let .macro(index):
            return "M\(index)"
        case let .custom(index):
            return style == .vial ? String(format: "USER%02d", index) : "CUSTOM(\(index))"
        }
    }

    private func hex(_ code: UInt16) -> String { String(format: "0x%04X", code) }

    private func wrapMods(_ mods: UInt8, inner: String) -> String {
        if let named = KeycodeTables.modNames.first(where: { $0.mask == mods }) { return "\(named.function)(\(inner))" }
        let right = mods & 0x10 != 0
        var result = inner
        for (bit, left, rightName) in [(UInt8(0x08), "LGUI", "RGUI"), (0x04, "LALT", "RALT"), (0x02, "LSFT", "RSFT"), (0x01, "LCTL", "RCTL")]
        where mods & bit != 0 {
            result = "\(right ? rightName : left)(\(result))"
        }
        return result
    }

    public func modMaskName(_ mods: UInt8) -> String {
        let right = mods & 0x10 != 0
        var parts: [String] = []
        for (bit, name) in [(UInt8(0x01), "CTL"), (0x02, "SFT"), (0x04, "ALT"), (0x08, "GUI")] where mods & bit != 0 {
            parts.append("MOD_\(right ? "R" : "L")\(name)")
        }
        return parts.isEmpty ? "0" : parts.joined(separator: " | ")
    }

    public func modSymbol(_ mods: UInt8) -> String {
        if let named = KeycodeTables.modNames.first(where: { $0.mask == mods }) { return named.symbol }
        var out = ""
        for (bit, symbol) in [(UInt8(0x01), "⌃"), (0x02, "⇧"), (0x04, "⌥"), (0x08, "⌘")] where mods & bit != 0 { out += symbol }
        return out
    }

    // MARK: Labels

    public func label(for code: UInt16) -> KeyLabel {
        switch decode(code) {
        case let .named(c):
            let parts = byCode[c]!.label.components(separatedBy: "\n")
            return parts.count > 1 ? KeyLabel(top: parts[0], main: parts[1]) : KeyLabel(main: parts[0])
        case let .raw(c):
            return KeyLabel(main: hex(c))
        case let .mods(mods, kc):
            return KeyLabel(main: modSymbol(mods) + shortLabel(kc))
        case let .modTap(mods, kc):
            return KeyLabel(main: shortLabel(kc), sub: modSymbol(mods))
        case let .layerTap(layer, kc):
            return KeyLabel(main: shortLabel(kc), sub: "L\(layer)")
        case let .layerMod(layer, mods):
            return KeyLabel(main: "LM \(layer)", sub: modSymbol(mods))
        case let .layer(function, layer):
            return KeyLabel(main: "\(function.rawValue) \(layer)")
        case let .oneShotMod(mods):
            return KeyLabel(main: "OSM", sub: modSymbol(mods))
        case let .tapDance(index):
            return KeyLabel(main: "TD \(index)")
        case let .macro(index):
            return KeyLabel(main: "M\(index)")
        case let .custom(index):
            if index < customKeycodes.count {
                let custom = customKeycodes[index]
                return KeyLabel(main: (custom.shortName ?? custom.name).replacingOccurrences(of: "\n", with: " "))
            }
            return KeyLabel(main: String(format: "USER%02d", index))
        }
    }

    /// Single line legend (unshifted part) for compact display.
    public func shortLabel(_ code: UInt16) -> String {
        let label = label(for: code)
        return label.main.isEmpty ? (code == 0 ? "∅" : "") : label.main
    }

    /// Human readable description for tooltips.
    /// Human readable name (never the QMK identifier when a better one exists).
    public func title(for code: UInt16) -> String {
        switch decode(code) {
        case let .named(c):
            let entry = byCode[c]!
            if entry.title != entry.name { return L(entry.title) }
            let label = label(for: c)
            return label.main.isEmpty ? entry.name : label.main
        case let .mods(mods, kc): return modSymbol(mods) + shortLabel(kc)
        case let .modTap(mods, kc): return L("Dokun: %@ · Basılı tut: %@", "\(shortLabel(kc))", "\(modSymbol(mods))")
        case let .layerTap(layer, kc): return L("Dokun: %@ · Basılı tut: katman %@", "\(shortLabel(kc))", "\(layer)")
        case let .layerMod(layer, mods): return L("Katman %@ + %@", "\(layer)", "\(modSymbol(mods))")
        case let .layer(function, layer): return "\(function.title) \(layer)"
        case let .oneShotMod(mods): return L("Tek seferlik %@", "\(modSymbol(mods))")
        case let .tapDance(index): return L("Tap dance %@", "\(index)")
        case let .macro(index): return L("Makro %@", "\(index)")
        case let .custom(index):
            if index < customKeycodes.count {
                let custom = customKeycodes[index]
                return (custom.shortName ?? custom.name).replacingOccurrences(of: "\n", with: " ")
            }
            return L("Özel işlev %@", "\(index)")
        case .raw: return name(for: code)
        }
    }

    // MARK: Parse

    /// Parses QMK / VIA / Vial keycode expressions (`KC_A`, `LT(1,KC_SPC)`, `LT1(KC_SPACE)`,
    /// `LSFT_T(KC_A)`, `LCTL(KC_C)`, `MO(2)`, `0x5221`, custom keycode names ...).
    public func parse(_ input: String) -> UInt16? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let number = KeycodeSet.parseNumber(text) { return UInt16(exactly: number) }

        if let open = text.firstIndex(of: "("), text.hasSuffix(")") {
            let function = text[..<open].trimmingCharacters(in: .whitespaces).uppercased()
            let inner = String(text[text.index(after: open)..<text.index(before: text.endIndex)])
            let args = KeycodeSet.splitArguments(inner)
            return parseFunction(function, args)
        }

        let upper = text.uppercased()
        if let code = byName[upper] { return code }
        if let index = customKeycodes.firstIndex(where: { $0.name.uppercased() == upper }) { return encode(.custom(index)) }
        if let n = KeycodeSet.suffixNumber(upper, prefixes: ["USER", "QK_KB_", "QK_USER_"]) { return encode(.custom(n)) }
        if let n = KeycodeSet.suffixNumber(upper, prefixes: ["MACRO", "QK_MACRO_", "M", "DYN_MACRO_"]) { return encode(.macro(n)) }
        if let n = KeycodeSet.suffixNumber(upper, prefixes: ["TD"]) { return encode(.tapDance(n)) }
        return nil
    }

    private func parseFunction(_ function: String, _ args: [String]) -> UInt16? {
        if let layerFunction = LayerFunction(rawValue: function), args.count == 1, let layer = KeycodeSet.parseNumber(args[0]) {
            return encode(.layer(layerFunction, layer))
        }
        switch function {
        case "LT":
            guard args.count == 2, let layer = KeycodeSet.parseNumber(args[0]), let kc = parseBasic(args[1]) else { return nil }
            return encode(.layerTap(layer, kc))
        case "MT":
            guard args.count == 2, let mods = parseModMask(args[0]), let kc = parseBasic(args[1]) else { return nil }
            return encode(.modTap(mods, kc))
        case "LM":
            guard args.count == 2, let layer = KeycodeSet.parseNumber(args[0]), let mods = parseModMask(args[1]) else { return nil }
            return encode(.layerMod(layer, mods))
        case "OSM":
            guard args.count == 1, let mods = parseModMask(args[0]) else { return nil }
            return encode(.oneShotMod(mods))
        case "TD":
            guard args.count == 1, let n = KeycodeSet.parseNumber(args[0]) else { return nil }
            return encode(.tapDance(n))
        case "M", "MACRO", "QK_MACRO":
            guard args.count == 1, let n = KeycodeSet.parseNumber(args[0]) else { return nil }
            return encode(.macro(n))
        case "CUSTOM", "USER", "QK_KB":
            guard args.count == 1, let n = KeycodeSet.parseNumber(args[0]) else { return nil }
            return encode(.custom(n))
        default:
            break
        }
        guard args.count == 1 else { return nil }
        // Vial style layer tap: LT3(KC_A)
        if function.hasPrefix("LT"), let layer = Int(function.dropFirst(2)), let kc = parseBasic(args[0]) {
            return encode(.layerTap(layer, kc))
        }
        if let mods = KeycodeTables.modNames.first(where: { $0.tap == function })?.mask ?? KeycodeTables.modTapAliases[function] {
            guard let kc = parseBasic(args[0]) else { return nil }
            return encode(.modTap(mods, kc))
        }
        if let mods = KeycodeTables.modNames.first(where: { $0.function == function })?.mask ?? KeycodeTables.modFunctionAliases[function] {
            guard let inner = parse(args[0]), inner <= 0x1FFF else { return nil }
            let combined = mods | UInt8(inner >> 8 & 0x1F)
            return encode(.mods(combined, inner & 0xFF))
        }
        return nil
    }

    private func parseBasic(_ text: String) -> UInt16? {
        guard let code = parse(text), code <= 0xFF else { return nil }
        return code
    }

    private func parseModMask(_ text: String) -> UInt8? {
        var mask: UInt8 = 0
        for part in text.split(separator: "|") {
            let token = part.trimmingCharacters(in: .whitespaces).uppercased()
            if let bits = KeycodeTables.modBitNames[token] {
                mask |= bits
            } else if let number = KeycodeSet.parseNumber(token), number <= 0x1F, let bits = UInt8(exactly: number) {
                mask |= bits
            } else {
                return nil
            }
        }
        return mask
    }

    static func parseNumber(_ text: String) -> Int? {
        let t = text.trimmingCharacters(in: .whitespaces).lowercased()
        let value = t.hasPrefix("0x") ? Int(t.dropFirst(2), radix: 16) : Int(t)
        guard let value, value >= 0 else { return nil }
        return value
    }

    static func suffixNumber(_ text: String, prefixes: [String]) -> Int? {
        for prefix in prefixes where text.hasPrefix(prefix) {
            if let n = Int(text.dropFirst(prefix.count)) { return n }
        }
        return nil
    }

    static func splitArguments(_ text: String) -> [String] {
        var args: [String] = []
        var depth = 0
        var current = ""
        for ch in text {
            switch ch {
            case "(": depth += 1; current.append(ch)
            case ")": depth -= 1; current.append(ch)
            case "," where depth == 0:
                args.append(current.trimmingCharacters(in: .whitespaces)); current = ""
            default: current.append(ch)
            }
        }
        args.append(current.trimmingCharacters(in: .whitespaces))
        return args
    }
}
