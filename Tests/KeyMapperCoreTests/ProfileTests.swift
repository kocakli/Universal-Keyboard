import Foundation
import Testing
@testable import KeyMapperCore

@Suite struct ProfileTests {
    let keycodes = KeycodeSet.v6

    func sampleKeymap() -> Keymap {
        Keymap(
            layers: [
                [[0x14, 0x1A, 0x08], [0x2204, 0x16, 0x07], [0x412C, 0x5221, 0x01]],
                [[0x1E, 0x1F, 0x20], [0x01, 0x01, 0x01], [0x00, 0x7C00, 0x01]],
            ],
            encoders: [[.init(ccw: 0xAA, cw: 0xA9)], [.init(ccw: 0x01, cw: 0x01)]]
        )
    }

    @Test func vilRoundTrip() throws {
        let keymap = sampleKeymap()
        let data = try LayoutFiles.vilData(keymap: keymap, keycodes: keycodes, uid: 42, viaProtocol: 9, vialProtocol: 6)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("km-test.vil")
        try data.write(to: url)
        let profile = try LayoutFiles.importProfile(from: url, deviceKey: "E118:0001", cols: nil)
        let empty = Keymap(layers: keymap.layers.map { $0.map { $0.map { _ in 0 } } },
                           encoders: keymap.encoders.map { $0.map { _ in .init(ccw: 0, cw: 0) } })
        let resolved = profile.resolve(onto: empty, keycodes: keycodes)
        #expect(resolved.unknown.isEmpty)
        #expect(resolved.keymap == keymap)
    }

    @Test func viaRoundTrip() throws {
        let keymap = sampleKeymap()
        let data = try LayoutFiles.viaData(keymap: keymap, keycodes: keycodes, name: "T", vendorProductID: 0x3434_0311)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("km-test-via.json")
        try data.write(to: url)
        let profile = try LayoutFiles.importProfile(from: url, deviceKey: "3434:0311", cols: 3)
        let resolved = profile.resolve(onto: keymap, keycodes: keycodes)
        #expect(resolved.keymap == keymap)
        #expect(keymap.differences(from: resolved.keymap).isEmpty)
    }

    @Test func differencesOnlyChangedKeys() {
        var target = sampleKeymap()
        target.set(0x04, layer: 1, slot: .matrix(row: 1, col: 1))
        target.set(0x80, layer: 0, slot: .encoder(index: 0, clockwise: true))
        let changes = target.differences(from: sampleKeymap())
        #expect(changes.count == 2)
    }

    @Test func alphaLayoutsAreAligned() {
        for layout in AlphaLayout.all {
            #expect(layout.keys.count == AlphaLayout.qwerty.keys.count, "\(layout.name)")
            #expect(!layout.keys.contains(0), "\(layout.name)")
            #expect(Set(layout.keys) == Set(AlphaLayout.qwerty.keys), "\(layout.name)")
        }
    }

    @Test func colemakKeepsHomeRowMods() {
        // [S with shift hold, D, F]
        let layer: [[UInt16]] = [[keycodes.parse("LSFT_T(KC_S)")!, 0x07, 0x09]]
        let converted = AlphaLayout.convert(layer: layer, from: .qwerty, to: .colemak, keycodes: keycodes)
        #expect(converted == [[keycodes.parse("LSFT_T(KC_R)")!, 0x16, 0x17]])
        let back = AlphaLayout.convert(layer: converted, from: .colemak, to: .qwerty, keycodes: keycodes)
        #expect(back == layer)
    }

    @Test func hidutilOutputParsing() {
        let output = """
        RegistryID  Key                   Value
        100199180   UserKeyMapping   (
                {
                HIDKeyboardModifierMappingDst = 30064771113;
                HIDKeyboardModifierMappingSrc = 30064771129;
            }
        )
        100199181   UserKeyMapping   (
                {
                HIDKeyboardModifierMappingDst = 30064771113;
                HIDKeyboardModifierMappingSrc = 30064771129;
            }
        )
        """
        #expect(HIDUtilRemapper.parse(output) == [KeyRemap(from: 0x39, to: 0x29)])
    }

    @Test func profileStorePersistsAssignments() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("km-profiles-\(UUID().uuidString)")
        let store = ProfileStore(directory: dir)
        let profile = LayoutProfile.snapshot(name: "Test", deviceKey: "E118:0001", keymap: sampleKeymap(), keycodes: keycodes)
        try store.save(profile)
        store.assign(profile, to: "E118:0001")
        #expect(store.profiles(for: "E118:0001").map(\.id) == [profile.id])
        #expect(store.assignedProfile(for: "E118:0001")?.id == profile.id)
        store.delete(profile)
        #expect(store.all().isEmpty)
        #expect(store.assignedProfile(for: "E118:0001") == nil)
        try? FileManager.default.removeItem(at: dir)
    }
}
