import Foundation

/// A firmware build offered by a vendor.
public struct FirmwareRelease: Codable, Hashable, Sendable {
    public var version: String
    public var date: String?
    public var downloadURL: URL?
    public var notes: String?

    public init(version: String, date: String? = nil, downloadURL: URL? = nil, notes: String? = nil) {
        self.version = version
        self.date = date
        self.downloadURL = downloadURL
        self.notes = notes
    }
}

/// What we know about a keyboard's firmware.
public struct FirmwareStatus: Sendable, Equatable {
    public var current: String?
    public var latest: FirmwareRelease?
    /// Where the user updates (vendor tool).
    public var updatePage: URL?

    public init(current: String?, latest: FirmwareRelease?, updatePage: URL?) {
        self.current = current
        self.latest = latest
        self.updatePage = updatePage
    }

    public var isUpdateAvailable: Bool {
        guard let current, let latest else { return false }
        return KeychronLauncher.compareVersions(latest.version, current) == .orderedDescending
    }
}

/// Keychron Launcher's (undocumented) public endpoints: product info, keyboard definitions and
/// firmware releases, keyed by VIA's vendorProductId ((vid << 16) | pid, decimal).
/// Best effort: everything degrades gracefully when the service changes.
public enum KeychronLauncher {
    public static let vendorID = 0x3434
    public static let site = URL(string: "https://launcher.keychron.com")!
    static let api = URL(string: "https://launcher.keychron.com/vapi/v2/")!
    static let files = URL(string: "https://launcher.keychron.com/static/")!

    public struct Product: Sendable {
        public var name: String
        /// 0 keyboard, 1 mouse, 2 receiver, 3 trackball.
        public var category: Int
        public var latest: FirmwareRelease?
    }

    // MARK: Network

    static func get(_ url: URL, session: URLSession) async -> Data? {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("KeyMapper/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    public static func product(vendorProductID: Int, session: URLSession = .shared) async -> Product? {
        guard let data = await get(api.appendingPathComponent("product/\(vendorProductID)"), session: session) else { return nil }
        return parseProduct(data)
    }

    /// Definition file candidates in the order Keychron Launcher tries them.
    static func definitionFiles(viaProtocol: Int, variant: Int) -> [String] {
        let primary = viaProtocol >= 11 ? "v3" : "v2"
        var names: [String] = []
        if (1...100).contains(variant) { names.append("\(primary)-\(variant).json") }
        names.append("\(primary).json")
        names.append(primary == "v3" ? "v2.json" : "v3.json")
        return names
    }

    public static func definitionData(vendorProductID: Int, viaProtocol: Int, variant: Int,
                                      session: URLSession = .shared) async -> Data? {
        for name in definitionFiles(viaProtocol: viaProtocol, variant: variant) {
            let url = files.appendingPathComponent("device/\(vendorProductID)/json/\(name)")
            if let data = await get(url, session: session),
               (try? JSONSerialization.jsonObject(with: data)) is [String: Any] {
                return data
            }
        }
        return nil
    }

    // MARK: Parsing

    static func parseProduct(_ data: Data) -> Product? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = root["data"] as? [String: Any],
              let product = payload["product"] as? [String: Any] else { return nil }
        let category = (payload["category"] as? [String: Any])?["type"] as? Int ?? 0
        var latest: FirmwareRelease?
        if let firmware = payload["firmware"] as? [String: Any], let lasted = firmware["lasted"] as? [String: Any],
           let version = lasted["version"] as? String {
            latest = FirmwareRelease(
                version: version,
                date: (lasted["updateTime"] as? String).map { String($0.prefix(10)) },
                downloadURL: (lasted["path"] as? String).flatMap(fileURL(for:)),
                notes: releaseNotes(lasted["languageDesc"] as? [[String: Any]] ?? [])
            )
        }
        return Product(name: product["name"] as? String ?? "Keychron", category: category, latest: latest)
    }

    static func fileURL(for path: String) -> URL? {
        if path.hasPrefix("http") { return URL(string: path) }
        let trimmed = path.hasPrefix("upload/") ? String(path.dropFirst("upload/".count)) : path
        return URL(string: trimmed, relativeTo: files)?.absoluteURL
    }

    /// Picks notes in the app language, then English.
    static func releaseNotes(_ entries: [[String: Any]]) -> String? {
        let byLanguage = Dictionary(entries.compactMap { entry -> (String, String)? in
            guard let language = entry["language"] as? String, let text = entry["description"] as? String else { return nil }
            return (language, text)
        }, uniquingKeysWith: { a, _ in a })
        return byLanguage[L10n.current.releaseNotesTag] ?? byLanguage["en-US"] ?? byLanguage.values.first
    }

