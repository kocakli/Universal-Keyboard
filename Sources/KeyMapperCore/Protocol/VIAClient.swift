import Compression
import Foundation

/// VIA raw HID command ids (quantum/via.h).
enum VIACommand: UInt8 {
    case getProtocolVersion = 0x01
    case getKeyboardValue = 0x02
    case setKeyboardValue = 0x03
    case getKeycode = 0x04
    case setKeycode = 0x05
    case getLayerCount = 0x11
    case getBuffer = 0x12
    case getEncoder = 0x14
    case setEncoder = 0x15
    case vialPrefix = 0xFE
    case unhandled = 0xFF
}

/// Vial sub commands (sent after the 0xFE prefix).
enum VialCommand: UInt8 {
    case getKeyboardID = 0x00
    case getSize = 0x01
    case getDefinition = 0x02
    case getEncoder = 0x03
    case setEncoder = 0x04
    case getUnlockStatus = 0x05
    case unlockStart = 0x06
    case unlockPoll = 0x07
    case lock = 0x08
}

public struct VialUnlockStatus: Sendable, Equatable {
    public let unlocked: Bool
    public let inProgress: Bool
    /// Matrix positions (row, col) the user has to hold to unlock.
    public let keys: [MatrixPosition]
}

public struct MatrixPosition: Hashable, Codable, Sendable {
    public let row: Int
    public let col: Int
    public init(row: Int, col: Int) { self.row = row; self.col = col }
}

/// Speaks the VIA protocol, plus Vial extensions when available.
/// All calls are blocking; run them off the main thread.
public final class VIAClient: @unchecked Sendable {
    public let connection: RawHIDConnection

    public init(connection: RawHIDConnection) {
        self.connection = connection
    }

    // MARK: VIA

    @discardableResult
    func command(_ id: VIACommand, _ payload: [UInt8] = [], checkEcho: Bool = true) throws -> [UInt8] {
        let response = try connection.exchange([id.rawValue] + payload)
        if checkEcho {
            if response[0] == VIACommand.unhandled.rawValue && id != .unhandled {
                throw HIDError.unexpectedResponse("komut 0x\(String(id.rawValue, radix: 16)) desteklenmiyor")
            }
            if response[0] != id.rawValue {
                throw HIDError.unexpectedResponse("komut 0x\(String(id.rawValue, radix: 16)) yanıtı 0x\(String(response[0], radix: 16))")
            }
        }
        return response
    }

    public func protocolVersion() throws -> Int {
        let r = try command(.getProtocolVersion)
        return Int(r[1]) << 8 | Int(r[2])
    }

    public func layerCount() throws -> Int {
        Int(try command(.getLayerCount)[1])
    }

    /// Packed layout options value (id_layout_options).
    public func layoutOptions() throws -> UInt32 {
        let r = try command(.getKeyboardValue, [0x02])
        return UInt32(r[2]) << 24 | UInt32(r[3]) << 16 | UInt32(r[4]) << 8 | UInt32(r[5])
    }

    public func keycode(layer: Int, row: Int, col: Int) throws -> UInt16 {
        let r = try command(.getKeycode, [UInt8(layer), UInt8(row), UInt8(col)])
        return UInt16(r[4]) << 8 | UInt16(r[5])
    }

    public func setKeycode(_ code: UInt16, layer: Int, row: Int, col: Int) throws {
        try command(.setKeycode, [UInt8(layer), UInt8(row), UInt8(col), UInt8(code >> 8), UInt8(code & 0xFF)])
    }

    /// Reads the whole dynamic keymap: [layer][row][col].
    public func readKeymap(layers: Int, rows: Int, cols: Int) throws -> [[[UInt16]]] {
        let total = layers * rows * cols * 2
        var bytes: [UInt8] = []
        bytes.reserveCapacity(total)
        var offset = 0
        while offset < total {
            let size = min(28, total - offset)
            let r = try command(.getBuffer, [UInt8(offset >> 8), UInt8(offset & 0xFF), UInt8(size)])
            bytes.append(contentsOf: r[4..<(4 + size)])
            offset += size
        }
        var keymap = [[[UInt16]]](repeating: [[UInt16]](repeating: [UInt16](repeating: 0, count: cols), count: rows), count: layers)
        for layer in 0..<layers {
            for row in 0..<rows {
                for col in 0..<cols {
                    let index = ((layer * rows + row) * cols + col) * 2
                    keymap[layer][row][col] = UInt16(bytes[index]) << 8 | UInt16(bytes[index + 1])
                }
            }
        }
        return keymap
    }

