// Adapted from AMG65 Studio's UsageEngine Main.swift; see THIRD_PARTY_NOTICES.md.
import Foundation

/// Fetches AI tool quotas with the user's existing sign-ins. Runs only inside the bundled
/// `keymapper-usage` helper: credential reads switch Keychain UI off for the whole process,
/// so they must never run inside the app itself.
public enum UsageEngine {
    public static let providers = ["claude", "cursor", "codex"]

    /// `--providers claude,codex` (or `--provider claude`, or nothing for all) prints the quota JSON;
    /// `--authorize-keychain <provider>` asks macOS for Keychain access once, after a user's click.
    public static func run(arguments: [String]) async -> Data {
        if arguments.count == 2, arguments[0] == "--authorize-keychain" {
            return Data((CredentialReader.requestKeychainAccess(provider: arguments[1]).rawValue + "\n").utf8)
        }
        guard let selected = selection(arguments) else { return encode([.failure("unknown", code: "invalid_arguments")]) }
        let now = Date()
        let context = FetchContext(http: UsageHTTPClient(), home: FileManager.default.homeDirectoryForCurrentUser,
                                   environment: ProcessInfo.processInfo.environment, now: now,
                                   deadline: now.addingTimeInterval(18))
        enum Event: Sendable { case result(ProviderResult), deadline }
        let results = await withTaskGroup(of: Event.self, returning: [ProviderResult].self) { group in
            for provider in selected {
                group.addTask {
                    switch provider {
                    case "codex": return .result(await CodexProvider.fetch(context: context))
                    case "claude": return .result(await ClaudeProvider.fetch(context: context))
                    default: return .result(await CursorProvider.fetch(context: context))
                    }
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 18_000_000_000)
                return .deadline
            }
            var results = [String: ProviderResult]()
            while let event = await group.next() {
                if case let .result(result) = event { results[result.provider] = result } else { break }
                if results.count == selected.count { break }
            }
            group.cancelAll()
            return selected.map { results[$0] ?? .failure($0, code: "timeout") }
        }
        return encode(results)
    }

    /// Validated provider list; nil for anything unexpected.
    static func selection(_ arguments: [String]) -> [String]? {
        if arguments.isEmpty { return providers }
        guard arguments.count == 2, ["--provider", "--providers"].contains(arguments[0]) else { return nil }
        let names = arguments[1].split(separator: ",").map(String.init)
        if names == ["all"] { return providers }
        guard !names.isEmpty, names.allSatisfy(providers.contains), Set(names).count == names.count else { return nil }
        return providers.filter(names.contains)
    }

    static func encode(_ results: [ProviderResult]) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard var data = try? encoder.encode(results) else { return Data("[]\n".utf8) }
        data.append(10)
        return data
    }
}
