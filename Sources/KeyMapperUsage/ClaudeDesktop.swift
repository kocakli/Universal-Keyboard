import Foundation
import os

/// The Claude desktop app's own sign-in: an OAuth token cache in its `config.json`, encrypted with Electron's
/// safeStorage (the "Claude Safe Storage" Keychain password). Read-only: the access token is used in memory for the
/// usage request, never saved, and never renewed; the desktop app renews it while it runs.
enum ClaudeDesktop {
    static let service = "Claude Safe Storage"
    static let account = "Claude Key"
    /// Newest format first.
    static let cacheKeys = ["oauth:tokenCacheV2", "oauth:tokenCache"]
    static let log = Logger(subsystem: "dev.keymapper.KeyMapper", category: "usage")

    static func configURL(home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support/Claude/config.json")
    }

    /// The encrypted token caches in the app's config, newest format first; empty when it isn't signed in.
    static func encryptedCaches(config: Data) -> [Data] {
        guard let root = try? JSONValue.object(config) else { return [] }
        return cacheKeys.compactMap { key in
            guard let text = JSONValue.text(root[key], maximum: 262_144), let data = Data(base64Encoded: text),
                  data.starts(with: Data("v10".utf8)) else { return nil }
            return data
        }
    }

    /// Whether the desktop app has a sign-in on this Mac (nothing is decrypted to tell).
    static func isSignedIn(home: URL) -> Bool {
        guard let config = try? CredentialReader.file(configURL(home: home)) else { return false }
        return !encryptedCaches(config: config).isEmpty
    }

    /// A usable access token from the caches. `password` reads the Keychain without any dialog.
    static func credentials(caches: [Data], now: Date, password: () throws -> Data?) throws -> ClaudeProvider.Credentials {
        guard !caches.isEmpty else { throw UsageFailure(code: "auth_required") }
        guard let secret = try password() else {
            log.error("Claude desktop sign-in: no \(service, privacy: .public) item in the Keychain")
            throw UsageFailure(code: "auth_required")
        }
        guard secret.count <= 4096, let text = String(data: secret, encoding: .utf8) else {
            log.error("Claude desktop sign-in: the \(service, privacy: .public) password isn't text")
            throw UsageFailure(code: "credentials_unreadable")
        }
        var failures: [String] = []
        for (index, cache) in caches.enumerated() {
            guard let plain = SafeStorage.decrypt(cache, password: text, maximumBytes: 262_144) else {
                log.error("Claude desktop sign-in: cache \(index) (\(cache.count) bytes) didn't decrypt")
                failures.append("credentials_unreadable")
                continue
            }
            do {
                let token = try accessToken(in: plain, now: now)
                return ClaudeProvider.Credentials(
                    token: token, fingerprint: AccountFingerprint.make(provider: "claude", identity: "credential:" + token),
                    source: "desktop app")
            } catch let failure as UsageFailure {
                failures.append(failure.code)
            }
        }
        for code in ["relogin_required", "auth_required", "credentials_unreadable"] where failures.contains(code) {
            throw UsageFailure(code: code)
        }
        throw UsageFailure(code: "credentials_unreadable")
    }

    // MARK: Token cache

    private struct Candidate {
        let token: String
        let expiresAt: Date?
        let scopes: Set<String>?
    }

    /// The freshest access token with the `user:profile` scope the usage endpoint needs. The cache's layout isn't
    /// documented, so any object holding a Claude OAuth access token (`sk-ant-oat…`) counts, with its expiry and
    /// scopes taken from its own fields or, for scopes, from the key it is filed under.
    static func accessToken(in plain: Data, now: Date) throws -> String {
        let root: Any
        if let json = try? JSONSerialization.jsonObject(with: plain, options: [.fragmentsAllowed]) {
            root = json
        } else if let text = String(data: plain, encoding: .utf8) {
            root = text.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            throw UsageFailure(code: "credentials_unreadable")
        }
        var candidates: [Candidate] = []
        collect(root, inheritedScopes: nil, depth: 0, into: &candidates)
        guard !candidates.isEmpty else {
            log.error("Claude desktop sign-in has no access token where expected; layout: \(shape(root), privacy: .public)")
            throw UsageFailure(code: "credentials_unreadable")
        }
        let scoped = candidates.filter { $0.scopes.map { $0.contains("user:profile") } ?? true }
        guard !scoped.isEmpty else {
            let scopes = candidates.map { ($0.scopes ?? []).sorted().joined(separator: " ") }.joined(separator: " | ")
            log.error("Claude desktop sign-in: no token with user:profile; scopes: \(scopes, privacy: .public); layout: \(shape(root), privacy: .public)")
            throw UsageFailure(code: "auth_required")
        }
        let fresh = scoped.filter { $0.expiresAt.map { $0.timeIntervalSince(now) > 60 } ?? true }
        guard let best = fresh.max(by: { ($0.expiresAt ?? .distantPast) < ($1.expiresAt ?? .distantPast) }) else {
            let expiries = scoped.compactMap(\.expiresAt).map(UsageDates.iso).joined(separator: ", ")
            log.notice("Claude desktop sign-in: every token has expired (\(expiries, privacy: .public))")
            throw UsageFailure(code: "relogin_required")
        }
        return best.token
    }

