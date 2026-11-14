import Darwin
import Foundation
import Testing
@testable import KeyMapperUsage

@Suite struct HookConfigTests {
    static let helper = "/Applications/KeyMapper.app/Contents/MacOS/keymapper-usage"

    private func json(_ text: String) -> [String: Any] {
        try! JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
    }

    @Test func configurationIsAdditiveIdempotentAndReversible() throws {
        let helper = "/App's path/$x/`literal`/keymapper-usage"
        for provider in ActivityProvider.allCases {
            let event = try #require(HookConfig.events[provider]?.first)
            let original: [String: Any] = ["hooks": [event: [["command": "existing-user-command"]]], "other": ["key": true]]
            let command = try HookConfig.command(helperPath: helper, provider: provider)
            let all = Set(HookConfig.events[provider]!)
            let merged = try HookConfig.build(provider: provider, existing: original, command: command, supportedEvents: all)
            let list = try #require((merged["hooks"] as? [String: Any])?[event] as? [Any])
            #expect(HookConfig.same(list[0], ["command": "existing-user-command"]))
            #expect(HookConfig.same(merged["other"]!, ["key": true]))
            let twice = try HookConfig.build(provider: provider, existing: merged, command: command, supportedEvents: all)
            #expect(HookConfig.same(merged, twice))
            var removed = HookConfig.remove(provider: provider, existing: merged, command: command)
            if provider == .cursor {
                #expect(removed["version"] as? Int == 1)
                removed["version"] = nil
            }
            #expect(HookConfig.same(removed, original))
            let entry = try #require(list.last as? [String: Any])
            let nested = (entry["hooks"] as? [Any])?.first as? [String: Any]
            let handler = try #require(provider == .cursor ? entry : nested)
            #expect(handler["timeout"] as? Int == 2 && handler["type"] as? String == "command")
            let words = HookConfig.split(try #require(handler["command"] as? String))
            #expect(words == [helper, "hook", "--provider", provider.rawValue])
        }
    }

    @Test func quotingMatchesPythonShlex() throws {
        // Expected values printed by Python 3.14's shlex.quote / shlex.join.
        let cases = [
            ("", "''"), ("abc", "abc"), ("a b", "'a b'"), ("it's", #"'it'"'"'s'"#),
            ("/App's path/$x/`literal`/keymapper-usage", #"'/App'"'"'s path/$x/`literal`/keymapper-usage'"#),
            (Self.helper, Self.helper), ("ü", "'ü'"), (#"a"b"#, #"'a"b'"#), ("@%+=:,./-_", "@%+=:,./-_"),
        ]
        for (word, quoted) in cases { #expect(HookConfig.quote(word) == quoted) }
        #expect(try HookConfig.command(helperPath: "/Applications/Key Mapper.app/keymapper-usage", provider: .claude)
                == "'/Applications/Key Mapper.app/keymapper-usage' hook --provider claude")
    }

    @Test func splittingMatchesPythonShlex() {
        #expect(HookConfig.split(#"a\ b "c d" e"f"g 'h'\''i' "x\$y\z""#) == ["a b", "c d", "efg", "h'i", #"x\$y\z"#])
        #expect(HookConfig.split("''") == [""])
        #expect(HookConfig.split("'unterminated") == nil)
        #expect(HookConfig.split(#"trailing\"#) == nil)
    }

    @Test func noAssumedHookSupportOrPermissionDecisions() throws {
        #expect(HookConfig.same(try HookConfig.build(provider: .codex, existing: [:], command: "/hook", supportedEvents: []),
                                ["hooks": [String: Any]()]))
        for provider in ActivityProvider.allCases {
            let command = try HookConfig.command(helperPath: Self.helper, provider: provider)
            let result = try HookConfig.build(provider: provider, existing: [:], command: command,
                                              supportedEvents: Set(HookConfig.events[provider]!))
            let encoded = String(decoding: try JSONSerialization.data(withJSONObject: result), as: UTF8.self)
            for forbidden in ["permissionDecision", "followup_message", "failClosed", "updatedInput", "async"] {
                #expect(!encoded.contains(forbidden))
            }
            #expect(HookConfig.verifiedEvents[provider]!.isSubset(of: Set(HookConfig.events[provider]!)))
        }
        #expect(!HookConfig.events[.cursor]!.contains("preToolUse"))
        #expect(!HookConfig.events[.cursor]!.contains("beforeSubmitPrompt"))
        #expect(HookConfig.verifiedEvents[.claude] == ["UserPromptSubmit", "PreToolUse", "PostToolUse", "PreCompact", "Stop", "SessionEnd"])
        #expect(HookConfig.verifiedEvents[.codex]?.count == 10 && HookConfig.verifiedEvents[.cursor]?.count == 6)
    }

    @Test func malformedConfigRefusesWithoutModification() {
        for config in [json(#"{"hooks":[]}"#), json(#"{"hooks":{"Stop":"bad"}}"#), json(#"{"hooks":{"Stop":["text"]}}"#),
                       json(#"{"hooks":null}"#)] {
            #expect(throws: HookConfigError.malformedHooks) {
                _ = try HookConfig.build(provider: .codex, existing: config, command: "/hook", supportedEvents: ["Stop"])
            }
        }
        #expect(throws: HookConfigError.invalidCommand) {
            _ = try HookConfig.build(provider: .codex, existing: [:], command: "", supportedEvents: ["Stop"])
        }
        #expect(throws: HookConfigError.relativeHelperPath) {
            try HookConfig.command(helperPath: "keymapper-usage", provider: .codex)
        }
    }

    @Test func cursorConfigurationVersionIsChecked() throws {
        for version in [#"2"#, #""1""#, #"null"#] {
            #expect(throws: HookConfigError.unsupportedCursorVersion) {
                _ = try HookConfig.build(provider: .cursor, existing: json(#"{"version":\#(version)}"#), command: "/hook",
                                     supportedEvents: ["stop"])
            }
        }
        for text in [#"{"version":1}"#, #"{}"#] {
            let result = try HookConfig.build(provider: .cursor, existing: json(text), command: "/hook", supportedEvents: ["stop"])
            #expect(result["version"] as? Int == 1)
            #expect(HookConfig.same(result["hooks"]!, ["stop": [["type": "command", "command": "/hook", "timeout": 2] as [String: Any]]]))
        }
    }

    @Test func studioEntriesAreRemovedOnlyForTheSameProvider() throws {
        func studio(_ provider: String, script: String = "/Applications/AMG65 Studio.app/Contents/Resources/activity_hooks.py") -> String {
            ["/usr/bin/python3", script, "receive", "--provider", provider, "--state-dir",
             "/Users/x/Library/Application Support/AMG65 Studio/state"].map(HookConfig.quote).joined(separator: " ")
        }
        func handler(_ command: String) -> [String: Any] { ["type": "command", "command": command, "timeout": 2] }
        func group(_ handlers: [String: Any]...) -> [String: Any] { ["hooks": handlers] }

        let user = group(handler("~/bin/notify"))
        let ours = HookConfig.entry(provider: .claude, command: try HookConfig.command(helperPath: Self.helper, provider: .claude))
        let otherProvider = group(handler(studio("codex")))
        let mixed = group(handler(studio("claude")), handler("~/bin/notify"))
        let lookalikes: [[String: Any]] = [
            group(handler("echo activity_hooks.py receive --provider claude")),
            group(handler(studio("claude", script: "/x/not_activity_hooks.py"))),
            group(["type": "command", "command": studio("claude"), "timeout": 5]),
            ["matcher": "Bash", "hooks": [handler(studio("claude"))]],
        ]
        let existing: [String: Any] = ["model": "opus", "hooks": [
            "Stop": [user, group(handler(studio("claude"))), ours, otherProvider, mixed] + lookalikes,
            "PreToolUse": [group(handler(studio("claude")))],
            "NotAHookEvent": [group(handler(studio("claude")))],
        ]]
        let result = HookConfig.removeStudioEntries(provider: .claude, existing: existing)
        let hooks = try #require(result["hooks"] as? [String: Any])
        #expect(HookConfig.same(hooks["Stop"]!, [user, ours, otherProvider, mixed] + lookalikes))
        #expect(hooks["PreToolUse"] == nil)
        #expect(HookConfig.same(hooks["NotAHookEvent"]!, [group(handler(studio("claude")))]))
        #expect(result["model"] as? String == "opus")

        let cursor: [String: Any] = ["version": 1, "hooks": ["stop": [handler(studio("cursor")), handler(studio("claude")), handler("x")]]]
        let cleaned = HookConfig.removeStudioEntries(provider: .cursor, existing: cursor)
        #expect(HookConfig.same(cleaned, ["version": 1, "hooks": ["stop": [handler(studio("claude")), handler("x")]]] as [String: Any]))
    }
}

@Suite struct HookInstallerTests {
    typealias F = ActivityFixtures
    static let helper = HookConfigTests.helper

