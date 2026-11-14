import Foundation
import Testing
@testable import KeyMapperCore

@Suite struct BatteryTests {
    private func device(vendor: Int, product: Int, serial: String = "", transport: String = "Bluetooth") -> KeyboardDevice {
        KeyboardDevice(id: "\(vendor):\(product):\(serial)", vendorID: vendor, productID: product, name: "", manufacturer: "",
                       serial: serial, transport: transport, rawHIDRegistryID: nil, interfaceRegistryIDs: [])
    }

    @Test func registryEntryMatchesByVendorAndProduct() {
        // What a Magic Keyboard publishes on AppleDeviceManagementHIDEventService.
        let entries = [BatteryReader.Entry(vendorID: 0x004C, productID: 0x0322, serial: "38:09:FB:21:A9:8C", percent: 6)]
        let status = BatteryReader.status(for: device(vendor: 0x004C, product: 0x0322), in: entries)
        #expect(status?.level == 6)
        #expect(status?.isLow == true)
        #expect(BatteryReader.status(for: device(vendor: 0x3434, product: 0x0440), in: entries) == nil)
    }

    @Test func identicalDevicesAreToldApartBySerialOrAddress() {
        let entries = [
            BatteryReader.Entry(vendorID: 0x004C, productID: 0x0322, serial: "38:09:FB:21:A9:8C", percent: 6),
            BatteryReader.Entry(vendorID: 0x004C, productID: 0x0322, serial: "aa-bb-cc-dd-ee-ff", percent: 90),
        ]
        #expect(BatteryReader.status(for: device(vendor: 0x004C, product: 0x0322, serial: "AA:BB:CC:DD:EE:FF"), in: entries)?.level == 90)
        #expect(BatteryReader.status(for: device(vendor: 0x004C, product: 0x0322, serial: "38-09-fb-21-a9-8c"), in: entries)?.level == 6)
        // Two candidates and nothing to tell them apart: show nothing rather than the wrong one.
        #expect(BatteryReader.status(for: device(vendor: 0x004C, product: 0x0322), in: entries) == nil)
    }

    @Test func splitHalvesShowTheLowestLevel() {
        let status = BatteryStatus(levels: [80, 35, 140])
        #expect(status.levels == [80, 35, 100])
        #expect(status.level == 35)
        #expect(!status.isLow)
        #expect(BatteryStatus(levels: [20]).isLow)
    }

    @Test func onlyBluetoothLowEnergyUsesGATT() {
        #expect(device(vendor: 0xE118, product: 0x0001, transport: "Bluetooth Low Energy").isBluetoothLE)
        #expect(!device(vendor: 0x004C, product: 0x0322, transport: "Bluetooth").isBluetoothLE)
        #expect(!device(vendor: 0x3434, product: 0x0440, transport: "USB").isBluetoothLE)
    }
}
