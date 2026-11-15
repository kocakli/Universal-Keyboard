import Foundation
import KeyMapperCore
import KeyMapperUsage

/// One AI tool's hook installation, as read from its config file.
struct HookState: Equatable {
    var status: HookInstallStatus?
    /// AMG65 Studio's hook entries are still in this tool's config file.
    var studioEntries = false
    var error: String?
}

/// AI tool activity: off until the user turns it on. Nothing is read (hook journal, Codex logs, tool config files)
/// while it is off, and config files are only written from the hook buttons.
extension AppModel {
    static let activityEnabledKey = "activity.enabled"

    enum HookChange { case install, takeOver, remove }

    func setUpActivity() {
        if activityEnabled { startActivity() }
    }

    func setActivityEnabled(_ on: Bool) {
        activityEnabled = on
        UserDefaults.standard.set(on, forKey: Self.activityEnabledKey)
        if on { startActivity() } else { stopActivity() }
    }

    /// Activities in the form the LED renderer takes.
    var ledActivities: [LEDActivity] {
        activityRows.compactMap { row in
            guard row.state != .unknown, let expires = row.expiresAt else { return nil }
            return LEDActivity(provider: row.provider.rawValue, state: row.state.rawValue, summary: row.summary.rawValue,
                               expiresAt: expires, stale: row.stale)
        }
    }

    private func startActivity() {
        guard activityTask == nil else { return }
        refreshHookStates()
        let collector = ActivityCollector()
        // Studio's bridge polled about once a second; the collector reads small files, off the main thread.
        activityTask = Task { [weak self] in
            while !Task.isCancelled {
                let rows = await Task.detached(priority: .utility) { collector.snapshot() }.value
                guard !Task.isCancelled, let self else { return }
                if rows != self.activityRows { self.activityRows = rows }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func stopActivity() {
        activityTask?.cancel()
        activityTask = nil
        activityRows = []
        hookStates = [:]
    }

    // MARK: Hooks

    /// The helper the hooks run. Its path is written into the tools' config files.
    static var hookHelperPath: String? { UsageHelper.executable?.path }

    /// A path inside a build folder would break when the app moves, so hooks are installed only from /Applications.
    var canInstallHooks: Bool { Self.hookHelperPath?.hasPrefix("/Applications/") == true }

    func refreshHookStates() {
        guard activityEnabled else { return }
        let helper = Self.hookHelperPath ?? ""
        Task {
            let states = await Task.detached(priority: .utility) { Self.readHookStates(helper: helper) }.value
            if activityEnabled { hookStates = states }
        }
    }

    /// Installs, takes over from AMG65 Studio (removes Studio's entries and adds ours in one write) or removes.
    /// Each write keeps a backup of the previous file.
    func changeHooks(_ provider: ActivityProvider, _ change: HookChange) async {
        guard let helper = Self.hookHelperPath, change == .remove || canInstallHooks else { return }
        let result = await Task.detached(priority: .userInitiated) { () -> Result<URL?, Error> in
            let installer = HookInstaller(provider: provider, configURL: HookInstaller.defaultConfigURL(for: provider), helperPath: helper)
            return Result {
                switch change {
                case .install: return try installer.install()
                case .remove: return try installer.uninstall()
                case .takeOver:
                    let command = try HookConfig.command(helperPath: helper, provider: provider)
                    return try installer.update { existing in
                        try HookConfig.build(provider: provider, existing: HookConfig.removeStudioEntries(provider: provider, existing: existing),
                                             command: command, supportedEvents: installer.supportedEvents)
                    }
                }
            }
        }.value
        let name = Self.toolName(provider)
        switch result {
        case let .success(backup):
            notice = backup.map { L("%@ kancaları güncellendi; önceki dosya yedeklendi: %@", name, $0.lastPathComponent) }
                ?? L("%@ kancaları zaten güncel.", name)
            refreshHookStates()
        case let .failure(error):
            // Not refreshed: a fresh read would clear the message before it is seen. Nothing was written.
            hookStates[provider, default: HookState()].error = Self.hookMessage(error)
        }
    }

    static func toolName(_ provider: ActivityProvider) -> String {
        switch provider {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .cursor: return "Cursor"
        }
    }

    nonisolated private static func readHookStates(helper: String) -> [ActivityProvider: HookState] {
        var states: [ActivityProvider: HookState] = [:]
        for provider in ActivityProvider.allCases {
            let installer = HookInstaller(provider: provider, configURL: HookInstaller.defaultConfigURL(for: provider), helperPath: helper)
            var state = HookState()
            do { state.status = try installer.status() } catch { state.error = hookMessage(error) }
            state.studioEntries = hasStudioEntries(provider, at: installer.configURL)
            states[provider] = state
        }
        return states
    }

    /// Whether removing Studio's entries would change the file (read only; a missing or odd file counts as no).
    nonisolated private static func hasStudioEntries(_ provider: ActivityProvider, at url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true, (values.fileSize ?? 0) <= 4 * 1024 * 1024,
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        let cleaned = HookConfig.removeStudioEntries(provider: provider, existing: json)
        return !NSDictionary(dictionary: cleaned).isEqual(to: json)
    }

    nonisolated static func hookMessage(_ error: Error) -> String {
        guard let error = error as? HookConfigError else { return error.localizedDescription }
        switch error {
        case .relativeHelperPath, .invalidCommand:
            return L("KeyMapper'ın yardımcı programı bulunamadı.")
        case .malformedJSON, .malformedHooks:
            return L("Ayar dosyası beklenen biçimde değil; dosyaya dokunulmadı.")
        case .unsupportedCursorVersion:
            return L("Bu Cursor sürümünün kanca biçimi desteklenmiyor.")
        case .symbolicLink, .notRegularFile, .notOwnedByUser, .tooLarge:
            return L("Ayar dosyası güvenle yazılamıyor (bağlantı, başka kullanıcının dosyası ya da çok büyük); dosyaya dokunulmadı.")
        case .concurrentModification:
            return L("Ayar dosyası o sırada başka bir program tarafından değiştirildi; tekrar deneyin.")
        case .writeFailed:
            return L("Ayar dosyası yazılamadı.")
        }
    }
}
