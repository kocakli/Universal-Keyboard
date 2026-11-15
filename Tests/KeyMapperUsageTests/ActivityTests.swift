import Darwin
import Foundation
import Testing
@testable import KeyMapperUsage

/// Shared fixtures for the activity suites, ported from AMG65 Studio's tests/test_activity.py.
/// Everything happens in fresh temporary directories; real agent configuration and logs are never read.
enum ActivityFixtures {
    static let now: TimeInterval = 1_794_038_400

    static func hook(_ provider: String = "codex", _ event: String = "PreToolUse", now: TimeInterval = now,
                     _ values: [String: Any] = [:]) -> ActivityEvent? {
        var payload: [String: Any] = ["session_id": "private-session-id", "conversation_id": "private-session-id",
                                      "turn_id": "private-turn-id", "generation_id": "private-turn-id",
                                      "hook_event_name": event, "tool_name": "Bash"]
        payload.merge(values) { $1 }
        return ActivityNormalizer.hook(provider: provider, payload: payload, now: now)
    }

    static func record(_ kind: Any, at time: TimeInterval = now, _ values: [String: Any] = [:]) -> [String: Any] {
        var payload: [String: Any] = ["type": kind, "turn_id": "private-turn-id"]
        payload.merge(values) { $1 }
        return ["timestamp": isoformat(time), "type": "event_msg", "payload": payload]
    }

    /// Python's `datetime.fromtimestamp(time, timezone.utc).isoformat()`.
    static func isoformat(_ time: TimeInterval) -> String {
        var seconds = time_t(time.rounded(.down))
        var parts = tm()
        gmtime_r(&seconds, &parts)
        let micro = Int(((time - time.rounded(.down)) * 1_000_000).rounded())
        return String(format: "%04d-%02d-%02dT%02d:%02d:%02d", Int(parts.tm_year) + 1900, Int(parts.tm_mon) + 1,
                      Int(parts.tm_mday), Int(parts.tm_hour), Int(parts.tm_min), Int(parts.tm_sec))
            + (micro == 0 ? "" : String(format: ".%06d", micro)) + "+00:00"
    }

    static func line(_ row: Any) -> Data {
        var data = try! JSONSerialization.data(withJSONObject: row)
        data.append(10)
        return data
    }

    static func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("keymapper-activity-" + UUID().uuidString)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func mode(_ url: URL) -> Int {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return -1 }
        return Int(info.st_mode & 0o777)
    }

    static func contents(_ directory: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
    }
}

@Suite struct ActivityHookTests {
    typealias F = ActivityFixtures

    @Test func documentedApprovalOnly() {
        for provider in ["codex", "claude"] {
            #expect(F.hook(provider, "PermissionRequest")?.state == .waitingApproval)
        }
        #expect(F.hook("cursor", "PermissionRequest") == nil)
        #expect(F.hook("cursor", "beforeShellExecution") == nil)
    }

    @Test func explicitInputAndResult() {
        #expect(F.hook("claude", "Elicitation")?.state == .waitingInput)
        #expect(F.hook("claude", "PreToolUse", ["tool_name": "AskUserQuestion"])?.state == .waitingInput)
        #expect(F.hook("codex", "PreToolUse", ["tool_name": "request_user_input_async"])?.state == .waitingInput)
        #expect(F.hook("claude", "ElicitationResult")?.clearsWait == true)
    }

    @Test func idleAndBackgroundCompletionAreNotQuestionsOrSuccess() {
        for notification in ["idle_prompt", "agent_completed", "auth_success", "plugin_notification"] {
            #expect(F.hook("claude", "Notification", ["notification_type": notification]) == nil)
        }
        #expect(F.hook("claude", "Notification", ["notification_type": "agent_needs_input"])?.state == .waitingInput)
    }

    @Test func cursorTerminalStatusIsExplicit() {
        for (status, state) in [("completed", ActivityState.completed), ("error", .error), ("aborted", .unknown)] {
            #expect(F.hook("cursor", "stop", ["status": status])?.state == state)
        }
        #expect(F.hook("cursor", "stop", ["status": "invented"]) == nil)
        #expect(F.hook("cursor", "afterAgentResponse")?.state == .running)
    }

    @Test func subagentsDoNotCompleteParent() {
        for provider in ["claude", "codex", "cursor"] {
            #expect(F.hook(provider, "SubagentStop") == nil)
            #expect(F.hook(provider, "subagentStop") == nil)
        }
    }

