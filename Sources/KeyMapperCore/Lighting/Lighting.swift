import Foundation

/// A lighting system a QMK keyboard can expose through VIA / Vial.
public enum LightingKind: String, Codable, Sendable, CaseIterable {
    /// Single-colour backlight (QMK `backlight`): brightness and breathing on/off.
    case backlight
    /// RGB underglow or strip (QMK `rgblight`).
    case rgblight
    /// Per-key RGB (QMK `rgb_matrix`) through VIA's channel commands.
    case rgbMatrix
    /// Per-key single colour (QMK `led_matrix`).
    case ledMatrix
    /// Per-key RGB through Vial's own protocol (VialRGB).
    case vialRGB

    public var title: String {
        switch self {
        case .backlight: return L("Arka ışık")
        case .rgblight: return L("RGB şerit")
        case .rgbMatrix, .vialRGB: return L("Tuş RGB")
        case .ledMatrix: return L("Tuş ışığı")
        }
    }

    public var hasColor: Bool { self == .rgblight || self == .rgbMatrix || self == .vialRGB }
    public var hasSpeed: Bool { self != .backlight }
}

public struct LightingEffect: Hashable, Codable, Sendable {
    public let id: Int
    public let name: String
    public init(id: Int, name: String) { self.id = id; self.name = name }
}

public struct LightingCapability: Hashable, Codable, Sendable {
    public let kind: LightingKind
    /// Named effects; empty when the firmware's list is unknown (the UI then steps through numbers).
    public var effects: [LightingEffect]
    public init(kind: LightingKind, effects: [LightingEffect] = []) { self.kind = kind; self.effects = effects }
}

/// Current lighting values, normalised: brightness, speed, hue and saturation are 0–255.
public struct LightingState: Equatable, Sendable {
    public var brightness: Int
    public var effect: Int
    public var speed: Int
    public var hue: Int
    public var saturation: Int

    public init(brightness: Int = 0, effect: Int = 0, speed: Int = 0, hue: Int = 0, saturation: Int = 0) {
        self.brightness = brightness
        self.effect = effect
        self.speed = speed
        self.hue = hue
        self.saturation = saturation
    }
}

public enum LightingField: Sendable, CaseIterable { case brightness, effect, speed, color }

// MARK: - Definitions

/// Reads lighting support from VIA v3 `menus`, VIA v2 / Vial `lighting`.
public enum LightingDefinition {
    public static func capabilities(from json: [String: Any]) -> [LightingCapability] {
        var found: [LightingKind: [LightingEffect]] = [:]
        func add(_ kind: LightingKind, _ effects: [LightingEffect] = []) {
            if found[kind]?.isEmpty ?? true { found[kind] = effects } else if !effects.isEmpty && found[kind]!.isEmpty { found[kind] = effects }
        }

        if let menus = json["menus"] as? [Any] {
            for menu in menus {
                if let preset = menu as? String {
                    for kind in kinds(forPreset: preset) { add(kind) }
                } else {
                    walk(menu) { kind, effects in add(kind, effects) }
                }
            }
        }
        if let lighting = json["lighting"] as? String {
            for kind in kinds(forPreset: lighting) { add(kind) }
        } else if let lighting = json["lighting"] as? [String: Any] {
            // VIA v2 object form: {"extends": "qmk_rgblight", "underglowEffects": [["Name", n], …]}
            let kinds = (lighting["extends"] as? String).map(kinds(forPreset:)) ?? []
            let named = (lighting["underglowEffects"] as? [Any] ?? lighting["effects"] as? [Any] ?? [])
                .enumerated().compactMap { index, item -> LightingEffect? in
                    if let pair = item as? [Any], let name = pair.first as? String { return LightingEffect(id: index, name: name) }
                    return (item as? String).map { LightingEffect(id: index, name: $0) }
                }
            for kind in kinds { add(kind, kind == .rgblight ? named : []) }
        }

        // Built-in effect lists where the definition gives none (same tables VIA / Vial use).
        if found[.rgblight]?.isEmpty == true { found[.rgblight] = rgblightEffects }
        if found[.backlight]?.isEmpty == true { found[.backlight] = backlightEffects }
        return LightingKind.allCases.compactMap { kind in found[kind].map { LightingCapability(kind: kind, effects: $0) } }
    }

    static func kinds(forPreset preset: String) -> [LightingKind] {
        switch preset {
        case "qmk_backlight": return [.backlight]
        case "qmk_rgblight": return [.rgblight]
        case "qmk_backlight_rgblight": return [.backlight, .rgblight]
        case "qmk_rgb_matrix": return [.rgbMatrix]
        case "qmk_led_matrix": return [.ledMatrix]
        case "vialrgb": return [.vialRGB]
        default: return []
        }
    }

