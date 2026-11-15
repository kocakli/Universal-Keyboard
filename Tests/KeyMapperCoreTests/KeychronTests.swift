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

    @Test func napeProIsDrawnAsItself() throws {
        let definition = try KeychronLauncher.parseDefinition(fixture("keychron-nape-pro"), vendorID: 0x3434, productID: 0x0440)
        #expect(definition.name == "Nape Pro")
        #expect(definition.rows == 1 && definition.cols == 7)
        #expect(definition.keys.filter { !$0.isEncoder }.map(\.col).sorted() == [0, 1, 2, 3, 4, 5])
        #expect(definition.encoderCount == 1)
        #expect(definition.customKeycodes.count == 47)
        #expect(definition.source == .vendor)

        // Lying below the keyboard (Keychron's 90°): M1/M2, 01/02, the ball in its ring, 03/04, the end cap.
        let body = try #require(definition.deviceBody)
        let ball = try #require(body.ball), ring = try #require(body.ring)
        let buttons = Dictionary(uniqueKeysWithValues: definition.keys.filter { !$0.isEncoder }.map { ($0.name ?? "?", $0) })
        #expect(Set(buttons.keys) == ["01", "02", "03", "04", "M1", "M2"])
        // Each button keeps the column Keychron's firmware reads it from.
        #expect(buttons.mapValues(\.col) == ["03": 0, "04": 1, "01": 2, "02": 3, "M1": 4, "M2": 5])
        func right(_ key: LayoutKey) -> Double { key.x + key.w }
        #expect(right(buttons["M1"]!) <= buttons["01"]!.x && right(buttons["01"]!) <= ring.x - ring.radius)
        #expect(ring.x + ring.radius <= buttons["03"]!.x && right(buttons["03"]!) <= body.width)
        #expect(buttons["M1"]!.y < buttons["M2"]!.y && buttons["01"]!.y < buttons["02"]!.y && buttons["03"]!.y < buttons["04"]!.y)
        #expect(ball.radius < ring.radius && ball.x == ring.x && ball.y == ring.y)
        #expect(ring.y + ring.radius <= body.height && ring.y - ring.radius >= 0)

        // Nothing overlaps, everything is on the body, and the ring's two directions sit on the ring, off the ball.
        func overlaps(_ a: LayoutKey, _ b: LayoutKey) -> Bool {
            a.x < b.x + b.w - 0.001 && b.x < a.x + a.w - 0.001 && a.y < b.y + b.h - 0.001 && b.y < a.y + a.h - 0.001
        }
        for (i, a) in definition.keys.enumerated() {
            #expect(a.x >= 0 && a.y >= 0 && a.x + a.w <= body.width && a.y + a.h <= body.height)
            for b in definition.keys[(i + 1)...] { #expect(!overlaps(a, b)) }
        }
        let ringKeys = definition.keys.filter(\.isEncoder)
        #expect(ringKeys.map(\.encoderDirection) == [0, 1])
        for key in ringKeys {
            let distance = abs(key.x + key.w / 2 - ring.x)
            #expect(distance > ball.radius && distance < ring.radius)
        }
    }

    @Test func otherPointingDevicesKeepTheirButtonRow() throws {
        // A button the Nape Pro drawing doesn't know: the generic row, labelled with Keychron's ids.
        var json = try #require(try JSONSerialization.jsonObject(with: fixture("keychron-nape-pro")) as? [String: Any])
        var layouts = try #require(json["keys"] as? [String: Any])
        var entries = try #require(layouts["0"] as? [[String: Any]])
        entries[0]["id"] = "05"
        layouts["0"] = entries
        json["keys"] = layouts
        let definition = try KeychronLauncher.parseDefinition(JSONSerialization.data(withJSONObject: json),
                                                              vendorID: 0x3434, productID: 0x0999)
        #expect(definition.deviceBody == nil)
        #expect(definition.cols == 7 && definition.encoderCount == 1)
        let buttons = definition.keys.filter { !$0.isEncoder }
        #expect(Set(buttons.compactMap(\.name)) == ["05", "04", "01", "02", "M1", "M2"])
        for (i, a) in buttons.enumerated() {
            for b in buttons[(i + 1)...] { #expect(hypot(a.x - b.x, a.y - b.y) >= 1.2) }
        }
    }

    @Test func definitionsSavedBeforeBodiesStillDecode() throws {
        // Definitions cached by an older build have no key names or device body.
        let key = try JSONDecoder().decode(LayoutKey.self, from: Data(#"{"row":0,"col":1,"x":0,"y":0,"w":1,"h":1,"r":0,"rx":0,"ry":0,"decal":false}"#.utf8))
        #expect(key.name == nil && key.col == 1)
        var old = try KeychronLauncher.parseDefinition(fixture("keychron-v1-via"), vendorID: 0x3434, productID: 0x0311)
        old.deviceBody = nil
        var encoded = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        encoded.removeValue(forKey: "deviceBody")
        let decoded = try JSONDecoder().decode(KeyboardDefinition.self, from: JSONSerialization.data(withJSONObject: encoded))
        #expect(decoded.deviceBody == nil && decoded.keys.count == old.keys.count)
    }

    @Test func onlyPointingDevicesAreDrawnFromTheirButtonList() throws {
        // The Bluetooth remap view draws a trackball's buttons, never a keyboard, from the cached definition.
        let napeData = try fixture("keychron-nape-pro"), keyboardData = try fixture("keychron-v1-via")
        let nape = try #require(KeychronLauncher.pointingDevice(napeData, vendorID: 0x3434, productID: 0x0440))
        // The same buttons the cable editor draws.
        #expect(nape.keys == (try KeychronLauncher.parseDefinition(napeData, vendorID: 0x3434, productID: 0x0440)).keys)
        #expect(KeychronLauncher.pointingDevice(keyboardData, vendorID: 0x3434, productID: 0x0311) == nil)
        #expect(KeychronLauncher.pointingDevice(Data("not json".utf8), vendorID: 0x3434, productID: 0x0440) == nil)
        // Other vendors never look in Keychron's cache.
        #expect(KeychronLauncher.cachedPointingDevice(vendorID: 0x046D, productID: 0x0440) == nil)
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