    private func object(_ url: URL) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func write(_ text: String, to url: URL, mode: mode_t = 0o644) throws {
        try Data(text.utf8).write(to: url)
        chmod(url.path, mode)
    }

    @Test func installCreatesPrivateFileIdempotentAndReversible() throws {
        let root = F.temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent(".claude/settings.json")
        let installer = HookInstaller(provider: .claude, configURL: url, helperPath: Self.helper)
        #expect(try installer.status() == .notInstalled)
        #expect(try installer.install() == nil)
        #expect(F.mode(url) == 0o600)
        #expect(try installer.status() == .installed)
        let hooks = try #require(try object(url)["hooks"] as? [String: Any])
        #expect(Set(hooks.keys) == HookConfig.verifiedEvents[.claude])
        let entry = HookConfig.entry(provider: .claude, command: try HookConfig.command(helperPath: Self.helper, provider: .claude))
        #expect(hooks.values.allSatisfy { HookConfig.same($0, [entry]) })
        let installed = try Data(contentsOf: url)
        #expect(try installer.install() == nil)
        #expect(try Data(contentsOf: url) == installed)
        #expect(F.contents(url.deletingLastPathComponent()) == ["settings.json"])

        let backup = try #require(try installer.uninstall())
        #expect(try Data(contentsOf: backup) == installed)
        #expect(HookConfig.same(try object(url), ["hooks": [String: Any]()]))
        #expect(try installer.status() == .notInstalled)
        #expect(try installer.uninstall() == nil)
    }