    /// VIA v3 custom menus: controls carry `content: ["id_…", channel, valueID]`.
    private static func walk(_ node: Any, _ visit: (LightingKind, [LightingEffect]) -> Void) {
        if let list = node as? [Any] {
            for item in list { walk(item, visit) }
            return
        }
        guard let object = node as? [String: Any] else { return }
        if let content = object["content"] as? [Any], content.count == 3, content[0] is String,
           let channel = int(content[1]), let valueID = int(content[2]) {
            let kind: LightingKind? = switch channel {
            case 1: .backlight
            case 2: .rgblight
            case 3: .rgbMatrix
            case 5: .ledMatrix
            default: nil
            }
            if let kind {
                let effects = valueID == 2 && object["type"] as? String == "dropdown" ? dropdownOptions(object["options"]) : []
                visit(kind, effects)
            }
            return
        }
        if let content = object["content"] { walk(content, visit) }
    }

    /// Dropdown options are either ["Name", …] (value = index) or [["Name", value], …].
    private static func dropdownOptions(_ value: Any?) -> [LightingEffect] {
        guard let options = value as? [Any] else { return [] }
        return options.enumerated().compactMap { index, option in
            if let name = option as? String { return LightingEffect(id: index, name: name) }
            if let pair = option as? [Any], pair.count == 2, let name = pair[0] as? String, let id = int(pair[1]) {
                return LightingEffect(id: id, name: name)
            }
            return nil
        }
    }

    private static func int(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        return nil
    }

    /// QMK rgblight modes as listed by vial-gui (numbering assumes every animation is compiled in).
    static let rgblightEffects: [LightingEffect] = {
        var names = ["All Off", "Solid Color"]
        names += (1...4).map { "Breathing \($0)" }
        names += (1...3).map { "Rainbow Mood \($0)" }
        names += (1...6).map { "Rainbow Swirl \($0)" }
        names += (1...6).map { "Snake \($0)" }
        names += (1...3).map { "Knight \($0)" }
        names += ["Christmas"]
        names += (1...10).map { "Gradient \($0)" }
        names += ["RGB Test", "Alternating"]
        return names.enumerated().map { LightingEffect(id: $0.offset, name: $0.element) }
    }()

    /// QMK backlight "effect" is breathing on/off.
    static var backlightEffects: [LightingEffect] {
        [LightingEffect(id: 0, name: L("Sabit")), LightingEffect(id: 1, name: L("Nefes alma"))]
    }

    /// VialRGB effect ids (vial-gui VIALRGB_EFFECTS); the keyboard reports which ones it supports.
    public static let vialRGBEffectNames: [Int: String] = [
        0: "Disable", 1: "Direct Control", 2: "Solid Color", 3: "Alphas Mods", 4: "Gradient Up Down",
        5: "Gradient Left Right", 6: "Breathing", 7: "Band Sat", 8: "Band Val", 9: "Band Pinwheel Sat",
        10: "Band Pinwheel Val", 11: "Band Spiral Sat", 12: "Band Spiral Val", 13: "Cycle All", 14: "Cycle Left Right",
        15: "Cycle Up Down", 16: "Rainbow Moving Chevron", 17: "Cycle Out In", 18: "Cycle Out In Dual",
        19: "Cycle Pinwheel", 20: "Cycle Spiral", 21: "Dual Beacon", 22: "Rainbow Beacon", 23: "Rainbow Pinwheels",
        24: "Raindrops", 25: "Jellybean Raindrops", 26: "Hue Breathing", 27: "Hue Pendulum", 28: "Hue Wave",
        29: "Typing Heatmap", 30: "Digital Rain", 31: "Solid Reactive Simple", 32: "Solid Reactive",
        33: "Solid Reactive Wide", 34: "Solid Reactive Multiwide", 35: "Solid Reactive Cross",
        36: "Solid Reactive Multicross", 37: "Solid Reactive Nexus", 38: "Solid Reactive Multinexus", 39: "Splash",
        40: "Multisplash", 41: "Solid Splash", 42: "Solid Multisplash", 43: "Pixel Rain", 44: "Pixel Fractal",
    ]
}

// MARK: - Protocol

