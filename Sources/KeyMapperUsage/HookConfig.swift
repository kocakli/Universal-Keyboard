// Ported from AMG65 Studio's activity_hooks.py and docs/ACTIVITY.md; see THIRD_PARTY_NOTICES.md.
import Darwin
import Foundation

/// Why a host hook configuration was not read or changed. The app localises these.
public enum HookConfigError: Error, Equatable, Sendable {
    case relativeHelperPath
    case invalidCommand
    /// The file is not a JSON object.
    case malformedJSON
    /// `hooks`, or an event's hook list, is not the documented shape.
    case malformedHooks
    case unsupportedCursorVersion
    case symbolicLink
    case notRegularFile
    case notOwnedByUser
    case tooLarge
    /// The file changed while it was being updated; nothing was replaced.
    case concurrentModification
    case writeFailed
}

/// Pure, additive and reversible hook configuration for Codex (`~/.codex/hooks.json`), Claude Code
/// (`~/.claude/settings.json`) and Cursor (`~/.cursor/hooks.json`). Existing hooks, settings and permission
/// policies are preserved; entries carry no permission decisions, follow-ups, input rewrites or fail-closed flags.
public enum HookConfig {
    /// Every event the receiver understands, in configuration order (AMG65 Studio's `HOOK_EVENTS`).
    /// Cursor permission hooks are excluded: some require a permission response.
    public static let events: [ActivityProvider: [String]] = [
        .codex: ["UserPromptSubmit", "PreModelRequest", "PostModelRequest", "PreToolUse", "PermissionRequest",
                 "PostToolUse", "PreCompact", "Stop", "Interrupt", "SessionEnd"],
        .claude: ["UserPromptSubmit", "PreToolUse", "PermissionRequest", "PostToolUse", "PostToolUseFailure",
                  "PreCompact", "Notification", "Elicitation", "ElicitationResult", "Stop", "StopFailure", "SessionEnd"],
        .cursor: ["postToolUse", "postToolUseFailure", "afterAgentResponse", "preCompact", "stop", "sessionEnd"],
    ]

    /// The sets AMG65 Studio verified against the installed hosts and configured. Other events must not be
    /// installed without verifying that host's capabilities.
    public static let verifiedEvents: [ActivityProvider: Set<String>] = [
        .codex: ["UserPromptSubmit", "PreModelRequest", "PostModelRequest", "PreToolUse", "PermissionRequest",
                 "PostToolUse", "PreCompact", "Stop", "Interrupt", "SessionEnd"],
        .claude: ["UserPromptSubmit", "PreToolUse", "PostToolUse", "PreCompact", "Stop", "SessionEnd"],
        .cursor: ["postToolUse", "postToolUseFailure", "afterAgentResponse", "preCompact", "stop", "sessionEnd"],
    ]

    /// Seconds the host waits for the receiver.
    public static let timeout = 2

    /// `<helper> hook --provider <provider>`, shell-quoted like Python's `shlex.join`.
    public static func command(helperPath: String, provider: ActivityProvider) throws -> String {
        guard helperPath.hasPrefix("/") else { throw HookConfigError.relativeHelperPath }
        return [helperPath, "hook", "--provider", provider.rawValue].map(quote).joined(separator: " ")
    }

    /// A copy of `existing` with this integration's entry appended to each supported event that lacks it.
    /// `supportedEvents` must be the verified capability set of the installed host.
    public static func build(provider: ActivityProvider, existing: [String: Any], command: String,
                             supportedEvents: Set<String>) throws -> [String: Any] {
        guard !command.isEmpty else { throw HookConfigError.invalidCommand }
        var result = existing
        if provider == .cursor {
            if let version = result["version"], !isNumber(version, 1) { throw HookConfigError.unsupportedCursorVersion }
            result["version"] = 1
        }
        var hooks: [String: Any] = [:]
        if let value = result["hooks"] {
            guard let object = value as? [String: Any] else { throw HookConfigError.malformedHooks }
            hooks = object
        }
        let entry = entry(provider: provider, command: command)
        for event in events[provider] ?? [] where supportedEvents.contains(event) {
            var current: [Any] = []
            if let value = hooks[event] {
                guard let list = value as? [Any], list.allSatisfy({ $0 is [String: Any] }) else {
                    throw HookConfigError.malformedHooks
                }
                current = list
            }
            if !current.contains(where: { same($0, entry) }) { current.append(entry) }
            hooks[event] = current
        }
        result["hooks"] = hooks
        return result
    }

