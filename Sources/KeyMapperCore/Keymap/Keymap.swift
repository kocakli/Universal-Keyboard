import Foundation

/// Keycodes for every layer: matrix keys plus encoder rotations.
public struct Keymap: Equatable, Sendable {
    /// [layer][row][col]
    public var layers: [[[UInt16]]]
    /// [layer][encoder] -> (ccw, cw)
    public var encoders: [[EncoderKeycodes]]

    public struct EncoderKeycodes: Equatable, Sendable {
        public var ccw: UInt16
        public var cw: UInt16
        public init(ccw: UInt16, cw: UInt16) { self.ccw = ccw; self.cw = cw }
    }

    public init(layers: [[[UInt16]]], encoders: [[EncoderKeycodes]] = []) {
        self.layers = layers
        self.encoders = encoders
    }

    public var layerCount: Int { layers.count }

    public func keycode(layer: Int, slot: KeySlot) -> UInt16? {
        guard layer >= 0, layer < layers.count else { return nil }
        switch slot {
        case let .matrix(row, col):
            guard row >= 0, row < layers[layer].count, col >= 0, col < layers[layer][row].count else { return nil }
            return layers[layer][row][col]
        case let .encoder(index, clockwise):
            guard layer < encoders.count, index >= 0, index < encoders[layer].count else { return nil }
            return clockwise ? encoders[layer][index].cw : encoders[layer][index].ccw
        }
    }

    public mutating func set(_ code: UInt16, layer: Int, slot: KeySlot) {
        switch slot {
        case let .matrix(row, col):
            guard layer >= 0, layer < layers.count, row >= 0, row < layers[layer].count, col >= 0, col < layers[layer][row].count else { return }
            layers[layer][row][col] = code
        case let .encoder(index, clockwise):
            guard layer >= 0, layer < encoders.count, index >= 0, index < encoders[layer].count else { return }
            if clockwise { encoders[layer][index].cw = code } else { encoders[layer][index].ccw = code }
        }
    }

    /// Every slot whose keycode differs from `other` (same shape assumed).
    public func differences(from other: Keymap) -> [(layer: Int, slot: KeySlot, code: UInt16)] {
        var result: [(Int, KeySlot, UInt16)] = []
        for layer in layers.indices {
            for row in layers[layer].indices {
                for col in layers[layer][row].indices {
                    let code = layers[layer][row][col]
                    if other.keycode(layer: layer, slot: .matrix(row: row, col: col)) != code {
                        result.append((layer, .matrix(row: row, col: col), code))
                    }
                }
            }
            if layer < encoders.count {
                for index in encoders[layer].indices {
                    let enc = encoders[layer][index]
                    if other.keycode(layer: layer, slot: .encoder(index: index, clockwise: false)) != enc.ccw {
                        result.append((layer, .encoder(index: index, clockwise: false), enc.ccw))
                    }
                    if other.keycode(layer: layer, slot: .encoder(index: index, clockwise: true)) != enc.cw {
                        result.append((layer, .encoder(index: index, clockwise: true), enc.cw))
                    }
                }
            }
        }
        return result
    }
}