/// Packet layouts for VIA lighting (quantum/via.h) and VialRGB (vial-qmk quantum/vialrgb.h).
/// VIA protocol 12+ addresses values by channel: [cmd, channel, valueID, data…].
/// Older VIA and Vial (protocol 9) use [cmd, valueID, data…] with per-system value ids.
/// Set commands only change RAM; `save` writes the current values to EEPROM.
public enum LightingProtocol {
    static let setValue: UInt8 = 0x07
    static let getValue: UInt8 = 0x08
    static let save: UInt8 = 0x09

    static let vialRGBGetInfo: UInt8 = 0x40
    static let vialRGBMode: UInt8 = 0x41
    static let vialRGBGetSupported: UInt8 = 0x42

    public static func usesChannels(viaProtocol: Int) -> Bool { viaProtocol >= 12 }

    static func channel(_ kind: LightingKind) -> UInt8? {
        switch kind {
        case .backlight: return 1
        case .rgblight: return 2
        case .rgbMatrix: return 3
        case .ledMatrix: return 5
        case .vialRGB: return nil
        }
    }

    /// Bytes that address one value after the command byte; nil when the system has no such value.
    static func address(_ kind: LightingKind, _ field: LightingField, viaProtocol: Int) -> [UInt8]? {
        if usesChannels(viaProtocol: viaProtocol) {
            guard let channel = channel(kind) else { return nil }
            let id: UInt8
            switch (kind, field) {
            case (_, .brightness): id = 1
            case (_, .effect): id = 2
            case (.backlight, _): return nil
            case (_, .speed): id = 3
            case (.ledMatrix, .color): return nil
            case (_, .color): id = 4
            }
            return [channel, id]
        }
        switch (kind, field) {
        case (.backlight, .brightness): return [0x09]
        case (.backlight, .effect): return [0x0A]
        case (.rgblight, .brightness): return [0x80]
        case (.rgblight, .effect): return [0x81]
        case (.rgblight, .speed): return [0x82]
        case (.rgblight, .color): return [0x83]
        case (.rgbMatrix, .brightness): return [0x01]
        case (.rgbMatrix, .effect): return [0x02]
        case (.rgbMatrix, .speed): return [0x03]
        case (.rgbMatrix, .color): return [0x04]
        default: return nil
        }
    }

    public static func getRequest(_ kind: LightingKind, _ field: LightingField, viaProtocol: Int) -> [UInt8]? {
        address(kind, field, viaProtocol: viaProtocol).map { [getValue] + $0 }
    }

    public static func setRequest(_ kind: LightingKind, _ field: LightingField, _ state: LightingState, viaProtocol: Int) -> [UInt8]? {
        guard let address = address(kind, field, viaProtocol: viaProtocol) else { return nil }
        let data: [UInt8]
        switch field {
        case .brightness: data = [byte(state.brightness)]
        case .effect: data = [byte(state.effect)]
        case .speed: data = [byte(state.speed)]
        case .color: data = [byte(state.hue), byte(state.saturation)]
        }
        return [setValue] + address + data
    }

    public static func saveRequest(_ kind: LightingKind, viaProtocol: Int) -> [UInt8] {
        if kind != .vialRGB, usesChannels(viaProtocol: viaProtocol), let channel = channel(kind) { return [save, channel] }
        return [save]
    }

    /// The value bytes of a get reply (they follow the echoed address).
    public static func value(in reply: [UInt8], kind: LightingKind, field: LightingField, viaProtocol: Int) -> [UInt8] {
        let offset = 1 + (address(kind, field, viaProtocol: viaProtocol)?.count ?? 0)
        return reply.count > offset ? Array(reply[offset...]) : []
    }

    // VialRGB

    public static func vialRGBSetRequest(_ state: LightingState, maxBrightness: Int) -> [UInt8] {
        let value = maxBrightness > 0 ? state.brightness * maxBrightness / 255 : state.brightness
        return [setValue, vialRGBMode, UInt8(state.effect & 0xFF), UInt8(state.effect >> 8 & 0xFF),
                byte(state.speed), byte(state.hue), byte(state.saturation), byte(value)]
    }

    /// [08, 41, idLo, idHi, speed, h, s, v]
    public static func vialRGBState(fromModeReply r: [UInt8], maxBrightness: Int) -> LightingState? {
        guard r.count >= 8 else { return nil }
        let value = Int(r[7])
        return LightingState(brightness: maxBrightness > 0 ? min(255, value * 255 / maxBrightness) : value,
                             effect: Int(r[2]) | Int(r[3]) << 8, speed: Int(r[4]), hue: Int(r[5]), saturation: Int(r[6]))
    }