    static func isAccessToken(_ value: Any?) -> String? {
        guard let text = JSONValue.text(value, maximum: 32_768), text.hasPrefix("sk-ant-oat") else { return nil }
        return text
    }

    private static func collect(_ value: Any, inheritedScopes: Set<String>?, depth: Int, into candidates: inout [Candidate]) {
        guard depth < 8 else { return }
        if let token = isAccessToken(value) {
            candidates.append(Candidate(token: token, expiresAt: nil, scopes: inheritedScopes))
        } else if let object = value as? [String: Any] {
            let scopes = scopes(object["scopes"] ?? object["scope"]) ?? inheritedScopes
            let token = ["accessToken", "access_token", "token"].lazy.compactMap { isAccessToken(object[$0]) }.first
                ?? object.keys.sorted().lazy.compactMap { isAccessToken(object[$0]) }.first
            if let token {
                let expiry = ["expiresAt", "expires_at", "expiry", "expires", "expirationTime"].lazy
                    .compactMap { date(object[$0]) }.first
                candidates.append(Candidate(token: token, expiresAt: expiry, scopes: scopes))
            }
            for (key, child) in object where child is [String: Any] || child is [Any] {
                // Caches are often filed under their scope list ("user:inference user:profile …").
                let keyScopes = key.contains("user:") ? Set(key.split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)) : nil
                collect(child, inheritedScopes: keyScopes ?? scopes, depth: depth + 1, into: &candidates)
            }
        } else if let array = value as? [Any] {
            for child in array.prefix(64) {
                collect(child, inheritedScopes: inheritedScopes, depth: depth + 1, into: &candidates)
            }
        }
    }

    private static func scopes(_ value: Any?) -> Set<String>? {
        if let list = value as? [String] { return Set(list) }
        if let text = value as? String { return Set(text.split(separator: " ").map(String.init)) }
        return nil
    }

    /// Milliseconds or seconds since 1970, or an ISO 8601 date.
    static func date(_ value: Any?) -> Date? {
        if let number = JSONValue.number(value) {
            if number > 100_000_000_000 { return Date(timeIntervalSince1970: number / 1000) }
            if number > 1_000_000_000 { return Date(timeIntervalSince1970: number) }
            return nil
        }
        if let text = value as? String {
            if let number = Double(text) { return date(NSNumber(value: number)) }
            return UsageDates.date(text)
        }
        return nil
    }

    /// The cache's structure with every value replaced by its kind, for the log when nothing usable is found.
    static func shape(_ value: Any, depth: Int = 0) -> String {
        guard depth < 6 else { return "…" }
        if let object = value as? [String: Any] {
            let fields = object.keys.sorted().prefix(24).map { key -> String in
                let name = key.hasPrefix("sk-") ? "<secret>" : key.contains("@") ? "<email>"
                    : UUID(uuidString: key) != nil ? "<uuid>" : String(key.prefix(60))
                return name + ": " + shape(object[key]!, depth: depth + 1)
            }
            return "{" + fields.joined(separator: ", ") + "}"
        }
        if let array = value as? [Any] {
            return "[" + (array.first.map { shape($0, depth: depth + 1) } ?? "") + (array.count > 1 ? ", … ×\(array.count)" : "") + "]"
        }
        if let text = value as? String {
            if text.hasPrefix("sk-ant-oat") { return "<access token>" }
            if text.hasPrefix("sk-ant-ort") { return "<refresh token>" }
            return "<string \(text.count)>"
        }
        if JSONValue.number(value) != nil { return "<number>" }
        if value is NSNumber { return "<bool>" }
        return "<null>"
    }
}