    @Test func existingSettingsModeAndUserHooksArePreservedWithBackup() throws {
        let root = F.temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("hooks.json")
        let text = #"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"user-thing"}]}]},"permissions":{"allow":["Bash(ls)"]}}"#
        try write(text, to: url)
        let original = try object(url)
        let installer = HookInstaller(provider: .codex, configURL: url, helperPath: Self.helper)
        let backup = try #require(try installer.install())
        #expect(backup.deletingLastPathComponent() == url.deletingLastPathComponent())
        #expect(backup.lastPathComponent.hasPrefix("hooks.json.keymapper-backup-"))
        #expect(try String(contentsOf: backup, encoding: .utf8) == text)
        #expect(F.mode(backup) == 0o600)
        #expect(F.mode(url) == 0o644)
        let merged = try object(url)
        #expect(HookConfig.same(merged["permissions"]!, original["permissions"]!))
        let stop = try #require((merged["hooks"] as? [String: Any])?["Stop"] as? [Any])
        let userGroup = try #require(((original["hooks"] as? [String: Any])?["Stop"] as? [Any])?.first)
        #expect(stop.count == 2)
        #expect(HookConfig.same(stop[0], userGroup))
        #expect(try installer.status() == .installed)

        try installer.uninstall()
        #expect(HookConfig.same(try object(url), original))
        #expect(F.mode(url) == 0o644)
        #expect(!F.contents(root).contains { $0.contains(".keymapper-") && !$0.contains("backup") })
    }

