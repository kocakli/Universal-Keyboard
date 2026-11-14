import Foundation

/// Keyboards with their own display (clock LCD, LED matrix) and a vendor configuration channel.
/// Each model has its own protocol; this file only knows how to recognise them.
public enum ScreenKeyboardModel: String, Codable, Sendable, CaseIterable {
    /// LEOBOG AMG65: 240×135 colour LCD, 63×5 LED matrix, SONiX MCU with its own HID protocol.
    case leobogAMG65

    public var name: String {
        switch self {
        case .leobogAMG65: return "LEOBOG AMG65"
        }
    }

    /// LCD resolution in pixels.
    public var lcdSize: (width: Int, height: Int) {
        switch self {
        case .leobogAMG65: return (240, 135)
        }
    }

    /// LED matrix resolution (columns × rows).
    public var ledMatrixSize: (columns: Int, rows: Int) {
        switch self {
        case .leobogAMG65: return (63, 5)
        }
    }
}

/// The vendor HID interface a screen keyboard is configured through.
public struct ScreenKeyboardChannel: Hashable, Sendable {
    public enum Link: String, Sendable {
        /// USB cable: the full protocol (clock, lighting, LED frames, uploads).
        case wired
        /// 2.4 GHz receiver: lighting, per-key colours and the key table only.
        case dongle
    }

    public let model: ScreenKeyboardModel
    public let link: Link
    /// IORegistry id of the vendor HID interface.
    public let registryID: UInt64

    public init(model: ScreenKeyboardModel, link: Link, registryID: UInt64) {
        self.model = model
        self.link = link
        self.registryID = registryID
    }

    /// Output / input report size of the vendor interface.
    public var reportSize: Int { link == .wired ? 64 : 32 }

    public var supportsClock: Bool { link == .wired }
    public var supportsLEDMatrix: Bool { link == .wired }
}

public enum ScreenKeyboardCatalog {
    /// Matches one HID interface against the known vendor channels. VID/PID alone is not enough:
    /// the AULA F75 Max shares 0C45:800A but uses another usage page and protocol.
    public static func channel(for info: HIDInterfaceInfo) -> ScreenKeyboardChannel? {
        let pairs = info.usagePairs
        // AMG65 by cable: SONiX 0C45:800A, vendor page 0xFF68 / usage 0x61, 64 byte reports.
        if info.vendorID == 0x0C45, info.productID == 0x800A,
           pairs.contains(where: { $0.page == 0xFF68 && $0.usage == 0x61 }) {
            return ScreenKeyboardChannel(model: .leobogAMG65, link: .wired, registryID: info.registryID)
        }
        // AMG65 2.4 GHz receiver: borrows Apple's 05AC:024F; its 0xFF60 / 0x61 interface uses a
        // checksummed 32 byte protocol (not VIA). The Bluetooth keyboard has the same IDs but no such interface.
        if info.vendorID == 0x05AC, info.productID == 0x024F,
           info.product.range(of: "AMG65", options: .caseInsensitive) != nil,
           pairs.contains(where: { $0.page == 0xFF60 && $0.usage == 0x61 }) {
            return ScreenKeyboardChannel(model: .leobogAMG65, link: .dongle, registryID: info.registryID)
        }
        return nil
    }
}