    /// Removes only entries exactly equal to the ones `build` creates for `command`.
    public static func remove(provider: ActivityProvider, existing: [String: Any], command: String) -> [String: Any] {
        guard !command.isEmpty else { return existing }
        let owned = entry(provider: provider, command: command)
        return removing(provider: provider, from: existing) { same($0, owned) }
    }

    /// Removes only AMG65 Studio's own entries for the same provider: exactly the shape it generates, whose
    /// command runs `activity_hooks.py receive --provider <provider> --state-dir <dir>`. Groups that also hold
    /// other handlers, and every other entry, are kept.
    public static func removeStudioEntries(provider: ActivityProvider, existing: [String: Any]) -> [String: Any] {
        removing(provider: provider, from: existing) { isStudioEntry($0, provider: provider) }
    }

    // MARK: Internals

    static func entry(provider: ActivityProvider, command: String) -> [String: Any] {
        let handler: [String: Any] = ["type": "command", "command": command, "timeout": timeout]
        return provider == .cursor ? handler : ["hooks": [handler]]
    }

    /// Deep JSON equality (numbers by value, like Python's `==`).
    static func same(_ lhs: Any, _ rhs: Any) -> Bool {
        (lhs as AnyObject).isEqual(rhs as AnyObject)
    }

    static func isNumber(_ value: Any?, _ expected: Double) -> Bool {
        (value as? NSNumber)?.doubleValue == expected
    }

    private static func removing(provider: ActivityProvider, from existing: [String: Any],
                                 where owned: (Any) -> Bool) -> [String: Any] {
        var result = existing
        guard var hooks = result["hooks"] as? [String: Any] else { return result }
        for event in events[provider] ?? [] {
            guard let list = hooks[event] as? [Any] else { continue }
            let kept = list.filter { !owned($0) }
            hooks[event] = kept.isEmpty ? nil : kept
        }
        result["hooks"] = hooks
        return result
    }

    static func isStudioEntry(_ entry: Any, provider: ActivityProvider) -> Bool {
        var candidate = entry as? [String: Any]
        if provider != .cursor {
            guard let group = candidate, group.count == 1, let list = group["hooks"] as? [Any], list.count == 1 else { return false }
            candidate = list[0] as? [String: Any]
        }
        guard let handler = candidate, Set(handler.keys) == ["type", "command", "timeout"], handler["type"] as? String == "command",
              isNumber(handler["timeout"], Double(timeout)), let command = handler["command"] as? String,
              let words = split(command), words.count == 7 else { return false }
        return (words[1] as NSString).lastPathComponent == "activity_hooks.py"
            && Array(words[2...5]) == ["receive", "--provider", provider.rawValue, "--state-dir"]
    }

    /// Python's `shlex.quote`.
    static func quote(_ word: String) -> String {
        if word.isEmpty { return "''" }
        let safe = word.unicodeScalars.allSatisfy {
            ("a"..."z").contains($0) || ("A"..."Z").contains($0) || ("0"..."9").contains($0) || "_@%+=:,./-".unicodeScalars.contains($0)
        }
        return safe ? word : "'" + word.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    /// Python's `shlex.split` (POSIX mode, no comments); nil for an unterminated quote or escape.
    static func split(_ command: String) -> [String]? {
        enum Mode { case plain, single, double }
        let scalars = Array(command.unicodeScalars)
        var words: [String] = []
        var word = String.UnicodeScalarView()
        var inWord = false
        var mode = Mode.plain
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            switch mode {
            case .plain:
                if " \t\r\n".unicodeScalars.contains(scalar) {
                    if inWord { words.append(String(word)); word = .init(); inWord = false }
                } else if scalar == "\\" {
                    index += 1
                    guard index < scalars.count else { return nil }
                    word.append(scalars[index]); inWord = true
                } else if scalar == "'" {
                    mode = .single; inWord = true
                } else if scalar == "\"" {
                    mode = .double; inWord = true
                } else {
                    word.append(scalar); inWord = true
                }
            case .single:
                if scalar == "'" { mode = .plain } else { word.append(scalar) }
            case .double:
                if scalar == "\"" {
                    mode = .plain
                } else if scalar == "\\", index + 1 < scalars.count, scalars[index + 1] == "\"" || scalars[index + 1] == "\\" {
                    index += 1
                    word.append(scalars[index])
                } else {
                    word.append(scalar)
                }
            }
            index += 1
        }
        guard mode == .plain else { return nil }
        if inWord { words.append(String(word)) }
        return words
    }
}

