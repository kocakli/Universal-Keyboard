import Foundation

/// One HID interface (an IOHIDDevice) as seen in the IORegistry.
public struct HIDInterfaceInfo: Hashable, Sendable {
    public let registryID: UInt64
    public let vendorID: Int
    public let productID: Int
    public let usagePairs: [UsagePair]
    public let product: String
    public let manufacturer: String
    public let serial: String
    public let transport: String
    public let locationID: Int
    public let builtIn: Bool

    public struct UsagePair: Hashable, Sendable {
        public let page: Int
        public let usage: Int
    }

    public var isKeyboard: Bool { usagePairs.contains { $0.page == 0x01 && $0.usage == 0x06 } }
    /// QMK raw HID (VIA / Vial) interface: usage page 0xFF60, usage 0x61.
    public var isRawHID: Bool { usagePairs.contains { $0.page == 0xFF60 && $0.usage == 0x61 } }
}

/// How the app can talk to a keyboard.
public enum DeviceCapability: String, Codable, Sendable {
    /// Vial firmware: definition is stored on the keyboard.
    case vial
    /// VIA / QMK firmware: definition comes from the VIA repository or a user supplied JSON.
    case via
    /// No programmable firmware reachable: macOS level per-device remapping (hidutil).
    case osRemap

    public var title: String {
        switch self {
        case .vial: return "Vial"
        case .via: return "VIA"
        case .osRemap: return "macOS"
        }
    }

    public var detail: String {
        switch self {
        case .vial: return "Firmware keymap (Vial)"
        case .via: return "Firmware keymap (VIA/QMK)"
        case .osRemap: return "macOS seviyesinde tuş eşleme"
        }
    }
}

/// A physical keyboard, grouping all of its HID interfaces.
public struct KeyboardDevice: Identifiable, Hashable, Sendable {
    public let id: String
    public let vendorID: Int
    public let productID: Int
    public let name: String
    public let manufacturer: String
    public let serial: String
    public let transport: String
    public let rawHIDRegistryID: UInt64?
    public let interfaceRegistryIDs: [UInt64]

    public init(id: String, vendorID: Int, productID: Int, name: String, manufacturer: String,
                serial: String, transport: String, rawHIDRegistryID: UInt64?, interfaceRegistryIDs: [UInt64]) {
        self.id = id
        self.vendorID = vendorID
        self.productID = productID
        self.name = name
        self.manufacturer = manufacturer
        self.serial = serial
        self.transport = transport
        self.rawHIDRegistryID = rawHIDRegistryID
        self.interfaceRegistryIDs = interfaceRegistryIDs
    }

    /// Vial keyboards advertise a magic serial number.
    public var isVial: Bool { serial.contains("vial:f64c2b3c") }

    public var capability: DeviceCapability {
        if rawHIDRegistryID != nil { return isVial ? .vial : .via }
        return .osRemap
    }

    /// Stable key used for profiles / settings, independent of the connection.
    public var deviceKey: String { String(format: "%04X:%04X", vendorID, productID) }

    /// VIA uses (vid << 16) | pid to look definitions up.
    public var vendorProductID: Int { (vendorID << 16) | productID }

    public var brand: Brand { BrandDatabase.brand(vendorID: vendorID, productID: productID, manufacturer: manufacturer) }

    public var transportLabel: String {
        switch transport.lowercased() {
        case "usb": return "USB"
        case "bluetooth": return "Bluetooth"
        case "bluetooth low energy": return "Bluetooth LE"
        default: return transport.isEmpty ? "?" : transport
        }
    }

    public var displayName: String { name.isEmpty ? "Klavye \(deviceKey)" : name }
}