    @Test func noArbitraryTextSurvives() throws {
        let secret = "SECRET /private/home prompt token command filename"
        let event = try #require(F.hook("claude", "PreToolUse", [
            "tool_name": secret, "tool_input": ["command": secret], "prompt": secret, "message": secret,
            "cwd": secret, "error": secret, "user_email": secret,
        ]))
        let encoded = String(decoding: try JSONSerialization.data(withJSONObject: event.row), as: UTF8.self)
        #expect(!encoded.contains(secret))
        #expect(!String(describing: event).contains(secret))
        #expect(event.summary == .usingTool)
        #expect(!encoded.contains("private-session-id"))
        #expect(event.sessionID.count == 20)
    }

    @Test func invalidShapesAreIgnoredWithoutException() {
        let payloads: [Any?] = [nil, [Any](), "string", [String: Any](), ["session_id": [String: Any]()],
                                ["session_id": "x", "hook_event_name": [Any]()]]
        for payload in payloads {
            #expect(ActivityNormalizer.hook(provider: "codex", payload: payload, now: F.now) == nil)
        }
        #expect(F.hook("codex", "PreToolUse", ["tool_name": ["unexpected": "dict"]])?.summary == .usingTool)
        #expect(F.hook("claude", "Notification", ["notification_type": ["bad": "shape"]]) == nil)
        #expect(ActivityNormalizer.hook(provider: "unknown", payload: [String: Any](), now: F.now) == nil)
    }

    /// Every provider × event × payload variant, compared with the output of Studio's `normalize_hook`
    /// (generated with Python 3.14). Lines: provider, event, variant indices, state, summary, clears_wait.
    /// Every combination not listed must be ignored.
    @Test func everyHookMappingMatchesStudio() {
        let events = ["UserPromptSubmit", "PreModelRequest", "PostModelRequest", "PreToolUse", "PostToolUse",
                      "PermissionRequest", "PostToolUseFailure", "Stop", "StopFailure", "Interrupt", "SessionEnd",
                      "PreCompact", "Elicitation", "ElicitationResult", "Notification", "SubagentStop", "beforeSubmitPrompt",
                      "preToolUse", "postToolUse", "postToolUseFailure", "afterAgentResponse", "preCompact", "stop",
                      "sessionEnd", "SessionStart"]
        let variants: [[String: Any]] = [
            [:], ["tool_name": "AskUserQuestion"], ["tool_name": "Read"], ["status": "failed"], ["status": "completed"],
            ["status": "aborted"], ["notification_type": "permission_prompt"],
            ["notification_type": "elicitation_complete"], ["notification_type": "idle_prompt"],
        ]
        let table = """
        codex UserPromptSubmit 012345678 queued prompt_submitted 1
        codex PreModelRequest 012345678 running working 1
        codex PostModelRequest 01245678 running working 1
        codex PostModelRequest 3 error failed 1
        codex PreToolUse 0345678 running running_command 0
        codex PreToolUse 1 waiting_input input_requested 0
        codex PreToolUse 2 running reading_files 0
        codex PostToolUse 0345678 running running_command 0
        codex PostToolUse 1 running using_tool 0
        codex PostToolUse 2 running reading_files 0
        codex PermissionRequest 012345678 waiting_approval approval_requested 0
        codex Stop 012345678 completed completed 1
        codex Interrupt 012345678 unknown interrupted 1
        codex SessionEnd 012345678 unknown session_ended 1
        codex PreCompact 012345678 running compacting 0
        claude UserPromptSubmit 012345678 queued prompt_submitted 1
        claude PreToolUse 0345678 running running_command 0
        claude PreToolUse 1 waiting_input input_requested 0
        claude PreToolUse 2 running reading_files 0
        claude PostToolUse 0345678 running running_command 0
        claude PostToolUse 1 running using_tool 0
        claude PostToolUse 2 running reading_files 0
        claude PermissionRequest 012345678 waiting_approval approval_requested 0
        claude PostToolUseFailure 012345678 error tool_failed 0
        claude Stop 012345678 completed completed 1
        claude StopFailure 012345678 error failed 1
        claude SessionEnd 012345678 unknown session_ended 1
        claude PreCompact 012345678 running compacting 0
        claude Elicitation 012345678 waiting_input input_requested 0
        claude ElicitationResult 012345678 running input_received 1
        claude Notification 6 waiting_approval approval_requested 0
        claude Notification 7 running input_received 1
        cursor beforeSubmitPrompt 012345678 queued prompt_submitted 1
        cursor preToolUse 0345678 running running_command 0
        cursor preToolUse 1 running using_tool 0
        cursor preToolUse 2 running reading_files 0
        cursor postToolUse 0345678 running running_command 0
        cursor postToolUse 1 running using_tool 0
        cursor postToolUse 2 running reading_files 0
        cursor postToolUseFailure 012345678 error tool_failed 0
        cursor afterAgentResponse 012345678 running working 0
        cursor preCompact 012345678 running compacting 0
        cursor stop 4 completed completed 1
        cursor stop 5 unknown interrupted 1
        cursor sessionEnd 012345678 unknown session_ended 1
        """
        var expected: [String: String] = [:]
        for line in table.split(separator: "\n") {
            let fields = line.split(separator: " ").map(String.init)
            for index in fields[2] { expected["\(fields[0]) \(fields[1]) \(index)"] = fields[3...5].joined(separator: " ") }
        }
        var compared = 0
        for provider in ActivityProvider.allCases.map(\.rawValue) {
            for event in events {
                for (index, variant) in variants.enumerated() {
                    var payload: [String: Any] = ["session_id": "s", "conversation_id": "s", "hook_event_name": event, "tool_name": "Bash"]
                    payload.merge(variant) { $1 }
                    let actual = ActivityNormalizer.hook(provider: provider, payload: payload, now: F.now)
                        .map { "\($0.state.rawValue) \($0.summary.rawValue) \($0.clearsWait ? 1 : 0)" }
                    #expect(actual == expected["\(provider) \(event) \(index)"], "\(provider) \(event) \(index)")
                    compared += 1
                }
            }
        }
        #expect(compared == 675 && expected.count == 256)
    }

    /// Studio's `normalize_codex_record` for each rollout record kind (state, summary, clears_wait, has wait token).
    @Test func everyCodexRecordMappingMatchesStudio() {
        let item = { (type: String) -> (String, [String: Any]) in ("event_msg", ["type": "item_completed", "item": ["type": type]]) }
        let call = { (type: String, name: String) -> (String, [String: Any]) in ("response_item", ["type": type, "name": name, "call_id": "c"]) }
        let cases: [((String, [String: Any]), String?)] = [
            (("event_msg", ["type": "task_started"]), "running working 1 0"),
            (("event_msg", ["type": "task_complete"]), "completed completed 1 0"),
            (("event_msg", ["type": "turn_aborted"]), "unknown interrupted 1 0"),
            (("event_msg", ["type": "agent_message"]), nil), (("event_msg", ["type": "token_count"]), nil),
            (item("Reasoning"), "running working 0 0"), (item("CommandExecution"), "running running_command 0 0"),
            (item("FileChange"), "running editing_files 0 0"), (item("WebSearch"), "running searching 0 0"),
            (item("McpToolCall"), "running using_tool 0 0"), (item("ContextCompaction"), "running compacting 0 0"),
            (item("AgentMessage"), nil),
            (call("function_call", "exec_command"), "running running_command 0 1"),
            (call("function_call", "read_file"), "running reading_files 0 1"),
            (call("custom_tool_call", "apply_patch"), "running editing_files 0 1"),
            (call("custom_tool_call", "web_search"), "running searching 0 1"),
            (call("function_call", "request_user_input"), "waiting_input input_requested 0 1"),
            (call("custom_tool_call", "mystery"), "running using_tool 0 1"),
            (("response_item", ["type": "function_call_output", "call_id": "c"]), "running using_tool 0 1"),
            (("response_item", ["type": "custom_tool_call_output", "call_id": "c"]), "running using_tool 0 1"),
            (("response_item", ["type": "message", "call_id": "c"]), nil),
            (("response_item", ["type": "reasoning", "call_id": "c"]), nil),
        ]
        for ((type, payload), expected) in cases {
            var body = payload
            body["turn_id"] = "t"
            let event = ActivityNormalizer.codexRecord(["timestamp": F.isoformat(F.now), "type": type, "payload": body],
                                                       session: "s", now: F.now)
            let actual = event.map {
                "\($0.state.rawValue) \($0.summary.rawValue) \($0.clearsWait ? 1 : 0) \($0.waitToken.isEmpty ? 0 : 1)"
            }
            #expect(actual == expected, "\(type) \(payload)")
        }
    }

    @Test func providerSpecificEventsAndToolCategories() {
        #expect(F.hook("claude", "PreToolUse", ["tool_name": "Read"])?.summary == .readingFiles)
        #expect(F.hook("codex", "PostToolUse", ["tool_name": "apply_patch"])?.summary == .editingFiles)
        #expect(F.hook("cursor", "postToolUse", ["tool_name": "Grep"])?.summary == .searching)
        #expect(F.hook("codex", "PostModelRequest", ["status": "failed"])?.state == .error)
        #expect(F.hook("codex", "PreModelRequest")?.clearsWait == true)
        #expect(F.hook("claude", "PreModelRequest") == nil)
        #expect(F.hook("codex", "PostToolUseFailure") == nil)
        #expect(F.hook("claude", "PostToolUseFailure")?.summary == .toolFailed)
        #expect(F.hook("claude", "Interrupt") == nil)
        #expect(F.hook("codex", "Interrupt")?.summary == .interrupted)
        #expect(F.hook("cursor", "beforeSubmitPrompt")?.state == .queued)
        // A missing turn falls back to the session identity; the raw id is never kept.
        #expect(F.hook("codex", "Stop", ["turn_id": NSNull()])?.turnID == ActivityNormalizer.opaque("private-session-id"))
        #expect(F.hook("codex", "Stop", ["session_id": String(repeating: "x", count: 513)]) == nil)
    }
}

