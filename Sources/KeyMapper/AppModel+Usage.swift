import Foundation
import KeyMapperCore
import KeyMapperUsage

/// AI tool quotas (Claude, Codex, Cursor), read with the user's existing sign-ins by the bundled
/// `keymapper-usage` helper. Every provider is off until the user turns it on.
extension AppModel {
    static let usageInterval: TimeInterval = 5 * 60
    private static let providersKey = "usage.providers"

    static func loadUsageProviders() -> [String] {
        let stored = UserDefaults.standard.stringArray(forKey: providersKey) ?? []
        return UsageEngine.providers.filter(stored.contains)
    }

    func setUpUsage() {
        usage = usageStore.snapshot(providers: usageProviders)
        usageTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshUsage(force: false) }
        }
        refreshUsage(force: false)
    }

    func isUsageEnabled(_ provider: String) -> Bool { usageProviders.contains(provider) }

    func setUsage(_ provider: String, enabled: Bool) {
        var list = Set(usageProviders)
        if enabled { list.insert(provider) } else { list.remove(provider); usageStore.remove(provider) }
        usageProviders = UsageEngine.providers.filter(list.contains)
        UserDefaults.standard.set(usageProviders, forKey: Self.providersKey)
        usage = usageStore.snapshot(providers: usageProviders)
        if enabled {
            usageAwaiting.insert(provider)
            refreshUsage(force: true, coalesce: false)
        } else {
            usageAwaiting.remove(provider)
        }
    }

    /// Quotas in the order the LED matrix uses; providers that are off show as unknown.
    var ledQuotas: [LEDQuota] {
        LEDMatrixRenderer.providers.map { provider in
            let row = usage.first { $0.provider == provider.id }
            return LEDQuota(provider: provider.id, remainingPercent: row?.remainingPercent, stale: row?.stale ?? false)
        }
    }

    /// Every five minutes on its own; a click asks again at most every ten seconds. A request while a
    /// refresh runs (e.g. a provider just switched on) is queued and runs right after it.
    func refreshUsage(force: Bool, coalesce: Bool = true) {
        guard !usageProviders.isEmpty else { return }
        guard !usageRefreshing else {
            if force { usageQueued = true }
            return
        }
        if coalesce, let last = usageLastRequest {
            let age = Date().timeIntervalSince(last)
            if force ? age < 10 : age < Self.usageInterval { return }
        }
        usageLastRequest = Date()
        usageRefreshing = true
        let providers = usageProviders
        Task {
            let results = await UsageHelper.fetch(providers: providers)
            usageStore.merge(results, providers: providers)
            usage = usageStore.snapshot(providers: usageProviders)
            usageAwaiting.subtract(providers)
            usageRefreshing = false
            if usageQueued {
                usageQueued = false
                refreshUsage(force: true, coalesce: false)
            }
        }
    }

    /// Asks macOS once for the Keychain item the provider's sign-in lives in (Claude, Cursor).
    /// This is the only path that may show the system dialog, and only after the user's click.
    func authorizeKeychain(for provider: String) {
        Task {
            let result = await UsageHelper.authorizeKeychain(provider: provider)
            switch result {
            case "granted":
                notice = L("Anahtar Zinciri erişimi verildi.")
                refreshUsage(force: true, coalesce: false)
            case "denied": errorMessage = L("Anahtar Zinciri erişimi reddedildi.")
            case "missing": errorMessage = L("Bu sağlayıcının Anahtar Zinciri kaydı bulunamadı; önce uygulamasında oturum açın.")
            default: errorMessage = L("Anahtar Zinciri erişimi istenemedi.")
            }
        }
    }
}

/// Runs the bundled helper with a time limit and a bounded output; only quota JSON comes back.
enum UsageHelper {
    static let timeout: TimeInterval = 25
    static let maximumOutput = 8 * 1024 * 1024

    static var executable: URL? {
        if let bundled = Bundle.main.url(forAuxiliaryExecutable: "keymapper-usage") { return bundled }
        // `swift run` / `.build/debug`: the helper sits next to the app's executable.
        return Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("keymapper-usage")
    }

    static func fetch(providers: [String]) async -> [ProviderResult] {
        guard let data = await run(["--providers", providers.joined(separator: ",")]),
              let results = try? JSONDecoder().decode([ProviderResult].self, from: data) else {
            return providers.map { ProviderResult.unavailable($0) }
        }
        return results
    }

    static func authorizeKeychain(provider: String) async -> String {
        guard let data = await run(["--authorize-keychain", provider], timeout: 120) else { return "failed" }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func run(_ arguments: [String], timeout: TimeInterval = timeout) async -> Data? {
        guard let executable, FileManager.default.isExecutableFile(atPath: executable.path) else { return nil }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = executable
                process.arguments = arguments
                let output = Pipe()
                process.standardOutput = output
                process.standardError = FileHandle.nullDevice
                do { try process.run() } catch { continuation.resume(returning: nil); return }
                let killer = DispatchWorkItem { if process.isRunning { process.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
                var data = Data()
                let handle = output.fileHandleForReading
                while true {
                    let chunk = handle.availableData
                    if chunk.isEmpty { break }
                    data.append(chunk)
                    if data.count > maximumOutput { process.terminate(); data = Data(); break }
                }
                process.waitUntilExit()
                killer.cancel()
                continuation.resume(returning: process.terminationReason == .exit && process.terminationStatus == 0 && !data.isEmpty ? data : nil)
            }
        }
    }
}

extension ProviderResult {
    static func unavailable(_ provider: String) -> ProviderResult {
        // Decoding keeps the initialisers internal to the usage module.
        let json = #"{"provider":"\#(provider)","error":{"code":"helper_unavailable"}}"#
        return try! JSONDecoder().decode(ProviderResult.self, from: Data(json.utf8))
    }
}

extension ProviderUsage {
    /// What the user can do about a missing or failed reading.
    var errorDescription: String? {
        guard let error else { return nil }
        switch error {
        case "auth_required": return L("Oturum bulunamadı; %@ uygulamasında oturum açın.", label)
        case "relogin_required": return L("Oturumun süresi dolmuş; %@ uygulamasında yeniden oturum açın.", label)
        case "keychain_locked": return L("Okumak için Anahtar Zinciri izni gerekiyor.")
        case "network_error": return L("Ağ hatası; daha sonra yeniden denenecek.")
        case "rate_limited": return L("Sağlayıcı istekleri sınırladı; daha sonra yeniden denenecek.")
        case "timeout": return L("Zaman aşımı; daha sonra yeniden denenecek.")
        case "access_denied": return L("Sağlayıcı erişimi reddetti.")
        case "no_usage": return L("Bu hesap için kullanım bilgisi yok.")
        case "helper_unavailable": return L("Kullanım okuyucusu çalıştırılamadı.")
        default: return L("Kullanım okunamadı.")
        }
    }
}
