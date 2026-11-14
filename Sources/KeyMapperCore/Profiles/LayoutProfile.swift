import Foundation

/// A macOS level remap of one keyboard-page HID usage to another.
public struct KeyRemap: Codable, Hashable, Sendable {
    /// HID keyboard page usage (same numbers as QMK basic keycodes, e.g. 0x39 = Caps Lock).
    public var from: UInt16
    public var to: UInt16

    public init(from: UInt16, to: UInt16) {
        self.from = from
        self.to = to
    }
}

/// A saved layout that can be assigned to a keyboard.
public struct LayoutProfile: Codable, Identifiable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// Written into the keyboard's firmware (VIA / Vial).
        case firmware
        /// Applied by macOS (hidutil) every time the keyboard connects.
        case osRemap
    }

    public var id: UUID
    public var name: String
    /// `VVVV:PPPP` of the keyboard the profile was made for.
    public var deviceKey: String
    public var kind: Kind
    public var createdAt: Date
    public var updatedAt: Date
    public var note: String?

    /// [layer][row][col] keycode expressions; `nil` = leave untouched.
    public var layers: [[[String?]]]?
    /// [layer][encoder][ccw, cw]
    public var encoders: [[[String?]]]?
    public var remaps: [KeyRemap]?

    public init(id: UUID = UUID(), name: String, deviceKey: String, kind: Kind, note: String? = nil,
                layers: [[[String?]]]? = nil, encoders: [[[String?]]]? = nil, remaps: [KeyRemap]? = nil) {
        self.id = id
        self.name = name
        self.deviceKey = deviceKey
        self.kind = kind
        self.createdAt = Date()
        self.updatedAt = Date()
        self.note = note
        self.layers = layers
        self.encoders = encoders
        self.remaps = remaps
    }

    /// Snapshot of a keyboard's current keymap.
    public static func snapshot(name: String, deviceKey: String, keymap: Keymap, keycodes: KeycodeSet) -> LayoutProfile {
        let layers = keymap.layers.map { layer in layer.map { row in row.map { Optional(keycodes.name(for: $0)) } } }
        let encoders = keymap.encoders.map { layer in
            layer.map { [Optional(keycodes.name(for: $0.ccw)), Optional(keycodes.name(for: $0.cw))] }
        }
        return LayoutProfile(name: name, deviceKey: deviceKey, kind: .firmware, layers: layers, encoders: encoders.isEmpty ? nil : encoders)
    }

    public var layerCount: Int { layers?.count ?? 0 }

    /// Builds the keymap this profile describes on top of `current`.
    /// Returns the expressions that could not be parsed.
    public func resolve(onto current: Keymap, keycodes: KeycodeSet) -> (keymap: Keymap, unknown: [String]) {
        var target = current
        var unknown: [String] = []
        for (layerIndex, layer) in (layers ?? []).enumerated() where layerIndex < target.layers.count {
            for (rowIndex, row) in layer.enumerated() where rowIndex < target.layers[layerIndex].count {
                for (colIndex, value) in row.enumerated() where colIndex < target.layers[layerIndex][rowIndex].count {
                    guard let value, value != "-1" else { continue }
                    if let code = keycodes.parse(value) {
                        target.layers[layerIndex][rowIndex][colIndex] = code
                    } else {
                        unknown.append(value)
                    }
                }
            }
        }
        for (layerIndex, layer) in (encoders ?? []).enumerated() where layerIndex < target.encoders.count {
            for (index, pair) in layer.enumerated() where index < target.encoders[layerIndex].count {
                for (direction, value) in pair.prefix(2).enumerated() {
                    guard let value else { continue }
                    guard let code = keycodes.parse(value) else { unknown.append(value); continue }
                    if direction == 0 { target.encoders[layerIndex][index].ccw = code } else { target.encoders[layerIndex][index].cw = code }
                }
            }
        }
        return (target, unknown)
    }
}