/// A private journal directory plus a collector that never scans Codex logs.
struct ActivityStoreFixture {
    let root = ActivityFixtures.temporaryDirectory()
    let path: URL
    let store: ActivityStore
    let collector: ActivityCollector

    init() {
        path = root.appendingPathComponent("state")
        store = ActivityStore(directory: path)
        collector = ActivityCollector(stateDirectory: path, scanCodex: false)
    }

    func rows(_ now: TimeInterval = ActivityFixtures.now) -> [ActivityRow] {
        collector.snapshot(now: Date(timeIntervalSince1970: now))
    }

    func selected(_ now: TimeInterval = ActivityFixtures.now) -> ActivityRow? { ActivityCollector.selected(rows(now)) }

    @discardableResult func record(_ event: ActivityEvent?) -> Bool { event.map(store.record) ?? false }

    func remove() { try? FileManager.default.removeItem(at: root) }
}

@Suite struct ActivityStoreTests {
    typealias F = ActivityFixtures

    @Test func permissionsAtomicStateAndNoHistory() throws {
        let f = ActivityStoreFixture(); defer { f.remove() }
        #expect(f.record(F.hook()))
        #expect(F.mode(f.path) == 0o700)
        #expect(F.mode(f.store.fileURL) == 0o600)
        #expect(f.store.read().count == 1)
        f.record(F.hook(now: F.now + 1))
        #expect(f.store.read().count == 1)
        #expect(!F.contents(f.path).contains { $0.hasPrefix(".activity-") })
    }

