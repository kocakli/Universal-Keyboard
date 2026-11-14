import Foundation

/// Everything known about a connected programmable (VIA / Vial) keyboard.
public struct KeyboardState: Sendable {
    public var definition: KeyboardDefinition
    public var keycodes: KeycodeSet
    public var keymap: Keymap
    public var viaProtocol: Int
    public var vialProtocol: Int?
    public var vialUID: UInt64?
    public var layoutOptions: [Int]

    public var layerCount: Int { keymap.layerCount }
}

public enum SessionError: LocalizedError {
    case notProgrammable
    case locked

    public var errorDescription: String? {
        switch self {
        case .notProgrammable: return "Bu klavye VIA/Vial raw HID arayüzü sunmuyor."
        case .locked: return "Bu tuş (QK_BOOT) için Vial kilidinin açılması gerekiyor."
        }
    }
}

/// Serialises all raw HID traffic to one keyboard on a background queue.
public final class KeyboardSession: @unchecked Sendable {
    public let device: KeyboardDevice
    private let client: VIAClient
    private let queue: DispatchQueue

    public init(device: KeyboardDevice) throws {
        guard let registryID = device.rawHIDRegistryID else { throw SessionError.notProgrammable }
        self.device = device
        self.client = VIAClient(connection: try RawHIDConnection(registryID: registryID))
        self.queue = DispatchQueue(label: "keymapper.session.\(device.id)")
    }

    public var isClosed: Bool { client.connection.isClosed }

    public func close() {
        queue.async { [client] in client.connection.close() }
    }

    /// Runs blocking HID work on the session queue.
    public func perform<T>(_ work: @escaping (VIAClient) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [client] in
                do { continuation.resume(returning: try work(client)) } catch { continuation.resume(throwing: error) }
            }
        }
    }

    /// Reads protocol info, definition and the full keymap.
    public func load(definitionStore: DefinitionStore = .shared) async throws -> KeyboardState {
        let device = self.device
        let info = try await perform { client -> (Int, Int?, UInt64?, Data?) in
            let via = try client.protocolVersion()
            guard device.isVial else { return (via, nil, nil, nil) }
            let id = try client.vialKeyboardID()
            let json = try client.vialDefinitionJSON()
            return (via, id.protocol, id.uid, json)
        }

        let definition: KeyboardDefinition
        if let json = info.3 {
            definition = try DefinitionParser.parse(json, source: .vialFirmware)
        } else {
            definition = try await definitionStore.definition(vendorID: device.vendorID, productID: device.productID)
        }

        let version: KeycodeVersion
        if let vial = info.1 {
            version = vial >= 6 ? .v6 : .v5
        } else {
            version = info.0 >= 11 ? .v6 : .v5
        }
        let keycodes = KeycodeSet(version: version, customKeycodes: definition.customKeycodes)
        let isVial = info.1 != nil
        let encoderCount = definition.encoderCount

        let (keymap, packedOptions) = try await perform { client -> (Keymap, UInt32) in
            let layers = try client.layerCount()
            let matrix = try client.readKeymap(layers: layers, rows: definition.rows, cols: definition.cols)
            var encoders: [[Keymap.EncoderKeycodes]] = []
            if encoderCount > 0 {
                for layer in 0..<layers {
                    var row: [Keymap.EncoderKeycodes] = []
                    for index in 0..<encoderCount {
                        if isVial {
                            let pair = try client.vialEncoder(layer: layer, index: index)
                            row.append(.init(ccw: pair.ccw, cw: pair.cw))
                        } else {
                            let ccw = (try? client.encoder(layer: layer, index: index, clockwise: false)) ?? 0
                            let cw = (try? client.encoder(layer: layer, index: index, clockwise: true)) ?? 0
                            row.append(.init(ccw: ccw, cw: cw))
                        }
                    }
                    encoders.append(row)
                }
            }
            let options = (try? client.layoutOptions()) ?? 0
            return (Keymap(layers: matrix, encoders: encoders), options)
        }

        return KeyboardState(
            definition: definition,
            keycodes: keycodes,
            keymap: keymap,
            viaProtocol: info.0,
            vialProtocol: info.1,
            vialUID: info.2,
            layoutOptions: definition.selectedOptions(packed: packedOptions)
        )
    }

    public func setKeycode(_ code: UInt16, layer: Int, slot: KeySlot) async throws {
        let isVial = device.isVial
        try await perform { client in
            switch slot {
            case let .matrix(row, col):
                try client.setKeycode(code, layer: layer, row: row, col: col)
            case let .encoder(index, clockwise):
                if isVial {
                    try client.vialSetEncoder(code, layer: layer, index: index, clockwise: clockwise)
                } else {
                    try client.setEncoder(code, layer: layer, index: index, clockwise: clockwise)
                }
            }
        }
    }

    /// Writes only the keys that differ; reports progress (done, total).
    public func write(_ target: Keymap, over current: Keymap, progress: (@Sendable (Int, Int) -> Void)? = nil) async throws -> Int {
        let changes = target.differences(from: current)
        let isVial = device.isVial
        try await perform { client in
            for (index, change) in changes.enumerated() {
                switch change.slot {
                case let .matrix(row, col):
                    try client.setKeycode(change.code, layer: change.layer, row: row, col: col)
                case let .encoder(encoder, clockwise):
                    if isVial {
                        try client.vialSetEncoder(change.code, layer: change.layer, index: encoder, clockwise: clockwise)
                    } else {
                        try client.setEncoder(change.code, layer: change.layer, index: encoder, clockwise: clockwise)
                    }
                }
                progress?(index + 1, changes.count)
            }
        }
        return changes.count
    }

    public func vialUnlockStatus() async throws -> VialUnlockStatus {
        try await perform { try $0.vialUnlockStatus() }
    }

    public func vialUnlockStart() async throws {
        try await perform { try $0.vialUnlockStart() }
    }

    public func vialUnlockPoll() async throws -> (unlocked: Bool, counter: Int) {
        try await perform { try $0.vialUnlockPoll() }
    }

    public func vialLock() async throws {
        try await perform { try $0.vialLock() }
    }
}
