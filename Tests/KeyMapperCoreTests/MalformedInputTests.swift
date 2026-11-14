import Foundation
import Testing
@testable import KeyMapperCore

/// Definitions and keycode strings come from outside (VIA repository, user files, the keyboard itself);
/// bad values must be rejected, never crash.
@Suite struct MalformedInputTests {
    @Test func negativeAndOversizedNumbersAreRejected() {
        let set = KeycodeSet.v6
        #expect(set.parse("-1") == nil)
        #expect(set.parse("0x10000") == nil)
        #expect(set.parse("MT(-1, KC_A)") == nil)
        #expect(set.parse("MO(-3)") == nil)
        #expect(set.parse("LT(99, KC_A)") == nil)
        #expect(set.parse("TD(4096)") == nil)
    }

    @Test func absurdMatrixIsRejected() {
        let json = #"{"name":"x","matrix":{"rows":100000,"cols":2},"layouts":{"keymap":[["0,0"]]}}"#
        #expect(throws: DefinitionError.self) { try DefinitionParser.parse(Data(json.utf8), source: .userFile) }
    }

    @Test func keysOutsideTheMatrixAreDropped() throws {
        let json = #"{"name":"x","matrix":{"rows":2,"cols":2},"layouts":{"keymap":[["0,0","1,1","5,0","-1,0","0,9"],["999,0\n\n\n\n\n\n\n\n\ne","0,1\n\n\n\n\n\n\n\n\ne"]]}}"#
        let definition = try DefinitionParser.parse(Data(json.utf8), source: .userFile)
        #expect(definition.keys.filter { !$0.isEncoder }.map { "\($0.row),\($0.col)" } == ["0,0", "1,1"])
        #expect(definition.encoderCount == 1)
    }

    @Test func keymapSetIgnoresNegativeIndices() {
        var keymap = Keymap(layers: [[[1, 2]]], encoders: [[.init(ccw: 0, cw: 0)]])
        keymap.set(9, layer: -1, slot: .matrix(row: 0, col: 0))
        keymap.set(9, layer: 0, slot: .matrix(row: -1, col: 0))
        keymap.set(9, layer: 0, slot: .encoder(index: -1, clockwise: true))
        #expect(keymap == Keymap(layers: [[[1, 2]]], encoders: [[.init(ccw: 0, cw: 0)]]))
    }
}