    @Test func matchingToolResultPreservesObservedCategoryWithoutGuessingOtherCalls() {
        let f = ActivityStoreFixture(); defer { f.remove() }
        func toolEvent(_ kind: String, _ time: TimeInterval, _ call: String, _ name: String? = nil) -> ActivityEvent? {
            var payload: [String: Any] = ["type": kind, "turn_id": "private-turn-id", "call_id": call]
            if let name { payload["name"] = name }
            return ActivityNormalizer.codexRecord(["timestamp": F.isoformat(time), "type": "response_item", "payload": payload],
                                                  session: "private-session-id", now: time)
        }
        f.record(toolEvent("function_call", F.now, "call-a", "read_file"))
        f.record(toolEvent("function_call_output", F.now + 1, "call-a"))
        #expect(f.store.read().first?.summary == .readingFiles)
        f.record(toolEvent("function_call_output", F.now + 2, "call-other"))
        #expect(f.store.read().first?.summary == .usingTool)
    }

    @Test func expiryUnknownAndNoSelected() {
        let f = ActivityStoreFixture(); defer { f.remove() }
        f.record(F.hook())
        #expect(f.selected()?.state == .running)
        let rows = f.rows(F.now + ActivityState.running.lifetime)
        #expect(ActivityCollector.selected(rows) == nil)
        #expect(rows[0].provider == .codex)
        #expect(rows[0].state == .unknown)
        #expect(rows[0].stale)
        #expect(rows[0].expiresAt == F.now + 120)
    }

