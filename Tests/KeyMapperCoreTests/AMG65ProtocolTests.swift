import Foundation
import Testing
@testable import KeyMapperCore

/// Byte-for-byte parity with AMG65 Studio, whose packets run on the user's keyboard.
/// `Fixtures/amg65-golden.json` was produced by compiling Studio's own `Protocol.swift` (and the frame
/// packing lines of its `AMG65HID.swift` bridge) with the inputs used below, in Europe/Istanbul.
@Suite struct AMG65ProtocolTests {
    init() { L10n.current = .turkish }

    private func golden() throws -> [String: Any] {
        let url = try #require(Bundle.module.url(forResource: "amg65-golden", withExtension: "json", subdirectory: "Fixtures"))
        return try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func hex(_ steps: [AMG65Protocol.Step]) -> [String] { steps.map { hex($0.bytes) } }
    private func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined() }

    private var sampleLighting: AMG65Lighting {
        var l = AMG65Lighting()
        l.mode = 7
        l.color = RGB24(r: 12, g: 200, b: 99)
        l.colorful = true
        l.brightness = 4
        l.speed = 2
        l.direction = 1
        return l
    }

    private let sampleColors: [Int: RGB24] = [0: RGB24(r: 255, g: 0, b: 0), 5: RGB24(r: 1, g: 2, b: 3), 127: RGB24(r: 9, g: 8, b: 7)]

    @Test func cablePacketsMatchStudio() throws {
        let g = try golden()
        let lighting = AMG65Protocol.lighting(sampleLighting)
        #expect(hex(lighting) == g["lighting"] as? [String])
        #expect(Int(AMG65Protocol.checksum(lighting)) == g["lightingChecksum"] as? Int)

        var settings = AMG65DeviceSettings()
        settings.screenBrightness = 3
        settings.sleep = 2
        settings.fnToggle = true
        settings.gameMode = true
        settings.blockAltTab = true
        settings.blockWindowsKey = true
        let settingsSteps = AMG65Protocol.settings(settings)
        #expect(hex(settingsSteps) == g["settings"] as? [String])
        #expect(Int(AMG65Protocol.checksum(settingsSteps)) == g["settingsChecksum"] as? Int)

        let colorSteps = AMG65Protocol.customColors(sampleColors)
        #expect(hex(colorSteps) == g["customColors"] as? [String])
        #expect(Int(AMG65Protocol.checksum(colorSteps)) == g["customChecksum"] as? Int)
        #expect(hex(AMG65Protocol.customColorMode(brightness: 3)) == g["customMode"] as? [String])
        #expect(hex(AMG65Protocol.keyTable([0: [1, 2, 3, 4], 126: [5, 6, 7, 8]])) == g["keymap"] as? [String])
    }

    @Test func clockMatchesStudioAndUsesISOWeekdays() throws {
        let g = try golden()
        let istanbul = try #require(TimeZone(identifier: "Europe/Istanbul"))
        let instant = Date(timeIntervalSince1970: 1794691845)
        #expect(hex(AMG65Protocol.timeSync(instant, timeZone: istanbul, view: 0)) == g["timeView0"] as? [String])
        #expect(hex(AMG65Protocol.timeSync(instant, timeZone: istanbul, view: 1)) == g["timeView1"] as? [String])
        // 2026-11-15 00:30:45 is a Sunday: ISO weekday 7. The clock data isn't part of the checksum.
        let data = AMG65Protocol.timeSync(instant, timeZone: istanbul)[2]
        #expect(Array(data.bytes.prefix(11)) == [0, 0, 0x5A, 26, 11, 15, 0, 30, 45, 0, 7])
        #expect(data.kind == .uncountedData)
    }

    @Test func receiverPacketsMatchStudio() throws {
        let g = try golden()
        #expect(AMG65DongleProtocol.lighting(sampleLighting).map(hex) == g["dongleLighting"] as? [String])
        #expect(AMG65DongleProtocol.customColors(sampleColors, brightness: 3).map(hex) == g["dongleCustom"] as? [String])
        #expect(AMG65DongleProtocol.keyTable([0: [1, 2, 3, 4], 126: [5, 6, 7, 8]]).map(hex) == g["dongleKeymap"] as? [String])
    }

