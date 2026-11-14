import Foundation

/// Persists action bindings in `~/Library/Application Support/KeyMapper/actions.json`.
public final class ActionStore: @unchecked Sendable {
    public static let shared = ActionStore()

    private let url: URL
    private let lock = NSLock()

    public init(url: URL = AppPaths.root.appendingPathComponent("actions.json")) {
        self.url = url
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    public func load() -> [ActionBinding] {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([ActionBinding].self, from: data)) ?? []
    }

    public func save(_ bindings: [ActionBinding]) throws {
        lock.lock(); defer { lock.unlock() }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(bindings).write(to: url, options: .atomic)
    }

    /// The first trigger key no binding uses yet.
    public static func nextFreeTrigger(in bindings: [ActionBinding]) -> TriggerKey? {
        let used = Set(bindings.map(\.trigger))
        return TriggerKey.all.first { !used.contains($0.combo) }
    }
}

/// Ready made per-app shortcuts, in the spirit of Logitech Options+ app-specific presets.
public enum ActionPresets {
    public struct AppPreset: Identifiable, Sendable {
        public let bundleID: String
        public let appName: String
        public let shortcuts: [(title: String, combo: KeyCombo)]
        public var id: String { bundleID }
    }

    private static func key(_ code: UInt16, _ legend: String, _ mods: KeyCombo.Modifiers) -> KeyCombo {
        KeyCombo(keyCode: code, modifiers: mods, key: legend)
    }

    public static let apps: [AppPreset] = [
        AppPreset(bundleID: "com.apple.Safari", appName: "Safari", shortcuts: [
            ("Yeni sekme", key(0x11, "T", [.command])),
            ("Sekmeyi kapat", key(0x0D, "W", [.command])),
            ("Kapatılan sekmeyi geri aç", key(0x11, "T", [.command, .shift])),
            ("Önceki sekme", key(0x21, "[", [.command, .shift])),
            ("Sonraki sekme", key(0x1E, "]", [.command, .shift])),
        ]),
        AppPreset(bundleID: "com.google.Chrome", appName: "Google Chrome", shortcuts: [
            ("Yeni sekme", key(0x11, "T", [.command])),
            ("Sekmeyi kapat", key(0x0D, "W", [.command])),
            ("Kapatılan sekmeyi geri aç", key(0x11, "T", [.command, .shift])),
            ("Önceki sekme", key(0x21, "[", [.command, .shift])),
            ("Sonraki sekme", key(0x1E, "]", [.command, .shift])),
        ]),
        AppPreset(bundleID: "com.apple.finder", appName: "Finder", shortcuts: [
            ("Yeni klasör", key(0x2D, "N", [.command, .shift])),
            ("Yeni pencere", key(0x2D, "N", [.command])),
            ("Gizli dosyaları göster", key(0x2F, ".", [.command, .shift])),
            ("Bilgi al", key(0x22, "I", [.command])),
        ]),
        AppPreset(bundleID: "com.microsoft.VSCode", appName: "Visual Studio Code", shortcuts: [
            ("Komut paleti", key(0x23, "P", [.command, .shift])),
            ("Dosyaya git", key(0x23, "P", [.command])),
            ("Terminali aç/kapat", key(0x32, "`", [.control])),
            ("Satırı yorum yap", key(0x2C, "/", [.command])),
        ]),
        AppPreset(bundleID: "us.zoom.xos", appName: "zoom.us", shortcuts: [
            ("Mikrofonu aç/kapat", key(0x00, "A", [.command, .shift])),
            ("Kamerayı aç/kapat", key(0x09, "V", [.command, .shift])),
            ("Ekran paylaş", key(0x01, "S", [.command, .shift])),
        ]),
        AppPreset(bundleID: "com.tinyspeck.slackmacgap", appName: "Slack", shortcuts: [
            ("Hızlı geçiş", key(0x28, "K", [.command])),
            ("Okunmamışlar", key(0x00, "A", [.command, .shift])),
            ("Thread'ler", key(0x11, "T", [.command, .shift])),
        ]),
        AppPreset(bundleID: "com.adobe.Photoshop", appName: "Adobe Photoshop", shortcuts: [
            ("Geri al", key(0x06, "Z", [.command])),
            ("Katmanı çoğalt", key(0x26, "J", [.command])),
            ("Serbest dönüştür", key(0x11, "T", [.command])),
            ("Fırça", key(0x0B, "B", [])),
        ]),
    ]

    /// System wide suggestions for the default action.
    public static let system: [(title: String, combo: KeyCombo)] = [
        ("Ekran görüntüsü (alan)", key(0x15, "4", [.command, .shift])),
        ("Spotlight", key(0x31, "Space", [.command])),
        ("Mission Control", key(0x7E, "↑", [.control])),
        ("Masaüstü sola", key(0x7B, "←", [.control])),
        ("Masaüstü sağa", key(0x7C, "→", [.control])),
    ]
}
