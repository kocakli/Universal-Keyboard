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
    /// Vendor firmware version string when the keyboard reports one (Keychron 0xA1).
    public var firmwareVersion: String?
    /// Keychron Launcher status (family, active layer, radios) for Keychron firmware.
    public var keychron: KeychronStatus?
    /// Lighting systems the keyboard can be controlled through (declared by the definition or found by asking).
    public var lighting: [LightingCapability] = []
    /// VialRGB brightness ceiling (RGB_MATRIX_MAXIMUM_BRIGHTNESS); 255 elsewhere.
    public var vialRGBMaxBrightness = 255

    public var layerCount: Int { keymap.layerCount }
}

public enum SessionError: LocalizedError {
    case notProgrammable
    case locked

    public var errorDescription: String? {
        switch self {
        case .notProgrammable: return L("Bu klavye VIA/Vial raw HID arayüzü sunmuyor.")
        case .locked: return L("Bu tuş (QK_BOOT) için Vial kilidinin açılması gerekiyor.")
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

    /// Calls `handler(defaultLayer, activeLayer)` whenever Keychron firmware pushes a layer change.
    public func observeKeychronLayers(family: KeychronStatus.Family, _ handler: @escaping @Sendable (Int?, Int?) -> Void) {
        client.connection.setUnsolicitedHandler { report in
            guard report.first == KeychronProtocol.layer else { return }
            let layers = KeychronProtocol.layers(reply: report, family: family)
            handler(layers.default, layers.active)
        }
    }

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
        let isKeychron = device.vendorID == KeychronLauncher.vendorID
        let vendorInfo = try await perform { client -> (variant: Int, firmware: String?, status: KeychronStatus?) in
            guard isKeychron else { return (0, nil, nil) }
            let value = (try? client.firmwareValue()) ?? 0
            let firmware = (try? client.keychronFirmwareVersion()) ?? nil
            return (value <= 100 ? Int(value) : 0, firmware, client.keychronStatus())
        }

        let definition: KeyboardDefinition
        if let json = info.3 {
            definition = try DefinitionParser.parse(json, source: .vialFirmware)
        } else {
            definition = try await definitionStore.definition(vendorID: device.vendorID, productID: device.productID,
                                                              viaProtocol: info.0, variant: vendorInfo.variant)
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

        // Lighting is optional: a keyboard that fails these reads still loads.
        let declared = definition.lighting
        let viaProtocol = info.0
        let lighting = (try? await perform { client -> ([LightingCapability], Int) in
            var capabilities = declared
            var vialRGBMax = 255
            if capabilities.isEmpty {
                // Keychron Launcher definitions (and some VIA files) don't declare lighting; ask the firmware.
                capabilities = [LightingKind.rgbMatrix, .rgblight, .backlight, .ledMatrix]
                    .filter { client.lightingResponds($0, viaProtocol: viaProtocol) }
                    .map { LightingCapability(kind: $0) }
            }
            if let index = capabilities.firstIndex(where: { $0.kind == .vialRGB }) {
                if let rgb = try? client.vialRGBInfo(), rgb.version == 1 {
                    vialRGBMax = max(1, rgb.maxBrightness)
                    capabilities[index].effects = rgb.effects.map {
                        LightingEffect(id: $0, name: LightingDefinition.vialRGBEffectNames[$0] ?? L("Efekt %@", "\($0)"))
                    }
                } else {
                    capabilities.remove(at: index)
                }
            }
            return (capabilities, vialRGBMax)
        }) ?? ([], 255)

        return KeyboardState(
            definition: definition,
            keycodes: keycodes,
            keymap: keymap,
            viaProtocol: info.0,
            vialProtocol: info.1,
            vialUID: info.2,
            layoutOptions: definition.selectedOptions(packed: packedOptions),
            firmwareVersion: vendorInfo.firmware,
            keychron: vendorInfo.status,
            lighting: lighting.0,
            vialRGBMaxBrightness: lighting.1
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
