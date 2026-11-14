import Foundation

public enum DefinitionError: LocalizedError {
    case invalidJSON
    case missingField(String)
    case invalidMatrix(rows: Int, cols: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidJSON: return L("Tanım dosyası okunamadı (geçersiz JSON).")
        case let .missingField(field): return L("Tanım dosyasında '%@' alanı yok.", "\(field)")
        case let .invalidMatrix(rows, cols): return L("Tanımdaki matris boyutu geçersiz (%@x%@).", "\(rows)", "\(cols)")
        }
    }
}

/// Parses VIA / Vial keyboard definitions: raw KLE (`layouts.keymap`) or
/// VIA's precompiled format (`layouts.keys` + `layouts.optionKeys`).
public enum DefinitionParser {
    public static func parse(_ data: Data, source: DefinitionSource) throws -> KeyboardDefinition {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw DefinitionError.invalidJSON }
        guard let matrix = json["matrix"] as? [String: Any],
              let rows = int(matrix["rows"]), let cols = int(matrix["cols"]) else { throw DefinitionError.missingField("matrix") }
        guard (1...VIAClient.maxMatrix).contains(rows), (1...VIAClient.maxMatrix).contains(cols) else {
            throw DefinitionError.invalidMatrix(rows: rows, cols: cols)
        }
        guard let layouts = json["layouts"] as? [String: Any] else { throw DefinitionError.missingField("layouts") }

        var vendorID = int(json["vendorId"]) ?? 0
        var productID = int(json["productId"]) ?? 0
        if let vpid = int(json["vendorProductId"]) {
            vendorID = vpid >> 16
            productID = vpid & 0xFFFF
        }

        var keys: [LayoutKey]
        if let keymap = layouts["keymap"] as? [Any] {
            keys = parseKLE(keymap)
        } else if let compiled = layouts["keys"] as? [[String: Any]] {
            keys = compiled.compactMap { compiledKey($0) }
            if let optionKeys = layouts["optionKeys"] as? [String: Any] {
                for (groupKey, choices) in optionKeys {
                    guard let group = Int(groupKey), let choices = choices as? [String: Any] else { continue }
                    for (choiceKey, list) in choices {
                        guard let choice = Int(choiceKey), let list = list as? [[String: Any]] else { continue }
                        keys += list.compactMap { compiledKey($0, group: group, choice: choice) }
                    }
                }
            }
        } else {
            throw DefinitionError.missingField("layouts.keymap")
        }

        let options: [LayoutOption] = (layouts["labels"] as? [Any] ?? []).compactMap { label in
            if let title = label as? String { return LayoutOption(title: title, choices: []) }
            if let list = label as? [String], let title = list.first { return LayoutOption(title: title, choices: Array(list.dropFirst())) }
            return nil
        }

        let custom: [CustomKeycode] = (json["customKeycodes"] as? [[String: Any]] ?? []).compactMap { item in
            guard let name = item["name"] as? String else { return nil }
            return CustomKeycode(name: name, title: item["title"] as? String, shortName: item["shortName"] as? String)
        }

        // Drop keys that point outside the matrix or use absurd encoder indices.
        keys = keys.filter { key in
            if let index = key.encoderIndex {
                return (0..<VIAClient.maxEncoders).contains(index) && (0...1).contains(key.encoderDirection ?? -1)
            }
            if let knob = key.knobIndex, !(0..<VIAClient.maxEncoders).contains(knob) { return false }
            return (0..<rows).contains(key.row) && (0..<cols).contains(key.col)
        }