/// Whether this integration's hooks are configured for every verified event.
public enum HookInstallStatus: Equatable, Sendable {
    case notInstalled, partial, installed
}

/// Applies `HookConfig` to one host configuration file: backs up an existing regular owner-owned file at
/// mode 0600, refuses symbolic links, malformed JSON and unknown Cursor versions, detects concurrent
/// modification and atomically replaces the file, preserving its mode. Never touches trust databases.
public struct HookInstaller: Sendable {
    public let provider: ActivityProvider
    public let configURL: URL
    public let helperPath: String
    public let supportedEvents: Set<String>
    static let maximumBytes = 4 * 1024 * 1024
    /// Test seam: runs after the new content is written, just before the final modification check.
    var beforeReplace: (@Sendable () -> Void)?

    /// `supportedEvents` defaults to the verified set for `provider`.
    public init(provider: ActivityProvider, configURL: URL, helperPath: String, supportedEvents: Set<String>? = nil) {
        self.provider = provider
        self.configURL = configURL
        self.helperPath = helperPath
        self.supportedEvents = supportedEvents ?? HookConfig.verifiedEvents[provider] ?? []
    }

    /// `~/.claude/settings.json`, `~/.codex/hooks.json` or `~/.cursor/hooks.json`.
    public static func defaultConfigURL(for provider: ActivityProvider) -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch provider {
        case .claude: return home.appendingPathComponent(".claude/settings.json")
        case .codex: return home.appendingPathComponent(".codex/hooks.json")
        case .cursor: return home.appendingPathComponent(".cursor/hooks.json")
        }
    }

    public func status() throws -> HookInstallStatus {
        let command = try HookConfig.command(helperPath: helperPath, provider: provider)
        let hooks = try load().object["hooks"].map { value -> [String: Any] in
            guard let hooks = value as? [String: Any] else { throw HookConfigError.malformedHooks }
            return hooks
        } ?? [:]
        let entry = HookConfig.entry(provider: provider, command: command)
        let wanted = (HookConfig.events[provider] ?? []).filter(supportedEvents.contains)
        let present = wanted.filter { event in
            (hooks[event] as? [Any])?.contains { HookConfig.same($0, entry) } == true
        }
        if present.isEmpty { return .notInstalled }
        return present.count == wanted.count ? .installed : .partial
    }

    /// Adds the receiver for every supported event. Returns the backup of the previous file, if one was made.
    @discardableResult
    public func install() throws -> URL? {
        let command = try HookConfig.command(helperPath: helperPath, provider: provider)
        return try update { try HookConfig.build(provider: provider, existing: $0, command: command, supportedEvents: supportedEvents) }
    }

    /// Removes exactly the entries `install` adds. Returns the backup of the previous file, if one was made.
    @discardableResult
    public func uninstall() throws -> URL? {
        let command = try HookConfig.command(helperPath: helperPath, provider: provider)
        return try update { HookConfig.remove(provider: provider, existing: $0, command: command) }
    }

    /// Safely applies `transform` to the configuration. Nothing is written (and no backup made) when the
    /// result equals the current configuration. Returns the backup of the previous file, if one was made.
    @discardableResult
    public func update(_ transform: ([String: Any]) throws -> [String: Any]) throws -> URL? {
        let current = try load()
        let updated = try transform(current.object)
        if HookConfig.same(updated, current.object), current.identity != nil || updated.isEmpty { return nil }
        guard JSONSerialization.isValidJSONObject(updated),
              var data = try? JSONSerialization.data(withJSONObject: updated,
                                                     options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        else { throw HookConfigError.malformedJSON }
        data.append(10)
        let directory = configURL.deletingLastPathComponent()
        if current.identity == nil {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                     attributes: [.posixPermissions: 0o700])
        }
        let backup = try current.data.map(writeBackup)
        let name = "." + configURL.lastPathComponent + ".keymapper-"
        guard let temporary = PrivateIO.temporaryFile(beside: configURL, prefix: name, data: data, mode: current.mode) else {
            if let backup { unlink(backup.path) }
            throw HookConfigError.writeFailed
        }
        beforeReplace?()
        var replaced: Int32 = -1
        if let identity = current.identity {
            if Self.identity(of: configURL) == identity { replaced = rename(temporary, configURL.path) }
        } else {
            // A file that appeared meanwhile is never overwritten.
            replaced = renamex_np(temporary, configURL.path, UInt32(RENAME_EXCL))
        }
        let failure = errno
        guard replaced == 0 else {
            unlink(temporary)
            if let backup { unlink(backup.path) }
            let changed = current.identity == nil ? failure == EEXIST : Self.identity(of: configURL) != current.identity
            throw changed ? HookConfigError.concurrentModification : HookConfigError.writeFailed
        }
        return backup
    }

    // MARK: Reading and backup

    struct Identity: Equatable {
        let device: dev_t, inode: ino_t, size: off_t, seconds: Int, nanoseconds: Int
    }

    struct Loaded {
        let object: [String: Any]
        let data: Data?
        let identity: Identity?
        let mode: mode_t
    }

    static func identity(of url: URL) -> Identity? {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return nil }
        return Identity(device: info.st_dev, inode: info.st_ino, size: info.st_size,
                        seconds: info.st_mtimespec.tv_sec, nanoseconds: info.st_mtimespec.tv_nsec)
    }

    /// The current configuration; an empty object when the file doesn't exist yet.
    func load() throws -> Loaded {
        var info = stat()
        if lstat(configURL.path, &info) != 0 {
            guard errno == ENOENT else { throw HookConfigError.notRegularFile }
            return Loaded(object: [:], data: nil, identity: nil, mode: 0o600)
        }
        if (info.st_mode & S_IFMT) == S_IFLNK { throw HookConfigError.symbolicLink }
        guard (info.st_mode & S_IFMT) == S_IFREG else { throw HookConfigError.notRegularFile }
        guard info.st_uid == getuid() else { throw HookConfigError.notOwnedByUser }
        guard info.st_size <= Self.maximumBytes else { throw HookConfigError.tooLarge }
        let fd = open(configURL.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw errno == ELOOP ? HookConfigError.symbolicLink : HookConfigError.notRegularFile }
        defer { close(fd) }
        var opened = stat()
        guard fstat(fd, &opened) == 0, opened.st_dev == info.st_dev, opened.st_ino == info.st_ino else {
            throw HookConfigError.concurrentModification
        }
        guard let data = PrivateIO.readAll(fd, limit: Self.maximumBytes) else { throw HookConfigError.tooLarge }
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw HookConfigError.malformedJSON
        }
        if provider == .cursor, let version = object["version"], !HookConfig.isNumber(version, 1) {
            throw HookConfigError.unsupportedCursorVersion
        }
        return Loaded(object: object, data: data,
                      identity: Identity(device: opened.st_dev, inode: opened.st_ino, size: opened.st_size,
                                         seconds: opened.st_mtimespec.tv_sec, nanoseconds: opened.st_mtimespec.tv_nsec),
                      mode: info.st_mode & 0o777)
    }

    /// `<name>.keymapper-backup-<UTC time>[-n]` beside the file, mode 0600, never replacing anything.
    func writeBackup(_ data: Data) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let base = configURL.lastPathComponent + ".keymapper-backup-" + formatter.string(from: Date())
        for attempt in 0..<100 {
            let url = configURL.deletingLastPathComponent().appendingPathComponent(attempt == 0 ? base : "\(base)-\(attempt + 1)")
            let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
            if fd < 0 {
                if errno == EEXIST { continue }
                throw HookConfigError.writeFailed
            }
            let ok = fchmod(fd, 0o600) == 0 && PrivateIO.writeAll(fd, data) && fsync(fd) == 0
            close(fd)
            guard ok else { unlink(url.path); throw HookConfigError.writeFailed }
            return url
        }
        throw HookConfigError.writeFailed
    }
}
