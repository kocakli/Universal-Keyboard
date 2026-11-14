import Foundation
import IOKit

/// Battery charge of a connected device, 0–100. Split keyboards may report one value per half.
public struct BatteryStatus: Sendable, Equatable {
    public let levels: [Int]

    public init(levels: [Int]) {
        self.levels = levels.map { min(max($0, 0), 100) }
    }

    /// The emptiest cell decides when to charge, so that is the one shown.
    public var level: Int { levels.min() ?? 0 }
    public var isLow: Bool { level <= 20 }
}

/// Battery levels macOS keeps in IORegistry as `BatteryPercent`: Apple keyboards and some Bluetooth
/// Classic devices. Bluetooth LE keyboards report theirs over GATT instead (read in the app).
/// Keychron's raw HID protocol has no battery command, so a Keychron on USB has no reading.
public enum BatteryReader {
    public struct Entry: Sendable, Equatable {
        public let vendorID: Int
        public let productID: Int
        /// Serial number or Bluetooth address, used when two identical devices are connected.
        public let serial: String
        public let percent: Int

        public init(vendorID: Int, productID: Int, serial: String, percent: Int) {
            self.vendorID = vendorID
            self.productID = productID
            self.serial = serial
            self.percent = percent
        }
    }

    /// Every IORegistry service that reports `BatteryPercent`. Read only and cheap (one matching call).
    public static func registryEntries() -> [Entry] {
        let matching = ["IOPropertyExistsMatch": "BatteryPercent"] as CFDictionary
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var entries: [Entry] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            func property(_ key: String) -> Any? {
                IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
            }
            guard let percent = (property("BatteryPercent") as? NSNumber)?.intValue,
                  let vendor = (property("VendorID") as? NSNumber)?.intValue,
                  let product = (property("ProductID") as? NSNumber)?.intValue else { continue }
            let serial = (property("SerialNumber") as? String) ?? (property("DeviceAddress") as? String) ?? ""
            entries.append(Entry(vendorID: vendor, productID: product, serial: serial, percent: percent))
        }
        return entries
    }

    /// The entry for `device`: same vendor and product, and the same serial when several match.
    public static func status(for device: KeyboardDevice, in entries: [Entry]) -> BatteryStatus? {
        let candidates = entries.filter { $0.vendorID == device.vendorID && $0.productID == device.productID }
        let entry: Entry?
        if candidates.count <= 1 {
            entry = candidates.first
        } else {
            let serial = hexDigits(device.serial)
            entry = serial.isEmpty ? nil : candidates.first { hexDigits($0.serial) == serial }
        }
        return entry.map { BatteryStatus(levels: [$0.percent]) }
    }

    /// "38:09:FB:21:A9:8C" and "38-09-fb-21-a9-8c" compare equal.
    static func hexDigits(_ text: String) -> String { text.lowercased().filter(\.isHexDigit) }
}

extension KeyboardDevice {
    /// Bluetooth LE keyboards report battery over the GATT Battery Service, not IORegistry.
    public var isBluetoothLE: Bool { transport.lowercased() == "bluetooth low energy" }
}