        return KeyboardDefinition(
            name: json["name"] as? String ?? L("Klavye"),
            vendorID: vendorID,
            productID: productID,
            rows: rows,
            cols: cols,
            keys: keys,
            layoutOptions: options,
            customKeycodes: custom,
            source: source,
            lighting: LightingDefinition.capabilities(from: json)
        )
    }

    // MARK: KLE

    /// kle-serial legend reordering, indexed by alignment flags.
    private static let labelMap: [[Int]] = [
        [0, 6, 2, 8, 9, 11, 3, 5, 1, 4, 7, 10],
        [1, 7, -1, -1, 9, 11, 4, -1, -1, -1, -1, 10],
        [3, -1, 5, -1, 9, 11, -1, -1, 4, -1, -1, 10],
        [4, -1, -1, -1, 9, 11, -1, -1, -1, -1, -1, 10],
        [0, 6, 2, 8, 10, -1, 3, 5, 1, 4, 7, -1],
        [1, 7, -1, -1, 10, -1, 4, -1, -1, -1, -1, -1],
        [3, -1, 5, -1, 10, -1, -1, -1, 4, -1, -1, -1],
        [4, -1, -1, -1, 10, -1, -1, -1, -1, -1, -1, -1],
    ]

    static func reorderLabels(_ raw: [String], align: Int) -> [String] {
        var labels = [String](repeating: "", count: 12)
        let map = labelMap[max(0, min(7, align))]
        for (index, text) in raw.prefix(12).enumerated() where !text.isEmpty {
            let position = map[index]
            if position >= 0 { labels[position] = text }
        }
        return labels
    }

    /// Port of kle-serial's deserializer, keeping what a keymap editor needs.
    public static func parseKLE(_ rows: [Any]) -> [LayoutKey] {
        var keys: [LayoutKey] = []
        var x = 0.0, y = 0.0, w = 1.0, h = 1.0
        var r = 0.0, rx = 0.0, ry = 0.0
        var clusterX = 0.0, clusterY = 0.0
        var align = 4
        var decal = false
        var color: String?

        for rowItem in rows {
            guard let row = rowItem as? [Any] else { continue } // keyboard metadata object
            for item in row {
                if let legend = item as? String {
                    let labels = reorderLabels(legend.components(separatedBy: "\n"), align: align)
                    if !decal, let key = makeKey(labels: labels, x: x, y: y, w: w, h: h, r: r, rx: rx, ry: ry, color: color) {
                        keys.append(key)
                    }
                    x += w
                    w = 1; h = 1
                    decal = false
                } else if let props = item as? [String: Any] {
                    if let value = double(props["r"]) { r = value }
                    if let value = double(props["rx"]) { rx = value; clusterX = value; x = clusterX; y = clusterY }
                    if let value = double(props["ry"]) { ry = value; clusterY = value; x = clusterX; y = clusterY }
                    if let value = int(props["a"]) { align = value }
                    if let value = double(props["x"]) { x += value }
                    if let value = double(props["y"]) { y += value }
                    if let value = double(props["w"]) { w = value }
                    if let value = double(props["h"]) { h = value }
                    if let value = props["d"] as? Bool { decal = value }
                    if let value = props["c"] as? String { color = value }
                }
            }
            y += 1
            x = rx
        }
        return keys
    }

    private static func makeKey(labels: [String], x: Double, y: Double, w: Double, h: Double,
                                r: Double, rx: Double, ry: Double, color: String?) -> LayoutKey? {
        guard let (first, second) = pair(labels[0]) else { return nil }
        var key = LayoutKey(row: first, col: second, x: x, y: y, w: w, h: h, r: r, rx: rx, ry: ry, color: color)
        if labels[4].lowercased() == "e" {
            key.row = -1
            key.col = -1
            key.encoderIndex = first
            key.encoderDirection = second
        }
        if let (group, choice) = pair(labels[8]) {
            key.optionGroup = group
            key.optionChoice = choice
        }
        return key
    }

    private static func compiledKey(_ dict: [String: Any], group: Int? = nil, choice: Int? = nil) -> LayoutKey? {
        guard let row = int(dict["row"]), let col = int(dict["col"]) else { return nil }
        if (dict["d"] as? Bool) == true { return nil }
        return LayoutKey(
            row: row, col: col,
            x: double(dict["x"]) ?? 0, y: double(dict["y"]) ?? 0,
            w: double(dict["w"]) ?? 1, h: double(dict["h"]) ?? 1,
            r: double(dict["r"]) ?? 0, rx: double(dict["rx"]) ?? 0, ry: double(dict["ry"]) ?? 0,
            knobIndex: int(dict["ei"]),
            optionGroup: group, optionChoice: choice,
            color: dict["color"] as? String
        )
    }

    // MARK: Helpers

    private static func pair(_ text: String) -> (Int, Int)? {
        let parts = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let a = Int(parts[0]), let b = Int(parts[1]) else { return nil }
        return (a, b)
    }

    static func int(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let text = value as? String { return KeycodeSet.parseNumber(text) }
        return nil
    }

    static func double(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String { return Double(text) }
        return nil
    }
}
