import Foundation

public struct Brand: Hashable, Sendable {
    public let name: String
    /// What the brand's keyboards usually run, shown as a hint.
    public let ecosystem: String

    public init(name: String, ecosystem: String) {
        self.name = name
        self.ecosystem = ecosystem
    }
}

/// USB / Bluetooth vendor IDs of popular keyboard makers.
///
/// The brand is only informative: what the app can do is decided by probing the
/// device (raw HID → VIA/Vial firmware editing, otherwise macOS remapping), so
/// any QMK/VIA/Vial keyboard works even if its vendor is not listed here.
public enum BrandDatabase {
    static let vendors: [Int: Brand] = [
        0x3434: Brand(name: "Keychron", ecosystem: "QMK / VIA"),
        0x05AC: Brand(name: "Apple", ecosystem: "macOS"),
        0x004C: Brand(name: "Apple", ecosystem: "macOS"),
        0x046D: Brand(name: "Logitech", ecosystem: "Logi Options+"),
        0x1532: Brand(name: "Razer", ecosystem: "Synapse"),
        0x1B1C: Brand(name: "Corsair", ecosystem: "iCUE"),
        0x1038: Brand(name: "SteelSeries", ecosystem: "GG"),
        0x0951: Brand(name: "HyperX", ecosystem: "NGENUITY"),
        0x03F0: Brand(name: "HyperX / HP", ecosystem: "NGENUITY"),
        0x320F: Brand(name: "Glorious", ecosystem: "Glorious Core / QMK"),
        0x19F5: Brand(name: "NuPhy", ecosystem: "NuPhy Console / VIA"),
        0x31E3: Brand(name: "Wooting", ecosystem: "Wootility"),
        0x24F0: Brand(name: "Das Keyboard", ecosystem: "Q"),
        0x2516: Brand(name: "Cooler Master", ecosystem: "MasterPlus"),
        0x0B05: Brand(name: "ASUS ROG", ecosystem: "Armoury Crate"),
        0x1E7D: Brand(name: "ROCCAT", ecosystem: "Swarm"),
        0x29EA: Brand(name: "Kinesis", ecosystem: "SmartSet / ZMK"),
        0x3297: Brand(name: "ZSA", ecosystem: "Oryx / Keymapp"),
        0x4653: Brand(name: "foostan (Corne)", ecosystem: "QMK / Vial"),
        0xCB10: Brand(name: "Keebio", ecosystem: "QMK / VIA"),
        0x4B42: Brand(name: "KBDfans", ecosystem: "QMK / VIA"),
        0x445A: Brand(name: "DZTech", ecosystem: "QMK / VIA"),
        0x4B50: Brand(name: "KPrepublic", ecosystem: "QMK / VIA"),
        0x04D8: Brand(name: "Drop / Microchip", ecosystem: "QMK"),
        0xFEED: Brand(name: "QMK (generic)", ecosystem: "QMK"),
        0x1209: Brand(name: "pid.codes (open hardware)", ecosystem: "QMK / ZMK"),
        0x1D50: Brand(name: "OpenMoko (ZMK)", ecosystem: "ZMK"),
        0x0483: Brand(name: "STMicro (QMK boards)", ecosystem: "QMK"),
        0x16C0: Brand(name: "Teensy (QMK boards)", ecosystem: "QMK"),
        0xE118: Brand(name: "Jezail Funder (Cornix)", ecosystem: "Vial"),
        0x04D9: Brand(name: "Holtek (Ducky, OEM)", ecosystem: "OEM"),
        0x0C45: Brand(name: "Sonix (Akko, Redragon, OEM)", ecosystem: "OEM"),
        0x258A: Brand(name: "SINO WEALTH (Royal Kludge, OEM)", ecosystem: "OEM"),
        0x045E: Brand(name: "Microsoft", ecosystem: "Mouse and Keyboard Center"),
        0x413C: Brand(name: "Dell", ecosystem: "—"),
        0x17EF: Brand(name: "Lenovo", ecosystem: "—"),
    ]

    public static func brand(vendorID: Int, productID: Int, manufacturer: String) -> Brand {
        if vendorID == 0x1D50 && productID == 0x615E { return Brand(name: "ZMK", ecosystem: "ZMK Studio") }
        if let brand = vendors[vendorID] { return brand }
        let trimmed = manufacturer.trimmingCharacters(in: .whitespaces)
        return Brand(name: trimmed.isEmpty ? "Bilinmeyen üretici" : trimmed, ecosystem: "—")
    }

    /// Brands listed in the UI as "supported".
    public static var knownBrandNames: [String] {
        Array(Set(vendors.values.map(\.name))).sorted()
    }
}