    public func encoder(layer: Int, index: Int, clockwise: Bool) throws -> UInt16 {
        let r = try command(.getEncoder, [UInt8(layer), UInt8(index), clockwise ? 1 : 0])
        return UInt16(r[4]) << 8 | UInt16(r[5])
    }

    public func setEncoder(_ code: UInt16, layer: Int, index: Int, clockwise: Bool) throws {
        try command(.setEncoder, [UInt8(layer), UInt8(index), clockwise ? 1 : 0, UInt8(code >> 8), UInt8(code & 0xFF)])
    }

    // MARK: Vial

    private func vial(_ sub: VialCommand, _ payload: [UInt8] = []) throws -> [UInt8] {
        try connection.exchange([VIACommand.vialPrefix.rawValue, sub.rawValue] + payload)
    }

    /// Returns (vial protocol version, keyboard uid).
    public func vialKeyboardID() throws -> (protocol: Int, uid: UInt64) {
        let r = try vial(.getKeyboardID)
        let proto = Int(r[0]) | Int(r[1]) << 8 | Int(r[2]) << 16 | Int(r[3]) << 24
        var uid: UInt64 = 0
        for i in 0..<8 { uid |= UInt64(r[4 + i]) << (8 * UInt64(i)) }
        return (proto, uid)
    }

    /// Downloads and decompresses the keyboard definition JSON stored in Vial firmware.
    public func vialDefinitionJSON() throws -> Data {
        let r = try vial(.getSize)
        let size = Int(r[0]) | Int(r[1]) << 8 | Int(r[2]) << 16 | Int(r[3]) << 24
        guard size > 0, size < 1 << 20 else { throw HIDError.unexpectedResponse("geçersiz Vial tanım boyutu \(size)") }
        var blob: [UInt8] = []
        var block: UInt32 = 0
        while blob.count < size {
            let page = try vial(.getDefinition, [UInt8(block & 0xFF), UInt8(block >> 8 & 0xFF), UInt8(block >> 16 & 0xFF), UInt8(block >> 24)])
            blob.append(contentsOf: page.prefix(RawHIDConnection.reportSize))
            block += 1
        }
        return try LZMA.decompress(Data(blob.prefix(size)))
    }

    public func vialEncoder(layer: Int, index: Int) throws -> (ccw: UInt16, cw: UInt16) {
        let r = try vial(.getEncoder, [UInt8(layer), UInt8(index)])
        return (UInt16(r[0]) << 8 | UInt16(r[1]), UInt16(r[2]) << 8 | UInt16(r[3]))
    }

    public func vialSetEncoder(_ code: UInt16, layer: Int, index: Int, clockwise: Bool) throws {
        _ = try vial(.setEncoder, [UInt8(layer), UInt8(index), clockwise ? 1 : 0, UInt8(code >> 8), UInt8(code & 0xFF)])
    }

    public func vialUnlockStatus() throws -> VialUnlockStatus {
        let r = try vial(.getUnlockStatus)
        var keys: [MatrixPosition] = []
        var i = 2
        while i + 1 < r.count, r[i] != 0xFF, r[i + 1] != 0xFF {
            keys.append(MatrixPosition(row: Int(r[i]), col: Int(r[i + 1])))
            i += 2
        }
        return VialUnlockStatus(unlocked: r[0] == 1, inProgress: r[1] == 1, keys: keys)
    }

    public func vialUnlockStart() throws { _ = try vial(.unlockStart) }

    /// Returns (unlocked, remaining counter).
    public func vialUnlockPoll() throws -> (unlocked: Bool, counter: Int) {
        let r = try vial(.unlockPoll)
        return (r[0] == 1, Int(r[2]))
    }

    public func vialLock() throws { _ = try vial(.lock) }
}

/// xz / LZMA2 decoding via Apple's Compression framework (used by Vial definitions).
public enum LZMA {
    public static func decompress(_ data: Data) throws -> Data {
        let capacity = 1 << 22
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        defer { destination.deallocate() }
        let count = data.withUnsafeBytes { raw -> Int in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_decode_buffer(destination, capacity, base, data.count, nil, COMPRESSION_LZMA)
        }
        guard count > 0 else { throw HIDError.unexpectedResponse("Vial tanımı açılamadı (LZMA)") }
        return Data(bytes: destination, count: count)
    }

    public static func compress(_ data: Data) -> Data? {
        let capacity = max(data.count * 2, 4096)
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        defer { destination.deallocate() }
        let count = data.withUnsafeBytes { raw -> Int in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_encode_buffer(destination, capacity, base, data.count, nil, COMPRESSION_LZMA)
        }
        return count > 0 ? Data(bytes: destination, count: count) : nil
    }
}
