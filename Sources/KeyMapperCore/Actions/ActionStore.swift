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
