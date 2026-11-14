// Ported from AMG65 Studio's usage_adapter.py; see THIRD_PARTY_NOTICES.md.
import Darwin
import Foundation

/// One quota window as shown to the user: remaining share, never a sum or average of unlike limits.
public struct UsageWindowStatus: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let label: String
    /// 0…100, nil when the provider didn't report a usable value.
    public let remainingPercent: Double?
    public let resetsAt: Date?
    public let stale: Bool
}

/// A provider's quotas as shown in the app and on the keyboard. Holds no credentials or account identity.
public struct ProviderUsage: Codable, Equatable, Sendable, Identifiable {
    public let provider: String
    public let label: String
    /// The first usable primary/secondary window (preferring a fresh one); nil when unknown.
    public let remainingPercent: Double?
    public let remainingLabel: String?
    public let windows: [UsageWindowStatus]
    /// When the provider measured it (not when the app read it).
    public let updatedAt: Date?
    public let stale: Bool
    public let error: String?

    public var id: String { provider }
}

public enum UsageNormalizer {
    public static let labels = ["claude": "Claude", "cursor": "Cursor", "codex": "Codex"]
    /// A measurement older than this (or past its reset) is shown as stale.
    public static let maximumAge: TimeInterval = 15 * 60

    static let errorCodes: Set<String> = [
        "auth_required", "relogin_required", "keychain_locked", "network_error", "rate_limited", "invalid_response",
        "unavailable", "timeout", "helper_unavailable", "fetch_failed", "no_usage", "access_denied",
        "credentials_unreadable", "invalid_credentials",
    ]
    /// Failures that say nothing about the account; the last measurement of the same account may be kept.
    static let retainableErrors: Set<String> = ["network_error", "rate_limited", "timeout"]

    static func errorCode(_ result: ProviderResult?) -> String? {
        guard let code = result?.error?.code else { return nil }
        return errorCodes.contains(code) ? code : "fetch_failed"
    }

    public static func normalize(_ result: ProviderResult?, provider: String, lastKnown: Bool = false,
                                 now: Date, maximumAge: TimeInterval = maximumAge) -> ProviderUsage {
        let label = labels[provider] ?? provider
        guard let usage = result?.usage else {
            let code = errorCode(result) ?? "no_usage"
            return ProviderUsage(provider: provider, label: label, remainingPercent: nil, remainingLabel: nil,
                                 windows: [], updatedAt: nil, stale: true, error: code)
        }
        let updated = date(usage.updatedAt)
        let age = updated.map { now.timeIntervalSince($0) }
        let stale = lastKnown || age == nil || age! < -60 || age! > maximumAge
        let names = result?.rateWindowLabels ?? [:]

        var candidates: [(slot: String, window: UsageWindow, title: String?, known: Bool)] = []
        for (slot, window) in [("primary", usage.primary), ("secondary", usage.secondary), ("tertiary", usage.tertiary)] {
            if let window { candidates.append((slot, window, nil, true)) }
        }
        for extra in usage.extraRateWindows ?? [] {
            candidates.append(("extra:" + extra.id, extra.window, extra.title, extra.usageKnown))
        }
        let windows = candidates.map { slot, window, title, known -> UsageWindowStatus in
            let reset = date(window.resetsAt)
            return UsageWindowStatus(
                id: slot, label: windowLabel(slot, window: window, title: title, labels: names),
                remainingPercent: known ? remaining(window.usedPercent) : nil, resetsAt: reset,
                stale: stale || reset.map { $0 <= now } == true)
        }
        let selectable = windows.filter { ["primary", "secondary"].contains($0.id) && $0.remainingPercent != nil }
        let selected = selectable.first { !$0.stale } ?? selectable.first
        return ProviderUsage(provider: provider, label: label, remainingPercent: selected?.remainingPercent,
                             remainingLabel: selected?.label, windows: windows, updatedAt: updated,
                             stale: selected?.stale ?? stale, error: selected == nil ? (errorCode(result) ?? "no_usage") : errorCode(result))
    }

    /// Remaining share; over-limit usage shows as 0 (the raw value stays in the cache).
    static func remaining(_ used: Double?) -> Double? {
        guard let used, used.isFinite, used >= 0 else { return nil }
        return (max(0, 100 - used) * 100).rounded() / 100
    }

    static func windowLabel(_ slot: String, window: UsageWindow, title: String?, labels: [String: String]) -> String {
        if let label = labels[slot] ?? title, !label.isEmpty, label.count <= 40 { return label }
        switch window.windowMinutes {
        case 300: return "5h"
        case 10080: return "7d"
        case 1440: return "24h"
        case let minutes? where minutes.isFinite && minutes > 0:
            return minutes.truncatingRemainder(dividingBy: 60) == 0 ? "\(Int(minutes / 60))h" : "\(Int(minutes))m"
        default:
            return ["primary": "Primary", "secondary": "Secondary", "tertiary": "Other"][slot] ?? slot
        }
    }

