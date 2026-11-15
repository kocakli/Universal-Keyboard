import Foundation
import Testing
@testable import KeyMapperCore

@Suite struct LightingTests {
    init() { L10n.current = .turkish }

    private func json(_ text: String) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:]
    }

    @Test func viaV3MenuControlsDeclarePerKeyRGBWithEffectNames() {
        // Shape of a VIA v3 definition's lighting menu (content = [id, channel, value id]).
        let definition = json("""
        {"menus": [{"label": "Lighting", "content": [{"label": "Backlight", "content": [
          {"label": "Brightness", "type": "range", "options": [0, 255], "content": ["id_qmk_rgb_matrix_brightness", 3, 1]},
          {"label": "Effect", "type": "dropdown", "content": ["id_qmk_rgb_matrix_effect", 3, 2],
           "options": [["00. None", 0], ["01. SOLID_COLOR", 1], ["02. BREATHING", 2]]},
          {"label": "Color", "type": "color", "content": ["id_qmk_rgb_matrix_color", 3, 4]}
        ]}]}]}
        """)
        let capabilities = LightingDefinition.capabilities(from: definition)
        #expect(capabilities.map(\.kind) == [.rgbMatrix])
        #expect(capabilities[0].effects.map(\.id) == [0, 1, 2])
        #expect(capabilities[0].effects[1].name == "01. SOLID_COLOR")
    }

    @Test func presetNamesAndVialLightingFieldAreRecognised() {
        #expect(LightingDefinition.capabilities(from: json(#"{"menus": ["qmk_rgblight"]}"#)).map(\.kind) == [.rgblight])
        let both = LightingDefinition.capabilities(from: json(#"{"lighting": "qmk_backlight_rgblight"}"#))
        #expect(both.map(\.kind) == [.backlight, .rgblight])
        // Built-in rgblight list (vial-gui): 0 All Off … 36 Alternating.
        #expect(both[1].effects.count == 37)
        #expect(both[1].effects.last?.name == "Alternating")
        #expect(LightingDefinition.capabilities(from: json(#"{"lighting": "vialrgb"}"#)).map(\.kind) == [.vialRGB])
        #expect(LightingDefinition.capabilities(from: json(#"{"lighting": "none"}"#)).isEmpty)
        #expect(LightingDefinition.capabilities(from: json(#"{"name": "No lights"}"#)).isEmpty)
    }

    @Test func channelPacketsFollowQMKViaProtocol12() {
        // quantum/via.h: [cmd, channel, value id, data…]; rgb_matrix = channel 3, color = id 4.
        #expect(LightingProtocol.getRequest(.rgbMatrix, .brightness, viaProtocol: 13) == [0x08, 3, 1])
        let state = LightingState(brightness: 128, effect: 5, speed: 9, hue: 10, saturation: 200)
        #expect(LightingProtocol.setRequest(.rgbMatrix, .color, state, viaProtocol: 12) == [0x07, 3, 4, 10, 200])
        #expect(LightingProtocol.setRequest(.backlight, .effect, state, viaProtocol: 12) == [0x07, 1, 2, 5])
        #expect(LightingProtocol.setRequest(.backlight, .speed, state, viaProtocol: 12) == nil)
        #expect(LightingProtocol.getRequest(.ledMatrix, .color, viaProtocol: 12) == nil)
        #expect(LightingProtocol.saveRequest(.rgbMatrix, viaProtocol: 12) == [0x09, 3])
        #expect(LightingProtocol.value(in: [0x08, 3, 1, 200, 0], kind: .rgbMatrix, field: .brightness, viaProtocol: 12).first == 200)
    }

    @Test func legacyPacketsFollowVialProtocol9() {
        // vial-qmk quantum/via.h: [cmd, value id, data…]; rgblight 0x80–0x83, backlight 0x09/0x0A.
        let state = LightingState(brightness: 255, effect: 3, speed: 1, hue: 20, saturation: 30)
        #expect(LightingProtocol.getRequest(.backlight, .brightness, viaProtocol: 9) == [0x08, 0x09])
        #expect(LightingProtocol.setRequest(.rgblight, .effect, state, viaProtocol: 9) == [0x07, 0x81, 3])
        #expect(LightingProtocol.setRequest(.rgblight, .color, state, viaProtocol: 9) == [0x07, 0x83, 20, 30])
        #expect(LightingProtocol.saveRequest(.rgblight, viaProtocol: 9) == [0x09])
        #expect(LightingProtocol.getRequest(.ledMatrix, .brightness, viaProtocol: 9) == nil)
        #expect(LightingProtocol.value(in: [0x08, 0x83, 20, 30], kind: .rgblight, field: .color, viaProtocol: 9) == [20, 30])
    }

    @Test func vialRGBPacketsCarryEveryValueAndScaleBrightness() {
        // vialrgb.c: set mode = [07, 41, idLo, idHi, speed, h, s, v]; v is limited to the firmware maximum.
        let state = LightingState(brightness: 255, effect: 0x0102, speed: 7, hue: 8, saturation: 9)
        #expect(LightingProtocol.vialRGBSetRequest(state, maxBrightness: 200) == [0x07, 0x41, 0x02, 0x01, 7, 8, 9, 200])
        let read = LightingProtocol.vialRGBState(fromModeReply: [0x08, 0x41, 0x02, 0x01, 7, 8, 9, 100], maxBrightness: 200)
        #expect(read == LightingState(brightness: 127, effect: 0x0102, speed: 7, hue: 8, saturation: 9))
        // get_supported: little-endian ids after the two echo bytes, padded with 0xFFFF.
        let page = LightingProtocol.vialRGBSupported(fromReply: [0x08, 0x42, 2, 0, 6, 0, 0xFF, 0xFF, 0xFF, 0xFF])
        #expect(page.ids == [2, 6])
        #expect(page.done)
        #expect(page.last == 6)
    }

    @Test func definitionsEncodedBeforeLightingSupportStillDecode() throws {
        let old = #"{"name":"K","vendorID":1,"productID":2,"rows":1,"cols":1,"keys":[],"layoutOptions":[],"customKeycodes":[],"source":"userFile"}"#
        let decoded = try JSONDecoder().decode(KeyboardDefinition.self, from: Data(old.utf8))
        #expect(decoded.lighting.isEmpty)
    }
}
