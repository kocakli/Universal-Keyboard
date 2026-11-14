import Foundation

/// A key in the physical layout, in key units (1u = one standard key).
public struct LayoutKey: Hashable, Codable, Sendable {
    public var row: Int
    public var col: Int
    public var x: Double
    public var y: Double
    public var w: Double
    public var h: Double
    /// Rotation in degrees around (rx, ry).
    public var r: Double
    public var rx: Double
    public var ry: Double
    /// Vial style encoder entry (no matrix position): encoder index and direction (0 = CCW, 1 = CW).
    public var encoderIndex: Int?
    public var encoderDirection: Int?
    /// VIA style knob attached to a matrix key.
    public var knobIndex: Int?
    /// Layout option (group, choice) this key belongs to.
    public var optionGroup: Int?
    public var optionChoice: Int?
    public var decal: Bool
    public var color: String?

    public init(row: Int, col: Int, x: Double, y: Double, w: Double = 1, h: Double = 1,
                r: Double = 0, rx: Double = 0, ry: Double = 0,
                encoderIndex: Int? = nil, encoderDirection: Int? = nil, knobIndex: Int? = nil,
                optionGroup: Int? = nil, optionChoice: Int? = nil, decal: Bool = false, color: String? = nil) {
        self.row = row
        self.col = col
        self.x = x
        self.y = y
        self.w = w
        self.h = h
        self.r = r
        self.rx = rx
        self.ry = ry
        self.encoderIndex = encoderIndex
        self.encoderDirection = encoderDirection
        self.knobIndex = knobIndex
        self.optionGroup = optionGroup
        self.optionChoice = optionChoice
        self.decal = decal
        self.color = color
    }

    public var isEncoder: Bool { encoderIndex != nil }
    public var slot: KeySlot {
        if let index = encoderIndex { return .encoder(index: index, clockwise: encoderDirection == 1) }
        return .matrix(row: row, col: col)
    }
}

/// An assignable position: a matrix key or one direction of a rotary encoder.
public enum KeySlot: Hashable, Codable, Sendable {
    case matrix(row: Int, col: Int)
    case encoder(index: Int, clockwise: Bool)
}

/// A layout option label: either a toggle (single title) or a choice list.
public struct LayoutOption: Hashable, Codable, Sendable {
    public var title: String
    /// Empty for a boolean toggle.
    public var choices: [String]

    public var choiceCount: Int { choices.isEmpty ? 2 : choices.count }
    /// Bits used in the packed VIA layout options value.
    public var bitCount: Int {
        let n = choiceCount - 1
        return n <= 0 ? 0 : Int.bitWidth - n.leadingZeroBitCount
    }
}

public enum DefinitionSource: String, Codable, Sendable {
    case vialFirmware, viaRepository, userFile, builtIn

    public var title: String {
        switch self {
        case .vialFirmware: return "Klavyeden (Vial)"
        case .viaRepository: return "VIA deposu"
        case .userFile: return "İçe aktarılan dosya"
        case .builtIn: return "Yerleşik"
        }
    }
}

public struct KeyboardDefinition: Codable, Sendable {
    public var name: String
    public var vendorID: Int
    public var productID: Int
    public var rows: Int
    public var cols: Int
    public var keys: [LayoutKey]
    public var layoutOptions: [LayoutOption]
    public var customKeycodes: [CustomKeycode]
    public var source: DefinitionSource

    public init(name: String, vendorID: Int, productID: Int, rows: Int, cols: Int, keys: [LayoutKey],
                layoutOptions: [LayoutOption] = [], customKeycodes: [CustomKeycode] = [], source: DefinitionSource) {
        self.name = name
        self.vendorID = vendorID
        self.productID = productID
        self.rows = rows
        self.cols = cols
        self.keys = keys
        self.layoutOptions = layoutOptions
        self.customKeycodes = customKeycodes
        self.source = source
    }

    /// Number of rotary encoders referenced by the layout.
    public var encoderCount: Int {
        let indices = keys.compactMap { $0.encoderIndex ?? $0.knobIndex }
        return (indices.max() ?? -1) + 1
    }

    /// Decodes the packed VIA layout options value into one choice per option.
    public func selectedOptions(packed: UInt32) -> [Int] {
        var value = packed
        var result = [Int](repeating: 0, count: layoutOptions.count)
        for index in layoutOptions.indices.reversed() {
            let bits = layoutOptions[index].bitCount
            guard bits > 0 else { continue }
            result[index] = Int(value & ((1 << UInt32(bits)) - 1))
            value >>= UInt32(bits)
        }
        return result
    }

    /// Keys visible for the given layout option choices.
    public func visibleKeys(options: [Int]) -> [LayoutKey] {
        keys.filter { key in
            guard let group = key.optionGroup, let choice = key.optionChoice else { return true }
            let selected = group < options.count ? options[group] : 0
            return selected == choice
        }
    }
}
