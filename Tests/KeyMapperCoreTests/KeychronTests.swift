import Foundation
import Testing
@testable import KeyMapperCore

@Suite struct KeychronTests {
    init() { L10n.current = .turkish }

    @Test func launcherRepliesParseForBothFirmwareFamilies() {
        func reply(_ bytes: [UInt8]) -> [UInt8] { bytes + [UInt8](repeating: 0, count: 32 - bytes.count) }
        // QMK (keychron/qmk_firmware 2025q3): [A0, 2, 0, 2], [A3, default, active], features in byte 2.
        #expect(KeychronProtocol.family(protocolReply: reply([0xA0, 2, 0, 2])) == .qmk)
        let qmk = KeychronProtocol.layers(reply: reply([0xA3, 2, 3]), family: .qmk)
        #expect(qmk.default == 2 && qmk.active == 3)
        let features = KeychronProtocol.features(reply: reply([0xA2, 0, 0x07, 0x02]), family: .qmk)
        #expect(features.bluetooth && features.wireless24G)
        #expect(KeychronProtocol.reportRate(reply: reply([0xA7, 0x0D, 0, 3])) == 1000)
        #expect(KeychronProtocol.reportRate(reply: reply([0xA7, 0x0D, 1, 3])) == nil)
        // ZMK launcher (Nape Pro reply read from the device): [A0, 1, 0, 1], [A3, active].
        #expect(KeychronProtocol.family(protocolReply: reply([0xA0, 1, 0, 1])) == .zmk)
        let zmk = KeychronProtocol.layers(reply: reply([0xA3, 1]), family: .zmk)
        #expect(zmk.default == nil && zmk.active == 1)
        var status = KeychronStatus(family: .zmk, activeLayer: 1)
        #expect(status.baseLayer == 1)
        status.defaultLayer = 0
        #expect(status.baseLayer == 0)
        // Garbage and other firmware.
        #expect(KeychronProtocol.family(protocolReply: reply([0xFF])) == nil)
        #expect(KeychronProtocol.layers(reply: reply([0xA3, 200, 1]), family: .qmk).default == nil)
        #expect(KeychronProtocol.isUnsolicited(reply([0xA3, 0, 1])))
        #expect(!KeychronProtocol.isUnsolicited(reply([0x04, 0, 0])))
    }

    @Test func trackballDefinitionBecomesAButtonRow() throws {
        let definition = try KeychronLauncher.parseDefinition(fixture("keychron-nape-pro"), vendorID: 0x3434, productID: 0x0440)
        #expect(definition.name == "Nape Pro")
        #expect(definition.rows == 1 && definition.cols == 7)
        #expect(definition.keys.filter { !$0.isEncoder }.map(\.col).sorted() == [0, 1, 2, 3, 4, 5])
        #expect(definition.encoderCount == 1)
        #expect(definition.customKeycodes.count == 47)
        #expect(definition.source == .vendor)
        // Buttons must not overlap.
        let buttons = definition.keys.filter { !$0.isEncoder }
        for (i, a) in buttons.enumerated() {
            for b in buttons[(i + 1)...] { #expect(hypot(a.x - b.x, a.y - b.y) >= 1.2) }
        }
    }

    @Test func compiledKeyboardDefinitionStillParses() throws {
        let definition = try KeychronLauncher.parseDefinition(fixture("keychron-v1-via"), vendorID: 0x3434, productID: 0x0311)
        #expect(definition.rows == 6 && definition.cols == 16)
    }

    @Test func productInfoGivesLatestFirmware() throws {
        let product = try #require(KeychronLauncher.parseProduct(fixture("keychron-nape-pro-product")))
        #expect(product.name == "Nape Pro")
        #expect(product.category == 3)
        #expect(product.latest?.version == "1.3.3")
        #expect(product.latest?.downloadURL?.absoluteString.hasPrefix("https://launcher.keychron.com/static/device/875824192/bin/") == true)
        #expect(product.latest?.notes?.contains("Tap/Hold") == true)
    }

    @Test func versionsCompareNumerically() {
        #expect(KeychronLauncher.normalizeVersion("v1.3.3-ZK Nov 10 2026 09:08:33") == "1.3.3")
        #expect(KeychronLauncher.normalizeVersion("v1.2.1 2025-06-17-10:09:52") == "1.2.1")
        #expect(KeychronLauncher.compareVersions("1.3.10", "1.3.9") == .orderedDescending)
        #expect(KeychronLauncher.compareVersions("1.3", "1.3.0") == .orderedSame)
        #expect(FirmwareStatus(current: "1.3.3", latest: FirmwareRelease(version: "1.3.4"), updatePage: nil).isUpdateAvailable)
        #expect(!FirmwareStatus(current: "1.3.3", latest: FirmwareRelease(version: "1.3.3"), updatePage: nil).isUpdateAvailable)
    }

    @Test func definitionFileOrderMatchesLauncher() {
        #expect(KeychronLauncher.definitionFiles(viaProtocol: 12, variant: 0) == ["v3.json", "v2.json"])
        #expect(KeychronLauncher.definitionFiles(viaProtocol: 12, variant: 2) == ["v3-2.json", "v3.json", "v2.json"])
        #expect(KeychronLauncher.definitionFiles(viaProtocol: 9, variant: 0) == ["v2.json", "v3.json"])
    }

    @Test func usbVersionReadsAsDottedFirmware() {
        var device = KeyboardDevice(id: "x", vendorID: 0x3434, productID: 0x0440, name: "", manufacturer: "", serial: "",
                                    transport: "USB", rawHIDRegistryID: nil, interfaceRegistryIDs: [])
        device.versionNumber = 0x0133
        #expect(device.firmwareVersion == "1.3.3")
    }
}
