import Foundation
import Testing
@testable import KeyMapperUsage

/// Ported from AMG65 Studio's tests/test_usage_adapter.py (same cases, no network or credentials).
@Suite struct UsageStoreTests {
    static let now = ISO8601DateFormatter().date(from: "2026-11-07T08:30:00Z")!

    private func result(_ json: String) throws -> ProviderResult {
        try JSONDecoder().decode(ProviderResult.self, from: Data(json.utf8))
    }

    private func payload(used: String = "20", updated: String = "2026-11-07T08:29:00Z", reset: String = "2026-11-07T12:00:00Z",
                         secondary: String? = nil, fingerprint: String? = nil, error: String? = nil) throws -> ProviderResult {
        var fields: [String] = [#""provider":"claude""#]
        if let error {
            fields.append(#""error":{"code":"\#(error)"}"#)
        } else {
            var usage = #""updatedAt":"\#(updated)","primary":{"usedPercent":\#(used),"windowMinutes":300,"resetsAt":"\#(reset)"}"#
            if let secondary { usage += #","secondary":\#(secondary)"# }
            fields.append(#""usage":{\#(usage)}"#)
        }
        if let fingerprint { fields.append(#""accountFingerprint":"\#(fingerprint)""#) }
        return try result("{" + fields.joined(separator: ",") + "}")
    }

    private func normalize(_ value: ProviderResult) -> ProviderUsage {
        UsageNormalizer.normalize(value, provider: "claude", now: Self.now)
    }

    @Test func measuredZeroIsFullRemaining() throws {
        let usage = normalize(try payload(used: "0"))
        #expect(usage.remainingPercent == 100)
        #expect(!usage.stale)
    }

    @Test func missingAndNegativeUsageIsUnknown() throws {
        #expect(normalize(try payload(used: "null")).remainingPercent == nil)
        #expect(normalize(try payload(used: "-1")).remainingPercent == nil)
    }

    @Test func overQuotaShowsZeroRemaining() throws {
        #expect(normalize(try payload(used: "125")).remainingPercent == 0)
    }

    @Test func oldMeasurementKeepsItsTimeAndIsStale() throws {
        let usage = normalize(try payload(updated: "2026-11-07T07:00:00Z"))
        #expect(usage.stale)
        #expect(usage.updatedAt == ISO8601DateFormatter().date(from: "2026-11-07T07:00:00Z"))
    }

    @Test func passedResetMarksStale() throws {
        #expect(normalize(try payload(reset: "2026-11-07T08:00:00Z")).stale)
    }

    @Test func naiveAndFutureMeasurementsAreStale() throws {
        #expect(normalize(try payload(updated: "2026-11-07T08:29:00")).stale)
        #expect(normalize(try payload(updated: "2026-11-07T09:29:00Z")).stale)
    }

    @Test func timeZonesAreNormalised() throws {
        let usage = normalize(try payload(updated: "2026-11-07T17:29:00+09:00"))
        #expect(usage.updatedAt == ISO8601DateFormatter().date(from: "2026-11-07T08:29:00Z"))
        #expect(!usage.stale)
    }

    @Test func independentWindowsAreNotAggregated() throws {
        let usage = normalize(try payload(used: "20", secondary: #"{"usedPercent":90,"windowMinutes":10080}"#))
        #expect(usage.remainingPercent == 80)
        #expect(usage.windows[1].remainingPercent == 10)
        #expect(usage.windows[1].label == "7d")
    }

    @Test func expiredPrimaryDoesNotHideFreshSecondary() throws {
        let usage = normalize(try payload(reset: "2026-11-07T08:00:00Z",
                                          secondary: #"{"usedPercent":10,"windowMinutes":10080,"resetsAt":"2026-11-14T08:00:00Z"}"#))
        #expect(usage.remainingPercent == 90)
        #expect(usage.windows[0].stale)
    }

    @Test func unknownNamedQuotaIsNeverPrimary() throws {
        let value = try result(#"""
        {"provider":"cursor","usage":{"updatedAt":"2026-11-07T08:29:00Z","tertiary":{"usedPercent":0},
         "extraRateWindows":[{"id":"grok","title":"Grok","usageKnown":false,"window":{"usedPercent":100,"windowMinutes":10080}}]}}
        """#)
        let usage = UsageNormalizer.normalize(value, provider: "cursor", now: Self.now)
        #expect(usage.remainingPercent == nil)
        #expect(usage.windows[1].remainingPercent == nil)
    }

    @Test func unknownErrorCodesAreBounded() throws {
        let usage = normalize(try payload(error: "secret-cookie=abc"))
        #expect(usage.error == "fetch_failed")
        #expect(!String(describing: usage).contains("secret"))
    }

    @Test func sameAccountNetworkFailureKeepsTheMeasurementAsStale() throws {
        let store = UsageStore(cacheURL: nil)
        store.merge([try payload(fingerprint: String(repeating: "a", count: 64))], providers: ["claude"], now: Self.now)
        store.merge([try payload(fingerprint: String(repeating: "a", count: 64), error: "network_error")], providers: ["claude"], now: Self.now)
        let usage = store.snapshot(providers: ["claude"], now: Self.now)[0]
        #expect(usage.remainingPercent == 80)
        #expect(usage.stale)
        #expect(usage.updatedAt == ISO8601DateFormatter().date(from: "2026-11-07T08:29:00Z"))
        #expect(usage.error == "network_error")
    }

    @Test func otherOrMissingAccountNeverReusesTheMeasurement() throws {
        for fingerprint in [String(repeating: "b", count: 64), nil] {
            let store = UsageStore(cacheURL: nil)
            store.merge([try payload(fingerprint: String(repeating: "a", count: 64))], providers: ["claude"], now: Self.now)
            store.merge([try payload(fingerprint: fingerprint, error: "network_error")], providers: ["claude"], now: Self.now)
            #expect(store.snapshot(providers: ["claude"], now: Self.now)[0].remainingPercent == nil)
        }
    }

    @Test func authenticationFailureClearsTheMeasurement() throws {
        let store = UsageStore(cacheURL: nil)
        store.merge([try payload(fingerprint: String(repeating: "a", count: 64))], providers: ["claude"], now: Self.now)
        store.merge([try payload(fingerprint: String(repeating: "a", count: 64), error: "relogin_required")], providers: ["claude"], now: Self.now)
        let usage = store.snapshot(providers: ["claude"], now: Self.now)[0]
        #expect(usage.remainingPercent == nil)
        #expect(usage.error == "relogin_required")
    }

    @Test func privateCacheReloadsAndHoldsNoIdentity() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = directory.appendingPathComponent("usage.json")
        let store = UsageStore(cacheURL: cache)
        store.merge([try payload(fingerprint: String(repeating: "a", count: 64))], providers: ["claude"], now: Self.now)
        let attributes = try FileManager.default.attributesOfItem(atPath: cache.path)
        #expect((attributes[.posixPermissions] as? Int) == 0o600)
        let reloaded = UsageStore(cacheURL: cache)
        let usage = reloaded.snapshot(providers: ["claude"], now: Self.now)[0]
        #expect(usage.remainingPercent == 80)
        // What the app shows carries no account fingerprint.
        #expect(!String(describing: usage).contains(String(repeating: "a", count: 64)))
    }

    @Test func nonPrivateSymlinkedOrCorruptCacheIsIgnored() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = directory.appendingPathComponent("usage.json")
        let good = UsageStore(cacheURL: cache)
        good.merge([try payload()], providers: ["claude"], now: Self.now)
        let valid = try Data(contentsOf: cache)

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: cache.path)
        #expect(UsageStore(cacheURL: cache).snapshot(providers: ["claude"], now: Self.now)[0].remainingPercent == nil)

        try FileManager.default.removeItem(at: cache)
        let target = directory.appendingPathComponent("target.json")
        try valid.write(to: target)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
        try FileManager.default.createSymbolicLink(at: cache, withDestinationURL: target)
        #expect(UsageStore(cacheURL: cache).snapshot(providers: ["claude"], now: Self.now)[0].remainingPercent == nil)

        try FileManager.default.removeItem(at: cache)
        try Data("{broken".utf8).write(to: cache)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cache.path)
        #expect(UsageStore(cacheURL: cache).snapshot(providers: ["claude"], now: Self.now)[0].remainingPercent == nil)
    }

    @Test func providerSelectionIsValidated() {
        #expect(UsageEngine.selection([]) == ["claude", "cursor", "codex"])
        #expect(UsageEngine.selection(["--providers", "codex,claude"]) == ["claude", "codex"])
        #expect(UsageEngine.selection(["--providers", "claude,claude"]) == nil)
        #expect(UsageEngine.selection(["--providers", "claude;rm"]) == nil)
        #expect(UsageEngine.selection(["--provider"]) == nil)
    }
}
