import Foundation
import Testing
@testable import KeyMapperCore

/// Keyboards that borrow another vendor's USB / Bluetooth IDs (seen with a LEOBOG AMG65).
@Suite struct SpoofedDeviceTests {
    init() { L10n.current = .turkish }

    private func interface(_ vendor: Int, _ product: Int, page: Int, usage: Int, name: String, id: UInt64) -> HIDInterfaceInfo {
        HIDInterfaceInfo(registryID: id, vendorID: vendor, productID: product,
                         usagePairs: [.init(page: page, usage: usage)], product: name, manufacturer: "Manufacturer Name",
                         serial: "", transport: "USB", locationID: 1, builtIn: false)
    }

    @Test func appleIDDongleWithRawHIDIsNotTreatedAsVIA() {
        // AMG65 2.4 GHz dongle: 05AC:024F with a 0xFF60/0x61 interface that speaks LEOBOG's checksummed protocol.
        let dongle = HIDMonitor.group([
            interface(0x05AC, 0x024F, page: 0x01, usage: 0x06, name: "AMG65 Dongle", id: 1),
            interface(0x05AC, 0x024F, page: 0xFF60, usage: 0x61, name: "AMG65 Dongle", id: 2),
        ])
        #expect(dongle.count == 1)
        #expect(dongle[0].rawHIDRegistryID == nil)
        #expect(dongle[0].capability == .osRemap)

        // A real QMK keyboard keeps its raw HID interface.
        let qmk = HIDMonitor.group([
            interface(0x3434, 0x0440, page: 0x01, usage: 0x06, name: "Keychron Nape Pro", id: 3),
            interface(0x3434, 0x0440, page: 0xFF60, usage: 0x61, name: "Keychron Nape Pro", id: 4),
        ])
        #expect(qmk[0].rawHIDRegistryID == 4)
    }

    @Test func productNameBeatsBorrowedVendorID() {
        #expect(BrandDatabase.brand(vendorID: 0x05AC, productID: 0x024F, manufacturer: "Manufacturer Name",
                                    product: "LEOBOG AMG65-1").name == "LEOBOG")
        #expect(BrandDatabase.brand(vendorID: 0x0C45, productID: 0x800A, manufacturer: "", product: "LEOBOG AMG65").name == "LEOBOG")
        #expect(BrandDatabase.brand(vendorID: 0x05AC, productID: 0x0322, manufacturer: "Apple Inc.",
                                    product: "Magic Keyboard").name == "Apple")
    }
}