    /// ISO 8601 with a zone only; a naive time can't be placed and stays unknown.
    static func date(_ text: String?) -> Date? {
        guard let text, text.count <= 80 else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let value = formatter.date(from: text) { return value }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}

/// Last results per provider, merged by the account rule and kept in a private cache file.
public final class UsageStore: @unchecked Sendable {
    struct Entry: Codable {
        var result: ProviderResult
        /// A kept older measurement shown after a network failure of the same account.
        var lastKnown = false
    }

    struct Document: Codable {
        var version = 1
        var entries: [String: Entry]
    }

    public static let maximumCacheBytes = 8 * 1024 * 1024
    private let cacheURL: URL?
    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    /// `cacheURL` nil keeps everything in memory (tests).
    public init(cacheURL: URL?) {
        self.cacheURL = cacheURL
        if let cacheURL, let data = Self.readPrivateFile(cacheURL),
           let document = try? JSONDecoder().decode(Document.self, from: data) {
            entries = document.entries.filter { UsageEngine.providers.contains($0.key) }
        }
    }

    public static var defaultCacheURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KeyMapper", isDirectory: true).appendingPathComponent("usage.json")
    }

    /// Merges fresh helper results. A failure that says nothing about the account keeps the previous
    /// measurement only when both carry the same account fingerprint; anything else replaces it.
    public func merge(_ results: [ProviderResult], providers: [String], now: Date = Date()) {
        lock.lock()
        for provider in providers {
            let fresh = results.first { $0.provider == provider } ?? .failure(provider, code: "helper_unavailable")
            let sanitized = Self.sanitize(fresh)
            let code = UsageNormalizer.errorCode(sanitized)
            if let code, UsageNormalizer.retainableErrors.contains(code),
               let fingerprint = sanitized.accountFingerprint, let old = entries[provider],
               old.result.accountFingerprint == fingerprint, let usage = old.result.usage {
                entries[provider] = Entry(result: ProviderResult(provider: provider, usage: usage,
                                                                 rateWindowLabels: old.result.rateWindowLabels,
                                                                 error: UsageFailure(code: code), accountFingerprint: fingerprint),
                                          lastKnown: true)
            } else {
                entries[provider] = Entry(result: sanitized)
            }
        }
        let document = Document(entries: entries)
        lock.unlock()
        persist(document)
    }

    /// Drops a provider the user switched off.
    public func remove(_ provider: String) {
        lock.lock()
        entries[provider] = nil
        let document = Document(entries: entries)
        lock.unlock()
        persist(document)
    }

    public func snapshot(providers: [String], now: Date = Date()) -> [ProviderUsage] {
        lock.lock(); defer { lock.unlock() }
        return providers.map { provider in
            let entry = entries[provider]
            return UsageNormalizer.normalize(entry?.result, provider: provider, lastKnown: entry?.lastKnown ?? false, now: now)
        }
    }

    /// Keeps only a well-formed fingerprint and a known error code.
    static func sanitize(_ result: ProviderResult) -> ProviderResult {
        let fingerprint = result.accountFingerprint.flatMap { value in
            value.count == 64 && value.allSatisfy { $0.isHexDigit && !$0.isUppercase } ? value : nil
        }
        let error = UsageNormalizer.errorCode(result).map { UsageFailure(code: $0) }
        return ProviderResult(provider: result.provider, usage: result.usage, rateWindowLabels: result.rateWindowLabels,
                              error: error, accountFingerprint: fingerprint)
    }

    // MARK: Private cache file

    private func persist(_ document: Document) {
        guard let cacheURL, let data = try? JSONEncoder().encode(document) else { return }
        let directory = cacheURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        // Write a private temporary file, then replace (never follow) the cache.
        let temporary = directory.appendingPathComponent(".usage-\(UUID().uuidString)")
        let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { return }
        let written = data.withUnsafeBytes { write(fd, $0.baseAddress, data.count) }
        let synced = fsync(fd) == 0
        close(fd)
        if written == data.count, synced, rename(temporary.path, cacheURL.path) == 0 { return }
        unlink(temporary.path)
    }

    /// Bounded read of a same-user regular 0600 file; symlinks, FIFOs and other modes are refused.
    static func readPrivateFile(_ url: URL) -> Data? {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == getuid(), (info.st_mode & S_IFMT) == S_IFREG,
              (info.st_mode & 0o777) == 0o600, info.st_size <= maximumCacheBytes else { return nil }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let count = read(fd, &buffer, buffer.count)
            if count == 0 { break }
            if count < 0 { if errno == EINTR { continue }; return nil }
            data.append(contentsOf: buffer.prefix(count))
            if data.count > maximumCacheBytes { return nil }
        }
        return data
    }
}
