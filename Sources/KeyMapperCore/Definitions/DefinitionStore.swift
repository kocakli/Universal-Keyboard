import Foundation

/// Application Support locations.
public enum AppPaths {
    public static var root: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("KeyMapper", isDirectory: true)
    }()

    public static var definitions: URL { directory("Definitions") }
    public static var viaCache: URL { directory("Definitions/via-cache") }
    public static var userDefinitions: URL { directory("Definitions/user") }
    public static var profiles: URL { directory("Profiles") }

    static func directory(_ path: String) -> URL {
        let url = root.appendingPathComponent(path, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

public enum DefinitionLookupError: LocalizedError {
    case notFound(String)

    public var errorDescription: String? {
        switch self {
        case let .notFound(key):
            return L("%@ için VIA tanımı bulunamadı. Üreticinin sitesinden (ör. Keychron) VIA JSON dosyasını indirip \"VIA tanım dosyası yükle…\" ile ekleyin.", "\(key)")
        }
    }
}

/// Finds keyboard definitions for VIA keyboards: user files first, then the
/// local cache, then the public VIA repository (usevia.app).
public final class DefinitionStore: @unchecked Sendable {
    public static let shared = DefinitionStore()

    private let session: URLSession
    private let baseURL = URL(string: "https://usevia.app/definitions")!

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func userDefinitionURL(vendorID: Int, productID: Int) -> URL {
        AppPaths.userDefinitions.appendingPathComponent(String(format: "%04X_%04X.json", vendorID, productID))
    }

    /// Stores a user supplied VIA JSON for a keyboard (validated first).
    @discardableResult
    public func importUserDefinition(from url: URL, vendorID: Int, productID: Int) throws -> KeyboardDefinition {
        let data = try Data(contentsOf: url)
        var definition = try DefinitionParser.parse(data, source: .userFile)
        definition.vendorID = vendorID
        definition.productID = productID
        try data.write(to: userDefinitionURL(vendorID: vendorID, productID: productID), options: .atomic)
        return definition
    }

    public func removeUserDefinition(vendorID: Int, productID: Int) {
        try? FileManager.default.removeItem(at: userDefinitionURL(vendorID: vendorID, productID: productID))
    }

    public func definition(vendorID: Int, productID: Int, viaProtocol: Int = 12, variant: Int = 0) async throws -> KeyboardDefinition {
        let userURL = userDefinitionURL(vendorID: vendorID, productID: productID)
        if let data = try? Data(contentsOf: userURL) {
            return try DefinitionParser.parse(data, source: .userFile)
        }
        let vpid = (vendorID << 16) | productID

        // Keychron publishes definitions (including trackballs / mice) through Keychron Launcher.
        if vendorID == KeychronLauncher.vendorID {
            let cacheURL = AppPaths.viaCache.appendingPathComponent("keychron_\(vpid)_\(variant).json")
            if let data = try? Data(contentsOf: cacheURL),
               let definition = try? KeychronLauncher.parseDefinition(data, vendorID: vendorID, productID: productID) {
                return definition
            }
            if let data = await KeychronLauncher.definitionData(vendorProductID: vpid, viaProtocol: viaProtocol, variant: variant, session: session),
               let definition = try? KeychronLauncher.parseDefinition(data, vendorID: vendorID, productID: productID) {
                try? data.write(to: cacheURL, options: .atomic)
                return definition
            }
        }

        let cacheURL = AppPaths.viaCache.appendingPathComponent("\(vpid).json")
        if let data = try? Data(contentsOf: cacheURL), let definition = try? DefinitionParser.parse(data, source: .viaRepository) {
            return definition
        }
        for version in ["v3", "v2"] {
            let url = baseURL.appendingPathComponent(version).appendingPathComponent("\(vpid).json")
            var request = URLRequest(url: url, timeoutInterval: 15)
            request.setValue("KeyMapper/1.0", forHTTPHeaderField: "User-Agent")
            guard let (data, response) = try? await session.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let definition = try? DefinitionParser.parse(data, source: .viaRepository) else { continue }
            try? data.write(to: cacheURL, options: .atomic)
            return definition
        }
        throw DefinitionLookupError.notFound(String(format: "%04X:%04X", vendorID, productID))
    }
}
