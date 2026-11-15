import Foundation
import Testing
@testable import KeyMapperUsage

/// The Claude desktop app's sign-in, with made-up tokens and a made-up safe-storage password.
@Suite struct ClaudeDesktopTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let password = "fixture-safe-storage-password"

    func cache(_ plain: Any) throws -> Data {
        let data = plain is String ? Data((plain as! String).utf8) : try JSONSerialization.data(withJSONObject: plain)
        return try #require(SafeStorage.encrypt(data, password: password))
    }

    func token(_ caches: [Data], password: String? = nil) throws -> String {
        try ClaudeDesktop.credentials(caches: caches, now: now) { Data((password ?? self.password).utf8) }.token
    }

    func failure(_ body: () throws -> Void) -> String? {
        do { try body(); return nil } catch let failure as UsageFailure { return failure.code } catch { return "other" }
    }

    @Test func cachesComeFromTheConfigNewestFirst() throws {
        let v1 = try cache(["accessToken": "sk-ant-oat01-old"]), v2 = try cache(["accessToken": "sk-ant-oat01-new"])
        let config = try JSONSerialization.data(withJSONObject: [
            "darkMode": "dark", "oauth:tokenCache": v1.base64EncodedString(), "oauth:tokenCacheV2": v2.base64EncodedString(),
        ])
        #expect(ClaudeDesktop.encryptedCaches(config: config) == [v2, v1])
        // Signed out, or something that isn't safe storage: nothing to read.
        #expect(ClaudeDesktop.encryptedCaches(config: Data(#"{"darkMode":"dark"}"#.utf8)).isEmpty)
        let plain = Data("not encrypted".utf8).base64EncodedString()
        #expect(ClaudeDesktop.encryptedCaches(config: Data(#"{"oauth:tokenCacheV2":"\#(plain)"}"#.utf8)).isEmpty)
    }

    @Test func theFreshestTokenWithTheProfileScopeIsUsed() throws {
        let soon = (now.timeIntervalSince1970 + 600) * 1000, later = (now.timeIntervalSince1970 + 7200) * 1000
        // Filed under its scope list, expiry in milliseconds, next to a refresh token.
        let keyed = try cache([
            "user:inference user:profile user:sessions:claude_code": [
                "token": "sk-ant-oat01-keyed", "refreshToken": "sk-ant-ort01-never-used", "expiresAt": later,
            ],
        ])
        #expect(try token([keyed]) == "sk-ant-oat01-keyed")
        // Plain fields, expiry in seconds and as a date; the later one wins.
        let entries = try cache(["accounts": [
            ["accessToken": "sk-ant-oat01-soon", "expiresAt": soon / 1000, "scopes": ["user:profile"]],
            ["access_token": "sk-ant-oat01-later", "expires_at": UsageDates.iso(Date(timeIntervalSince1970: later / 1000)),
             "scope": "user:inference user:profile"],
        ]])
        #expect(try token([entries]) == "sk-ant-oat01-later")
        // A token without the profile scope can't read usage.
        let inferenceOnly = try cache(["accessToken": "sk-ant-oat01-inference", "scopes": ["user:inference"], "expiresAt": later])
        #expect(failure { _ = try token([inferenceOnly]) } == "auth_required")
        // Expired: the desktop app renews it when it runs.
        let expired = try cache(["accessToken": "sk-ant-oat01-expired", "expiresAt": (now.timeIntervalSince1970 - 10) * 1000])
        #expect(failure { _ = try token([expired]) } == "relogin_required")
        // The older cache format is still read when the newer one has nothing usable.
        #expect(try token([expired, keyed]) == "sk-ant-oat01-keyed")
        // A bare token string.
        #expect(try token([cache("sk-ant-oat01-bare")]) == "sk-ant-oat01-bare")
        // Each token is its own account fingerprint, never the token itself.
        let credentials = try ClaudeDesktop.credentials(caches: [keyed], now: now) { Data(password.utf8) }
        #expect(credentials.fingerprint.count == 64 && !credentials.fingerprint.contains("sk-ant"))
    }

    @Test func unreadableSignInsSayWhy() throws {
        let good = try cache(["accessToken": "sk-ant-oat01-fixture"])
        #expect(failure { _ = try token([good], password: "another-password") } == "credentials_unreadable")
        #expect(failure { _ = try token([cache(["something": ["else": 1]])]) } == "credentials_unreadable")
        #expect(failure { _ = try token([]) } == "auth_required")
        // No safe-storage key: the app was never signed in on this Mac.
        #expect(failure { _ = try ClaudeDesktop.credentials(caches: [good], now: now) { nil } } == "auth_required")
        // A locked key reaches the app as is, so it can offer the Keychain button.
        #expect(failure {
            _ = try ClaudeDesktop.credentials(caches: [good], now: now) { throw UsageFailure(code: "keychain_locked") }
        } == "keychain_locked")
    }

    @Test func theLoggedLayoutHasNoValues() throws {
        let layout: [String: Any] = [
            "8b0f5c39-2d1e-4a8b-9f0e-1c2d3e4f5a6b": ["token": "sk-ant-oat01-secret", "refresh": "sk-ant-ort01-secret",
                                                     "email": "someone@example.com", "expiresAt": 1, "ok": true],
        ]
        let shape = ClaudeDesktop.shape(layout)
        #expect(!shape.contains("secret") && !shape.contains("someone") && !shape.contains("8b0f5c39"))
        #expect(shape.contains("<uuid>") && shape.contains("<access token>") && shape.contains("<refresh token>"))
    }

    @Test func theDesktopSignInComesFirstAndItsFailureIsTheOneShown() throws {
        let desktop = ClaudeProvider.Credentials(token: "desktop", fingerprint: "d")
        let terminal = ClaudeProvider.Credentials(token: "terminal", fingerprint: "t")
        let caches = [Data("v10".utf8)]
        // No desktop sign-in: Claude Code's, as before.
        #expect(try ClaudeProvider.preferDesktop(caches: [], desktop: { desktop }, terminal: { terminal }).token == "terminal")
        var terminalRead = false
        #expect(try ClaudeProvider.preferDesktop(caches: caches, desktop: { desktop },
                                                 terminal: { terminalRead = true; return terminal }).token == "desktop")
        #expect(!terminalRead)
        #expect(try ClaudeProvider.preferDesktop(caches: caches, desktop: { throw UsageFailure(code: "relogin_required") },
                                                 terminal: { terminal }).token == "terminal")
        // Both fail: the desktop's reason, so the Keychain button asks for the desktop app's item.
        #expect(failure {
            _ = try ClaudeProvider.preferDesktop(caches: caches, desktop: { throw UsageFailure(code: "keychain_locked") },
                                                 terminal: { throw UsageFailure(code: "relogin_required") })
        } == "keychain_locked")
        #expect(failure {
            _ = try ClaudeProvider.preferDesktop(caches: [], desktop: { desktop }, terminal: { throw UsageFailure(code: "relogin_required") })
        } == "relogin_required")
    }

    @Test func theKeychainButtonAsksForTheItemTheReaderOpens() throws {
        #expect(CredentialReader.keychainAccessTarget(provider: "claude", claudeDesktopSignedIn: true)?.service == "Claude Safe Storage")
        #expect(CredentialReader.keychainAccessTarget(provider: "claude", claudeDesktopSignedIn: true)?.accounts == ["Claude Key"])
        #expect(CredentialReader.keychainAccessTarget(provider: "claude")?.service == "Claude Code-credentials")

        let home = FileManager.default.temporaryDirectory.appendingPathComponent("claude-desktop-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        #expect(!ClaudeDesktop.isSignedIn(home: home))
        let config = ClaudeDesktop.configURL(home: home)
        try FileManager.default.createDirectory(at: config.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ["oauth:tokenCacheV2": cache(["accessToken": "sk-ant-oat01-x"]).base64EncodedString()])
            .write(to: config)
        #expect(ClaudeDesktop.isSignedIn(home: home))
    }
}