    /// The button layout of a Keychron trackball or mouse, from a definition the cable editor already downloaded
    /// (never from the network): nil for keyboards and for devices never opened by cable. Over Bluetooth these devices
    /// have no raw HID, so this is the only way to draw them as themselves.
    public static func cachedPointingDevice(vendorID: Int, productID: Int) -> KeyboardDefinition? {
        guard vendorID == Self.vendorID else { return nil }
        let url = AppPaths.viaCache.appendingPathComponent("keychron_\((vendorID << 16) | productID)_0.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return pointingDevice(data, vendorID: vendorID, productID: productID)
    }

    /// `data` parsed as a pointing device's button layout; nil when it is a keyboard (it has a matrix).
    static func pointingDevice(_ data: Data, vendorID: Int, productID: Int) -> KeyboardDefinition? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], json["matrix"] == nil else { return nil }
        return try? pointingDeviceDefinition(json, vendorID: vendorID, productID: productID)
    }

    /// Keyboards come as VIA's compiled format; trackballs / mice as a button list placed on a product image.
    public static func parseDefinition(_ data: Data, vendorID: Int, productID: Int) throws -> KeyboardDefinition {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw DefinitionError.invalidJSON }
        if json["matrix"] != nil {
            var definition = try DefinitionParser.parse(data, source: .vendor)
            definition.vendorID = vendorID
            definition.productID = productID
            return definition
        }
        return try pointingDeviceDefinition(json, vendorID: vendorID, productID: productID)
    }

    /// Buttons sit at percentages of a product image. The Nape Pro is drawn as itself (`NapeProLayout`); any other
    /// device keeps the buttons' arrangement, at least 1.2u apart.
    static func pointingDeviceDefinition(_ json: [String: Any], vendorID: Int, productID: Int) throws -> KeyboardDefinition {
        guard let layouts = json["keys"] as? [String: Any],
              let entries = (layouts["0"] ?? layouts.values.first) as? [[String: Any]], !entries.isEmpty else {
            throw DefinitionError.missingField("keys")
        }
        let custom: [CustomKeycode] = (json["customKeycodes"] as? [[String: Any]] ?? []).compactMap { item in
            guard let name = item["name"] as? String else { return nil }
            return CustomKeycode(name: name, title: item["title"] as? String, shortName: item["shortName"] as? String)
        }
        func definition(_ keys: [LayoutKey], body: DeviceBody? = nil) -> KeyboardDefinition {
            // Keychron Launcher reads 7 keycodes per layer for these devices; keep at least that many columns.
            let maxCol = keys.filter { !$0.isEncoder }.map(\.col).max() ?? 0
            return KeyboardDefinition(name: json["name"] as? String ?? "Keychron", vendorID: vendorID, productID: productID,
                                      rows: 1, cols: max(maxCol + 1, 7), keys: keys, customKeycodes: custom, source: .vendor,
                                      deviceBody: body)
        }
        if let keys = NapeProLayout.keys(entries, maxColumns: VIAClient.maxMatrix) {
            return definition(keys, body: NapeProLayout.body)
        }

        struct Point { let x: Double; let y: Double; let col: Int?; let knob: Bool; let name: String? }
        let points: [Point] = entries.compactMap { entry in
            guard let x = DefinitionParser.double(entry["x"]), let y = DefinitionParser.double(entry["y"]) else { return nil }
            let isKnob = entry["labels"] != nil
            return Point(x: x, y: y, col: DefinitionParser.int(entry["col"]), knob: isKnob,
                         name: (entry["id"] as? String)?.uppercased())
        }
        // Horizontal: keep proportions, closest buttons 1.25u apart. Vertical: buttons at similar
        // heights form rows 1.4u apart, so the empty area around the ball does not shrink the keys.
        var minDX = Double.infinity
        for (i, a) in points.enumerated() {
            for b in points[(i + 1)...] where abs(a.x - b.x) > 2 { minDX = min(minDX, abs(a.x - b.x)) }
        }
        let scale = minDX.isFinite ? 1.25 / minDX : 0.12
        let minX = points.map(\.x).min() ?? 0
        var levels: [Double] = []
        for y in points.map(\.y).sorted() where levels.last.map({ y - $0 > 8 }) ?? true { levels.append(y) }
        func row(for y: Double) -> Double {
            let index = levels.lastIndex { y >= $0 - 0.001 } ?? 0
            return Double(index) * 1.4
        }

        var keys: [LayoutKey] = []
        for point in points {
            let x = (point.x - minX) * scale, y = row(for: point.y)
            if point.knob {
                keys.append(LayoutKey(row: -1, col: -1, x: x - 0.55, y: y, encoderIndex: 0, encoderDirection: 0))
                keys.append(LayoutKey(row: -1, col: -1, x: x + 0.55, y: y, encoderIndex: 0, encoderDirection: 1))
            } else if let col = point.col, (0..<VIAClient.maxMatrix).contains(col) {
                keys.append(LayoutKey(row: 0, col: col, x: x, y: y, name: point.name))
            }
        }
        return definition(keys)
    }

    // MARK: Versions

    /// "v1.2.1 2025-06-17-10:09:52" → "1.2.1".
    public static func normalizeVersion(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let cut = text.firstIndex(where: { $0 == " " || $0 == "-" }) { text = String(text[..<cut]) }
        if text.lowercased().hasPrefix("v") { text.removeFirst() }
        return text
    }

    public static func compareVersions(_ a: String, _ b: String) -> ComparisonResult {
        let left = normalizeVersion(a).split(separator: ".").map { Int($0) ?? 0 }
        let right = normalizeVersion(b).split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(left.count, right.count) {
            let l = index < left.count ? left[index] : 0, r = index < right.count ? right[index] : 0
            if l != r { return l < r ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }
}
