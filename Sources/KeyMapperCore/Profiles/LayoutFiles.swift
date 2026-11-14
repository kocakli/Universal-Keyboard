import Foundation

public enum LayoutFileError: LocalizedError {
    case unsupported
    case missingCols

    public var errorDescription: String? {
        switch self {
        case .unsupported: return "Dosya tanınmadı. Vial (.vil), VIA (.json) veya KeyMapper profili bekleniyor."
        case .missingCols: return "VIA dosyasını açmak için klavyenin matris bilgisi gerekiyor."
        }
    }
}

/// Reads and writes layout files from other tools: Vial `.vil`, VIA `.json` and KeyMapper profiles.
public enum LayoutFiles {
    /// Imports a layout file as a profile for `deviceKey`. `cols` is needed for VIA files (flat layers).
    public static func importProfile(from url: URL, deviceKey: String, cols: Int?) throws -> LayoutProfile {
        let data = try Data(contentsOf: url)
        let name = url.deletingPathExtension().lastPathComponent

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if var profile = try? decoder.decode(LayoutProfile.self, from: data) {
            profile.id = UUID()
            profile.deviceKey = deviceKey
            return profile
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw LayoutFileError.unsupported }

        // Vial: {"version": 1, "uid": ..., "layout": [layer][row][col], "encoder_layout": [layer][enc][2]}
        if let layout = json["layout"] as? [[[Any]]] {
            let layers = layout.map { layer in layer.map { row in row.map(cellString) } }
            let encoders = (json["encoder_layout"] as? [[[Any]]])?.map { layer in layer.map { pair in pair.map(cellString) } }
            return LayoutProfile(name: name, deviceKey: deviceKey, kind: .firmware, note: "Vial dosyasından", layers: layers, encoders: encoders)
        }

        // VIA: {"name": ..., "vendorProductId": ..., "layers": [[flat keycodes]], "encoders": [[[ccw, cw]]]}
        if let flatLayers = json["layers"] as? [[Any]] {
            guard let cols, cols > 0 else { throw LayoutFileError.missingCols }
            let layers: [[[String?]]] = flatLayers.map { flat in
                stride(from: 0, to: flat.count, by: cols).map { start in
                    flat[start..<min(start + cols, flat.count)].map(cellString)
                }
            }
            let encoders = (json["encoders"] as? [[[Any]]])?.map { layer in layer.map { pair in pair.map(cellString) } }
            return LayoutProfile(name: (json["name"] as? String) ?? name, deviceKey: deviceKey, kind: .firmware,
                                 note: "VIA dosyasından", layers: layers, encoders: encoders)
        }
        throw LayoutFileError.unsupported
    }

    private static func cellString(_ value: Any) -> String? {
        if let text = value as? String { return text == "-1" ? nil : text }
        if let number = value as? NSNumber {
            let int = number.intValue
            return int < 0 ? nil : String(format: "0x%04X", int)
        }
        return nil
    }

    /// Vial `.vil` (layout part only, macros / combos are left untouched on import in Vial).
    public static func vilData(keymap: Keymap, keycodes: KeycodeSet, uid: UInt64?, viaProtocol: Int, vialProtocol: Int?) throws -> Data {
        var json: [String: Any] = [
            "version": 1,
            "layout": keymap.layers.map { layer in layer.map { row in row.map { keycodes.name(for: $0, style: .vial) } } },
            "via_protocol": viaProtocol,
        ]
        if let uid { json["uid"] = NSNumber(value: uid) }
        if let vialProtocol { json["vial_protocol"] = vialProtocol }
        if !keymap.encoders.isEmpty {
            json["encoder_layout"] = keymap.encoders.map { layer in
                layer.map { [keycodes.name(for: $0.ccw, style: .vial), keycodes.name(for: $0.cw, style: .vial)] }
            }
        }
        return try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
    }

    /// VIA "Save + Load" layout JSON.
    public static func viaData(keymap: Keymap, keycodes: KeycodeSet, name: String, vendorProductID: Int) throws -> Data {
        var json: [String: Any] = [
            "name": name,
            "vendorProductId": vendorProductID,
            "layers": keymap.layers.map { layer in layer.flatMap { row in row.map { keycodes.name(for: $0) } } },
        ]
        if !keymap.encoders.isEmpty {
            json["encoders"] = keymap.encoders.map { layer in layer.map { [keycodes.name(for: $0.ccw), keycodes.name(for: $0.cw)] } }
        }
        return try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
    }

    public static func profileData(_ profile: LayoutProfile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(profile)
    }
}