    /// One page of supported VialRGB ids (little endian uint16, 0xFFFF = end).
    public static func vialRGBSupported(fromReply r: [UInt8]) -> (ids: [Int], done: Bool, last: Int) {
        var ids: [Int] = []
        var last = 0
        var done = false
        var index = 2
        while index + 1 < r.count {
            let id = Int(r[index]) | Int(r[index + 1]) << 8
            if id == 0xFFFF { done = true } else { ids.append(id); last = max(last, id) }
            index += 2
        }
        return (ids, done, last)
    }

    static func byte(_ value: Int) -> UInt8 { UInt8(min(max(value, 0), 255)) }
}

// MARK: - Client

extension VIAClient {
    private func lightingExchange(_ request: [UInt8]) throws -> [UInt8] {
        guard let id = VIACommand(rawValue: request[0]) else { throw HIDError.unexpectedResponse("lighting") }
        return try command(id, Array(request.dropFirst()))
    }

    /// True when the firmware answers a brightness read for this system (channel-based protocol only;
    /// older firmware runs every enabled handler on the same packet, so a probe there proves nothing).
    public func lightingResponds(_ kind: LightingKind, viaProtocol: Int) -> Bool {
        guard LightingProtocol.usesChannels(viaProtocol: viaProtocol),
              let request = LightingProtocol.getRequest(kind, .brightness, viaProtocol: viaProtocol) else { return false }
        // Short, single try: firmware that ignores the command must not stall loading.
        guard let reply = try? connection.exchange(request, timeout: 0.4, retries: 0, expecting: request[0]) else { return false }
        return reply.first == request[0]
    }

    public func lightingState(_ capability: LightingCapability, viaProtocol: Int, vialRGBMax: Int) throws -> LightingState {
        let kind = capability.kind
        if kind == .vialRGB {
            let reply = try lightingExchange([LightingProtocol.getValue, LightingProtocol.vialRGBMode])
            guard let state = LightingProtocol.vialRGBState(fromModeReply: reply, maxBrightness: vialRGBMax) else {
                throw HIDError.unexpectedResponse("VialRGB")
            }
            return state
        }
        var state = LightingState()
        for field in LightingField.allCases {
            guard let request = LightingProtocol.getRequest(kind, field, viaProtocol: viaProtocol) else { continue }
            let value = LightingProtocol.value(in: try lightingExchange(request), kind: kind, field: field, viaProtocol: viaProtocol)
            guard let first = value.first else { continue }
            switch field {
            case .brightness: state.brightness = Int(first)
            case .effect: state.effect = Int(first)
            case .speed: state.speed = Int(first)
            case .color:
                state.hue = Int(first)
                state.saturation = value.count > 1 ? Int(value[1]) : 0
            }
        }
        return state
    }

    /// Changes one value in RAM (shown immediately, lost on unplug until saved).
    public func setLighting(_ kind: LightingKind, _ field: LightingField, _ state: LightingState, viaProtocol: Int, vialRGBMax: Int) throws {
        if kind == .vialRGB {
            try lightingExchange(LightingProtocol.vialRGBSetRequest(state, maxBrightness: vialRGBMax))
            return
        }
        guard let request = LightingProtocol.setRequest(kind, field, state, viaProtocol: viaProtocol) else { return }
        try lightingExchange(request)
    }

    /// Writes the current values to EEPROM.
    public func saveLighting(_ kind: LightingKind, viaProtocol: Int) throws {
        try lightingExchange(LightingProtocol.saveRequest(kind, viaProtocol: viaProtocol))
    }

    /// VialRGB version, maximum brightness and supported effect ids.
    public func vialRGBInfo() throws -> (version: Int, maxBrightness: Int, effects: [Int]) {
        let info = try lightingExchange([LightingProtocol.getValue, LightingProtocol.vialRGBGetInfo])
        guard info.count >= 5 else { throw HIDError.unexpectedResponse("VialRGB") }
        var effects: Set<Int> = [0]
        var after = 0
        for _ in 0..<64 {
            let page = try lightingExchange([LightingProtocol.getValue, LightingProtocol.vialRGBGetSupported,
                                             UInt8(after & 0xFF), UInt8(after >> 8 & 0xFF)])
            let parsed = LightingProtocol.vialRGBSupported(fromReply: page)
            effects.formUnion(parsed.ids)
            if parsed.done || parsed.ids.isEmpty || parsed.last <= after { break }
            after = parsed.last
        }
        return (Int(info[2]) | Int(info[3]) << 8, Int(info[4]), effects.sorted())
    }
}