    @Test func linksMalformedJSONAndUnknownVersionsAreRefusedUntouched() throws {
        let root = F.temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("target.json")
        try write("{}", to: target)
        let link = root.appendingPathComponent("settings.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let linked = HookInstaller(provider: .claude, configURL: link, helperPath: Self.helper)
        #expect(throws: HookConfigError.symbolicLink) { try linked.install() }
        #expect(throws: HookConfigError.symbolicLink) { try linked.status() }
        #expect(try String(contentsOf: target, encoding: .utf8) == "{}")

        let cases: [(String, ActivityProvider, HookConfigError)] = [
            ("{broken", .claude, .malformedJSON), ("[]", .claude, .malformedJSON), ("", .codex, .malformedJSON),
            (#"{"version":2,"hooks":{}}"#, .cursor, .unsupportedCursorVersion), (#"{"hooks":[]}"#, .claude, .malformedHooks),
        ]
        for (text, provider, error) in cases {
            let directory = root.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("hooks.json")
            try write(text, to: url)
            let installer = HookInstaller(provider: provider, configURL: url, helperPath: Self.helper)
            #expect(throws: error) { try installer.install() }
            #expect(throws: error) { try installer.status() }
            if error != .malformedHooks { #expect(throws: error) { try installer.uninstall() } }
            #expect(try String(contentsOf: url, encoding: .utf8) == text)
            #expect(F.contents(directory) == ["hooks.json"])
        }

        let fifo = root.appendingPathComponent("fifo.json")
        mkfifo(fifo.path, 0o600)
        #expect(throws: HookConfigError.notRegularFile) {
            try HookInstaller(provider: .claude, configURL: fifo, helperPath: Self.helper).install()
        }
        #expect(throws: HookConfigError.relativeHelperPath) {
            try HookInstaller(provider: .claude, configURL: root.appendingPathComponent("x.json"), helperPath: "keymapper-usage").install()
        }
    }

    @Test func concurrentModificationIsDetected() throws {
        let root = F.temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("settings.json")
        try write("{}", to: url)
        var installer = HookInstaller(provider: .claude, configURL: url, helperPath: Self.helper)
        installer.beforeReplace = { _ = try? Data(#"{"changed":true}"#.utf8).write(to: url) }
        #expect(throws: HookConfigError.concurrentModification) { try installer.install() }
        #expect(try String(contentsOf: url, encoding: .utf8) == #"{"changed":true}"#)
        #expect(F.contents(root) == ["settings.json"])

        // A file that appears while a new one is prepared is never overwritten.
        let fresh = root.appendingPathComponent("new/settings.json")
        var creating = HookInstaller(provider: .claude, configURL: fresh, helperPath: Self.helper)
        creating.beforeReplace = { _ = try? Data("{}".utf8).write(to: fresh) }
        #expect(throws: HookConfigError.concurrentModification) { try creating.install() }
        #expect(try String(contentsOf: fresh, encoding: .utf8) == "{}")
        #expect(F.contents(fresh.deletingLastPathComponent()) == ["settings.json"])
    }

    @Test func partialInstallationIsReported() throws {
        let root = F.temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("hooks.json")
        let command = try HookConfig.command(helperPath: Self.helper, provider: .cursor)
        let partial = try HookConfig.build(provider: .cursor, existing: [:], command: command, supportedEvents: ["stop"])
        try JSONSerialization.data(withJSONObject: partial).write(to: url)
        let installer = HookInstaller(provider: .cursor, configURL: url, helperPath: Self.helper)
        #expect(try installer.status() == .partial)
        try installer.install()
        #expect(try installer.status() == .installed)
        #expect(try object(url)["version"] as? Int == 1)
        let other = HookInstaller(provider: .cursor, configURL: url, helperPath: "/Other/keymapper-usage")
        #expect(try other.status() == .notInstalled)
    }

    @Test func defaultLocationsAreTheDocumentedFiles() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(HookInstaller.defaultConfigURL(for: .claude).path == home + "/.claude/settings.json")
        #expect(HookInstaller.defaultConfigURL(for: .codex).path == home + "/.codex/hooks.json")
        #expect(HookInstaller.defaultConfigURL(for: .cursor).path == home + "/.cursor/hooks.json")
        #expect(HookInstaller(provider: .claude, configURL: URL(fileURLWithPath: "/x"), helperPath: "/h").supportedEvents
                == HookConfig.verifiedEvents[.claude])
    }
}