    @Test func priorityWaitingAndOtherProvider() {
        let f = ActivityStoreFixture(); defer { f.remove() }
        f.record(F.hook())
        f.record(F.hook("claude", "PermissionRequest"))
        #expect(f.selected()?.provider == .claude)
    }

    @Test func unrelatedToolDoesNotClearWait() {
        let f = ActivityStoreFixture(); defer { f.remove() }
        f.record(F.hook("claude", "PermissionRequest", ["tool_use_id": "approval-tool"]))
        f.record(F.hook("claude", "PostToolUse", now: F.now + 1, ["tool_use_id": "unrelated-tool"]))
        #expect(f.selected()?.state == .waitingApproval)
        f.record(F.hook("claude", "PostToolUse", now: F.now + 2, ["tool_use_id": "approval-tool"]))
        #expect(f.selected()?.state == .running)
    }

    @Test func modelResumeAndCompletionClearWait() {
        let f = ActivityStoreFixture(); defer { f.remove() }
        f.record(F.hook("codex", "PermissionRequest"))
        f.record(F.hook("codex", "PreModelRequest", now: F.now + 1))
        #expect(f.selected()?.state == .running)
        f.record(F.hook("codex", "Stop", now: F.now + 2))
        #expect(f.selected()?.state == .completed)
    }

    @Test func sessionEndClearsAllTurns() {
        let f = ActivityStoreFixture(); defer { f.remove() }
        f.record(F.hook())
        f.record(F.hook("codex", "SessionEnd", now: F.now + 1, ["turn_id": NSNull()]))
        #expect(f.selected() == nil)
    }

    @Test func outOfOrderRejected() {
        let f = ActivityStoreFixture(); defer { f.remove() }
        f.record(F.hook("codex", "Stop", now: F.now))
        f.record(F.hook(now: F.now - 1))
        #expect(f.selected()?.state == .completed)
    }

    @Test func oldOtherTurnDoesNotResurrectAfterCompletion() {
        let f = ActivityStoreFixture(); defer { f.remove() }
        f.record(F.hook("codex", "Stop", now: F.now))
        f.record(F.hook(now: F.now - 1, ["turn_id": "earlier-turn"]))
        #expect(f.selected()?.state == .completed)
    }