    @Test func liveFrameMatchesTheBridge() throws {
        let g = try golden()
        var pixels: [RGB24] = []
        for index in 0..<315 {
            let r = UInt8(index % 255), g = UInt8((index * 7) % 255), b = UInt8((index * 13) % 255)
            pixels.append(RGB24(r: r, g: g, b: b))
        }
        let steps = AMG65Protocol.liveFrame(pixels)
        // begin, header (15 packets follow), 15 data packets, flush, end.
        #expect(steps.count == 19)
        let header: [UInt8] = Array(steps[1].bytes.prefix(2))
        #expect(header == [0x04, 0x35])
        #expect(steps[1].bytes[8] == 15)
        let data: [String] = steps[2...16].map { hex($0.bytes) }
        #expect(data == g["frameData"] as? [String])
        let flush = steps[17]
        #expect(flush.kind == AMG65Protocol.Step.Kind.flush)
        #expect(flush.bytes.allSatisfy { $0 == 0 })
        // 255 is a status value on the matrix: colours are clamped to 254.
        let white = AMG65Protocol.liveFrame([RGB24](repeating: RGB24(r: 255, g: 255, b: 255), count: 315))
        #expect(white[2].bytes.prefix(3).allSatisfy { $0 == 254 })
    }

    @Test func acknowledgementsAndChecksumsFollowTheBridge() {
        let lighting = AMG65Protocol.lighting(sampleLighting)
        // Header packets are acknowledged with their own opcode, data packets with 0x41.
        #expect(lighting.map(\.expectedOpcode) == [0x18, 0x13, 0x41, 0x02, 0xF0])
        // The clock has no counted data, so its end reply carries no checksum to check.
        #expect(!AMG65Protocol.timeSync(Date()).contains { $0.kind == .data })
        #expect(AMG65Protocol.stopLiveFrames.map(\.expectedOpcode) == [0x02, 0xF0])
    }

    @Test func vendorChannelsAreRecognisedByUsagePageNotJustIDs() {
        func info(_ vendor: Int, _ product: Int, _ page: Int, _ name: String) -> HIDInterfaceInfo {
            HIDInterfaceInfo(registryID: 7, vendorID: vendor, productID: product, usagePairs: [.init(page: page, usage: 0x61)],
                             product: name, manufacturer: "", serial: "", transport: "USB", locationID: 1, builtIn: false)
        }
        #expect(ScreenKeyboardCatalog.channel(for: info(0x0C45, 0x800A, 0xFF68, "LEOBOG AMG65"))?.link == .wired)
        // AULA F75 Max: same IDs, different page and protocol.
        #expect(ScreenKeyboardCatalog.channel(for: info(0x0C45, 0x800A, 0xFF13, "AULA F75 Max")) == nil)
        #expect(ScreenKeyboardCatalog.channel(for: info(0x05AC, 0x024F, 0xFF60, "AMG65 Dongle"))?.link == .dongle)
        #expect(ScreenKeyboardCatalog.channel(for: info(0x05AC, 0x024F, 0xFF60, "Other Dongle")) == nil)
        #expect(ScreenKeyboardChannel(model: .leobogAMG65, link: .wired, registryID: 1).reportSize == 64)
    }

    @Test(arguments: [AppLanguage.english, .spanish, .japanese, .chinese])
    func effectNamesAreTranslated(language: AppLanguage) throws {
        // Effect titles go through L() at runtime, so the source scan can't see them.
        let table = try #require(L10n.table(for: language))
        #expect(AMG65Effect.titleKeys.count == AMG65Protocol.effects.count)
        for key in AMG65Effect.titleKeys.values.sorted() { #expect(table[key] != nil, "\(key) has no \(language) translation") }
    }

    @Test func hexColoursParseStrictly() {
        #expect(RGB24(hex: "#0C64FF") == RGB24(r: 12, g: 100, b: 255))
        #expect(RGB24(hex: "0c64ff")?.hex == "#0C64FF")
        #expect(RGB24(hex: "#FFF") == nil)
        #expect(RGB24(hex: "#0C64FF80") == nil)
    }
}
