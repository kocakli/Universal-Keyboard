import Foundation
import Testing
@testable import KeyMapperCore

func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

@Suite struct DefinitionTests {
    @Test func vialKLEWithRotationAndEncoders() throws {
        let definition = try DefinitionParser.parse(fixture("cornix-vial"), source: .vialFirmware)
        #expect(definition.rows == 8 && definition.cols == 7)
        #expect(definition.vendorID == 0xE118 && definition.productID == 0x0001)
        #expect(definition.customKeycodes.count == 8)
        #expect(definition.encoderCount == 2)
        let matrixKeys = definition.keys.filter { !$0.isEncoder }
        #expect(Set(matrixKeys.map { "\($0.row),\($0.col)" }).count == matrixKeys.count)
        let thumb = try #require(definition.keys.first { $0.row == 3 && $0.col == 4 })
        #expect(abs(thumb.x - 4.5) < 0.001 && abs(thumb.y - 3.7) < 0.001)
        #expect(thumb.r == 11.93 && thumb.rx == 5 && thumb.ry == 4.75)
        let rightThumb = try #require(definition.keys.first { $0.row == 7 && $0.col == 4 })
        #expect(rightThumb.rx == 9.25 && rightThumb.r == -11.93)
        #expect(definition.layoutOptions.first?.title == "Firmware Version")
    }

    @Test func compiledVIADefinition() throws {
        let definition = try DefinitionParser.parse(fixture("keychron-v1-via"), source: .viaRepository)
        #expect(definition.name == "Keychron V1 ANSI Knob")
        #expect(definition.vendorID == 0x3434)
        #expect(definition.rows == 6 && definition.cols == 16)
        #expect(definition.keys.count > 80)
        #expect(definition.encoderCount == 1)
        #expect(definition.customKeycodes.contains { $0.name == "Mission Control" })
    }

    @Test func layoutOptionBits() {
        let definition = KeyboardDefinition(
            name: "t", vendorID: 0, productID: 0, rows: 1, cols: 1, keys: [],
            layoutOptions: [LayoutOption(title: "Split BS", choices: []), LayoutOption(title: "Bottom", choices: ["ANSI", "Tsangan", "WKL"])],
            source: .builtIn)
        // Last option occupies the lowest bits: bottom = 2 (2 bits), split = 1.
        #expect(definition.selectedOptions(packed: 0b1_10) == [1, 2])
    }

    @Test func lzmaRoundTrip() throws {
        let original = try fixture("cornix-vial")
        let compressed = try #require(LZMA.compress(original))
        #expect(try LZMA.decompress(compressed) == original)
    }
}