    @Test func malformedEventFieldTypesFailClosed() throws {
        let f = ActivityStoreFixture(); defer { f.remove() }
        f.record(F.hook())
        var document = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: f.store.fileURL)) as? [String: Any])
        var rows = try #require(document["events"] as? [[String: Any]])
        rows[0]["state"] = ["unexpected": "object"]
        document["events"] = rows
        try JSONSerialization.data(withJSONObject: document).write(to: f.store.fileURL)
        #expect(f.store.read().isEmpty)
    }

    @Test func journalRowsAreStrictOneByOne() throws {
        let f = ActivityStoreFixture(); defer { f.remove() }
        f.record(F.hook())
        let document = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: f.store.fileURL)) as? [String: Any])
        let valid = try #require((document["events"] as? [[String: Any]])?.first)
        var extraKey = valid; extraKey["prompt"] = "text"
        var booleanTime = valid; booleanTime["observed_at"] = true
        var numericFlag = valid; numericFlag["clears_wait"] = 1
        var rawSession = valid; rawSession["session_id"] = "private-session-id"
        var badEvent = valid; badEvent["event"] = "Pre Tool Use"
        var minimal = valid; minimal["wait_token"] = nil; minimal["clears_wait"] = nil; minimal["turn_id"] = String(repeating: "b", count: 20)
        let rows: [Any] = [extraKey, booleanTime, numericFlag, rawSession, badEvent, NSNull(), valid, minimal]
        try JSONSerialization.data(withJSONObject: ["schema": 1, "events": rows]).write(to: f.store.fileURL)
        let read = f.store.read()
        #expect(read.count == 2)
        #expect(read.first?.state == .running)
        #expect(read.last?.waitToken == "" && read.last?.clearsWait == false)
        try JSONSerialization.data(withJSONObject: ["schema": true, "events": [valid]]).write(to: f.store.fileURL)
        #expect(f.store.read().isEmpty)
    }

    @Test func concurrentSessionsCount() {
        let f = ActivityStoreFixture(); defer { f.remove() }
        f.record(F.hook("codex", "PreToolUse", ["session_id": "one"]))
        f.record(F.hook("codex", "PreToolUse", ["session_id": "two"]))
        #expect(f.selected()?.activeCount == 2)
    }

    @Test func concurrentWritersNeverLoseAcceptedEvents() {
        let f = ActivityStoreFixture(); defer { f.remove() }
        final class Accepted: @unchecked Sendable {
            let lock = NSLock()
            var indices: [Int] = []
            func add(_ index: Int) { lock.lock(); indices.append(index); lock.unlock() }
        }
        let accepted = Accepted()
        DispatchQueue.concurrentPerform(iterations: 6) { index in
            if f.record(F.hook("codex", "PreToolUse", now: F.now + Double(index) / 10, ["session_id": "writer-\(index)"])) {
                accepted.add(index)
            }
        }
        let stored = Set(f.store.read().map(\.sessionID))
        #expect(!accepted.indices.isEmpty)
        for index in accepted.indices {
            #expect(stored.contains(ActivityNormalizer.opaque("codex:writer-\(index)")))
        }
    }

    @Test func journalCapacity() {
        let f = ActivityStoreFixture(); defer { f.remove() }
        for index in 0..<(ActivityLimits.maximumSessions + 3) {
            f.record(F.hook("codex", "PreToolUse", now: F.now + Double(index) / 100, ["session_id": String(index)]))
        }
        let events = f.store.read()
        #expect(events.count == ActivityLimits.maximumSessions)
        // The oldest observations are the ones dropped.
        #expect(events.map(\.observedAt).min() == F.now + 3.0 / 100)
    }

    @Test func symlinkStateAndLockRefused() throws {
        let f = ActivityStoreFixture(); defer { f.remove() }
        let outside = f.root.appendingPathComponent("outside")
        try Data("preserve".utf8).write(to: outside)
        try FileManager.default.createDirectory(at: f.path, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: f.store.fileURL, withDestinationURL: outside)
        #expect(f.store.read().isEmpty)
        // Atomic replacement replaces the link, never the target.
        #expect(f.record(F.hook()))
        #expect(try String(contentsOf: outside, encoding: .utf8) == "preserve")
        try FileManager.default.removeItem(at: f.store.lockURL)
        try FileManager.default.createSymbolicLink(at: f.store.lockURL, withDestinationURL: outside)
        #expect(!f.record(F.hook()))
        #expect(try String(contentsOf: outside, encoding: .utf8) == "preserve")
    }

    @Test func linkedStateDirectoryRefused() throws {
        let f = ActivityStoreFixture(); defer { f.remove() }
        let real = f.root.appendingPathComponent("real")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: f.path, withDestinationURL: real)
        #expect(!f.record(F.hook()))
        #expect(F.contents(real).isEmpty)
    }

    @Test func invalidJournalRowsAndFutureEventsIgnored() throws {
        let f = ActivityStoreFixture(); defer { f.remove() }
        f.record(F.hook(now: F.now + 500))
        #expect(f.selected() == nil)
        try Data(#"{"schema":1,"events":[{"provider":"bad"},null]}"#.utf8).write(to: f.store.fileURL)
        #expect(f.store.read().isEmpty)
    }

    @Test func oversizedJournalIgnored() throws {
        let f = ActivityStoreFixture(); defer { f.remove() }
        f.record(F.hook())
        var data = try Data(contentsOf: f.store.fileURL)
        data.append(Data(repeating: 32, count: ActivityLimits.maximumStateBytes))
        try data.write(to: f.store.fileURL)
        #expect(f.store.read().isEmpty)
    }

    @Test func selectionPrefersPriorityThenRecency() {
        let f = ActivityStoreFixture(); defer { f.remove() }
        f.record(F.hook("codex", "PreToolUse", now: F.now))
        f.record(F.hook("cursor", "postToolUse", now: F.now + 1))
        #expect(f.selected(F.now + 1)?.provider == .cursor)
        f.record(F.hook("claude", "Stop", now: F.now + 2))
        let rows = f.rows(F.now + 2)
        #expect(rows.map(\.provider) == [.codex, .claude, .cursor])
        #expect(rows[1].state == .completed && rows[1].activeCount == 0)
        #expect(ActivityCollector.selected(rows)?.provider == .cursor)
    }
}
