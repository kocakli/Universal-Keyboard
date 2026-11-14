// Ported from AMG65 Studio's activity.py; see THIRD_PARTY_NOTICES.md.
import CoreFoundation
import CryptoKit
import Foundation

/// AI tools whose agent activity is observed. The declaration order breaks selection ties.
public enum ActivityProvider: String, CaseIterable, Codable, Sendable {
    case codex, claude, cursor
}

/// Observed agent state. `unknown` means no fresh supported observation, never "idle" or "finished".
public enum ActivityState: String, CaseIterable, Codable, Sendable {
    case unknown, queued, running
    case waitingApproval = "waiting_approval"
    case waitingInput = "waiting_input"
    case completed, error

    /// Freshness limit after the last qualifying event, in seconds; not an estimate of task duration.
    public var lifetime: TimeInterval {
        switch self {
        case .unknown: 0
        case .queued: 30
        case .running: 120
        case .waitingApproval, .waitingInput: 300
        case .completed: 45
        case .error: 90
        }
    }

    /// Selection order: approval, input, error, running, queued, completed.
    public var priority: Int {
        switch self {
        case .unknown: 0
        case .completed: 1
        case .queued: 2
        case .running: 3
        case .error: 4
        case .waitingInput: 5
        case .waitingApproval: 6
        }
    }

    var isWaiting: Bool { self == .waitingApproval || self == .waitingInput }
}

/// Fixed label codes for the app to localise; never model-generated text.
public enum ActivitySummary: String, CaseIterable, Codable, Sendable {
    case unknown
    case promptSubmitted = "prompt_submitted"
    case working
    case usingTool = "using_tool"
    case runningCommand = "running_command"
    case readingFiles = "reading_files"
    case editingFiles = "editing_files"
    case searching
    case approvalRequested = "approval_requested"
    case inputRequested = "input_requested"
    case inputReceived = "input_received"
    case completed
    case toolFailed = "tool_failed"
    case failed, interrupted
    case sessionEnded = "session_ended"
    case compacting
}

public enum ActivitySource: String, Codable, Sendable {
    case hook
    case codexLog = "codex_log"
}

enum ActivityLimits {
    static let maximumInputBytes = 256 * 1024
    static let maximumStateBytes = 128 * 1024
    static let maximumSessions = 64
    static let maximumTailBytes = 256 * 1024
    static let maximumFiles = 8
    static let maximumRecordsPerFile = 2048
    static let maximumDirectoryEntries = 2048
    /// Merge horizon: older observations are dropped.
    static let history: TimeInterval = 600
}

/// One observation. Holds only fixed codes, event names and opaque SHA-256-prefix identities.
struct ActivityEvent: Equatable, Sendable {
    let provider: ActivityProvider
    let sessionID: String
    let turnID: String
    let state: ActivityState
    var summary: ActivitySummary
    let observedAt: TimeInterval
    let source: ActivitySource
    let event: String
    var waitToken = ""
    var clearsWait = false

    var key: String { "\(provider.rawValue):\(sessionID):\(turnID)" }

    static let terminalEvents: Set<String> = ["SessionEnd", "sessionEnd", "task_complete", "Stop"]

    /// The checks of Studio's `_valid_event` that the enum-typed fields don't already guarantee.
    var isWellFormed: Bool {
        observedAt.isFinite && Self.isOpaque(sessionID) && Self.isOpaque(turnID)
            && (waitToken.isEmpty || Self.isOpaque(waitToken)) && Self.isEventName(event)
    }

    static func isOpaque(_ value: String) -> Bool {
        value.utf8.count == 20 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    static func isEventName(_ value: String) -> Bool {
        (1...40).contains(value.utf8.count)
            && value.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0) || $0 == 95 }
    }

    /// Strict journal row: exactly the known keys, exact JSON types (a Boolean is not a number), else nil.
    init?(row: Any) {
        guard let row = row as? [String: Any] else { return nil }
        let required = ["provider", "session_id", "turn_id", "state", "summary", "observed_at", "source", "event"]
        guard Set(row.keys).isSubset(of: required + ["wait_token", "clears_wait"]),
              required.allSatisfy({ row[$0] != nil }),
              let provider = (row["provider"] as? String).flatMap(ActivityProvider.init(rawValue:)),
              let state = (row["state"] as? String).flatMap(ActivityState.init(rawValue:)),
              let summary = (row["summary"] as? String).flatMap(ActivitySummary.init(rawValue:)),
              let source = (row["source"] as? String).flatMap(ActivitySource.init(rawValue:)),
              let observedAt = JSONValue.number(row["observed_at"]),
              let session = row["session_id"] as? String, let turn = row["turn_id"] as? String,
              let event = row["event"] as? String else { return nil }
        var waitToken = ""
        if let value = row["wait_token"] {
            guard let token = value as? String else { return nil }
            waitToken = token
        }
        var clearsWait = false
        if let value = row["clears_wait"] {
            guard let flag = value as? NSNumber, CFGetTypeID(flag) == CFBooleanGetTypeID() else { return nil }
            clearsWait = flag.boolValue
        }
        self.init(provider: provider, sessionID: session, turnID: turn, state: state, summary: summary,
                  observedAt: observedAt, source: source, event: event, waitToken: waitToken, clearsWait: clearsWait)
        guard isWellFormed else { return nil }
    }

    init(provider: ActivityProvider, sessionID: String, turnID: String, state: ActivityState, summary: ActivitySummary,
         observedAt: TimeInterval, source: ActivitySource, event: String, waitToken: String = "", clearsWait: Bool = false) {
        self.provider = provider; self.sessionID = sessionID; self.turnID = turnID; self.state = state
        self.summary = summary; self.observedAt = observedAt; self.source = source; self.event = event
        self.waitToken = waitToken; self.clearsWait = clearsWait
    }

    var row: [String: Any] {
        ["provider": provider.rawValue, "session_id": sessionID, "turn_id": turnID, "state": state.rawValue,
         "summary": summary.rawValue, "observed_at": observedAt, "source": source.rawValue, "event": event,
         "wait_token": waitToken, "clears_wait": clearsWait]
    }
}

/// Maps documented hook events and versioned Codex rollout records to fixed codes. All other content
/// (prompts, commands, paths, tool arguments and results, messages) is ignored.
enum ActivityNormalizer {
    static let toolLabels: [String: ActivitySummary] = [
        "Bash": .runningCommand, "Shell": .runningCommand, "exec_command": .runningCommand,
        "Read": .readingFiles, "ReadFile": .readingFiles, "read_file": .readingFiles,
        "Edit": .editingFiles, "Write": .editingFiles, "apply_patch": .editingFiles,
        "Grep": .searching, "Glob": .searching, "WebSearch": .searching, "web_search": .searching,
    ]
    static let inputTools: Set<String> = ["AskUserQuestion", "request_user_input", "request_user_input_async"]

    /// Stable opaque identity; original IDs and paths never leave memory.
    static func opaque(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).prefix(10).map { String(format: "%02x", $0) }.joined()
    }

    static func safeIdentifier(_ value: Any?) -> String? {
        guard let value = value as? String, (1...512).contains(value.unicodeScalars.count) else { return nil }
        return value
    }

    static func make(_ provider: ActivityProvider, session: String, turn: String?, state: ActivityState,
                     summary: ActivitySummary, at time: TimeInterval, source: ActivitySource, event: String,
                     waitToken: String?, clearsWait: Bool) -> ActivityEvent {
        ActivityEvent(provider: provider, sessionID: opaque(provider.rawValue + ":" + session), turnID: opaque(turn ?? session),
                      state: state, summary: summary, observedAt: time, source: source, event: event,
                      waitToken: waitToken.map(opaque) ?? "", clearsWait: clearsWait)
    }

    /// A hook payload from Codex, Claude Code or Cursor; nil for anything not documented.
    static func hook(provider name: String, payload: Any?, now: TimeInterval) -> ActivityEvent? {
        guard let provider = ActivityProvider(rawValue: name), let payload = payload as? [String: Any],
              let session = safeIdentifier(payload[provider == .cursor ? "conversation_id" : "session_id"]) else { return nil }
        let turn = safeIdentifier(payload[provider == .cursor ? "generation_id" : "turn_id"])
        guard let kind = payload["hook_event_name"] as? String else { return nil }
        // Subagent lifecycle events describe another worker, not the parent's completion.
        if ["SubagentStart", "SubagentStop", "subagentStart", "subagentStop"].contains(kind) { return nil }
        let tool = payload["tool_name"] as? String
        let label = tool.flatMap { toolLabels[$0] } ?? .usingTool
        let token = safeIdentifier(payload["tool_use_id"])
        var result: (state: ActivityState, summary: ActivitySummary, clears: Bool)?
        if provider == .codex || provider == .claude {
            if kind == "UserPromptSubmit" { result = (.queued, .promptSubmitted, true) }
            else if kind == "PreModelRequest" || kind == "PostModelRequest", provider == .codex {
                result = kind == "PostModelRequest" && payload["status"] as? String == "failed"
                    ? (.error, .failed, true) : (.running, .working, true)
            }
            else if kind == "PreToolUse" {
                result = tool.map(inputTools.contains) == true ? (.waitingInput, .inputRequested, false) : (.running, label, false)
            }
            else if kind == "PostToolUse" { result = (.running, label, false) }
            else if kind == "PermissionRequest" { result = (.waitingApproval, .approvalRequested, false) }
            else if kind == "PostToolUseFailure", provider == .claude { result = (.error, .toolFailed, false) }
            else if kind == "Stop" { result = (.completed, .completed, true) }
            else if kind == "StopFailure", provider == .claude { result = (.error, .failed, true) }
            else if kind == "Interrupt", provider == .codex { result = (.unknown, .interrupted, true) }
            else if kind == "SessionEnd" { result = (.unknown, .sessionEnded, true) }
            else if kind == "PreCompact" { result = (.running, .compacting, false) }
            else if kind == "Elicitation", provider == .claude { result = (.waitingInput, .inputRequested, false) }
            else if kind == "ElicitationResult", provider == .claude { result = (.running, .inputReceived, true) }
            else if kind == "Notification", provider == .claude {
                guard let notification = payload["notification_type"] as? String else { return nil }
                if notification == "permission_prompt" { result = (.waitingApproval, .approvalRequested, false) }
                else if ["elicitation_dialog", "elicitation_url_dialog", "agent_needs_input", "quota_auto_resume_stale"]
                    .contains(notification) { result = (.waitingInput, .inputRequested, false) }
                else if ["elicitation_complete", "elicitation_response"].contains(notification) {
                    result = (.running, .inputReceived, true)
                }
                // idle_prompt and agent_completed are deliberately ignored: idle is not a question, and
                // agent_completed does not distinguish success from failure.
            }
        } else {
            if kind == "beforeSubmitPrompt" { result = (.queued, .promptSubmitted, true) }
            else if kind == "preToolUse" || kind == "postToolUse" { result = (.running, label, false) }
            else if kind == "postToolUseFailure" { result = (.error, .toolFailed, false) }
            else if kind == "afterAgentResponse" { result = (.running, .working, false) }
            else if kind == "preCompact" { result = (.running, .compacting, false) }
            else if kind == "stop" {
                switch payload["status"] as? String {
                case "completed": result = (.completed, .completed, true)
                case "error": result = (.error, .failed, true)
                case "aborted": result = (.unknown, .interrupted, true)
                default: break
                }
            }
            else if kind == "sessionEnd" { result = (.unknown, .sessionEnded, true) }
        }
        guard let result else { return nil }
        return make(provider, session: session, turn: turn, state: result.state, summary: result.summary, at: now,
                    source: .hook, event: kind, waitToken: token, clearsWait: result.clears)
    }

    static let codexItemLabels: [String: ActivitySummary] = [
        "Reasoning": .working, "CommandExecution": .runningCommand, "FileChange": .editingFiles,
        "WebSearch": .searching, "McpToolCall": .usingTool, "ContextCompaction": .compacting,
    ]

    /// Best-effort versioned rollout metadata. Unknown record shapes stay unknown.
    static func codexRecord(_ record: Any?, session: String, now: TimeInterval) -> ActivityEvent? {
        guard let record = record as? [String: Any], let at = eventTime(record["timestamp"]),
              !(at > now + 5 || at < now - ActivityLimits.history),
              let payload = record["payload"] as? [String: Any], let kind = payload["type"] as? String else { return nil }
        let turn = safeIdentifier(payload["turn_id"])
        var result: (state: ActivityState, summary: ActivitySummary, clears: Bool)?
        var token: String?
        let type = record["type"] as? String
        if type == "event_msg" {
            if kind == "task_started" { result = (.running, .working, true) }
            else if kind == "task_complete" { result = (.completed, .completed, true) }
            else if kind == "turn_aborted" { result = (.unknown, .interrupted, true) }
            else if kind == "item_completed" {
                guard let item = payload["item"] as? [String: Any], let itemType = item["type"] as? String else { return nil }
                if let label = codexItemLabels[itemType] { result = (.running, label, false) }
            }
        } else if type == "response_item" {
            // Only tool lifecycle metadata is observed, never arguments, output or reasoning.
            if kind == "function_call" || kind == "custom_tool_call" {
                guard let name = payload["name"] as? String else { return nil }
                result = inputTools.contains(name) ? (.waitingInput, .inputRequested, false)
                    : (.running, toolLabels[name] ?? .usingTool, false)
                token = safeIdentifier(payload["call_id"])
            } else if kind == "function_call_output" || kind == "custom_tool_call_output" {
                result = (.running, .usingTool, false)
                token = safeIdentifier(payload["call_id"])
            }
        }
        guard let result else { return nil }
        return make(.codex, session: session, turn: turn, state: result.state, summary: result.summary, at: at,
                    source: .codexLog, event: kind, waitToken: token, clearsWait: result.clears)
    }

    /// ISO 8601 date-time with an explicit zone (Python `datetime.fromisoformat` subset); naive times are rejected.
    static func eventTime(_ value: Any?) -> TimeInterval? {
        guard let text = value as? String, text.unicodeScalars.count <= 48 else { return nil }
        let bytes = Array(text.utf8)
        var index = 0
        func digits(_ count: Int) -> Int? {
            guard index + count <= bytes.count else { return nil }
            var number = 0
            for byte in bytes[index..<index + count] {
                guard (48...57).contains(byte) else { return nil }
                number = number * 10 + Int(byte - 48)
            }
            index += count
            return number
        }
        func expect(_ byte: UInt8) -> Bool {
            guard index < bytes.count, bytes[index] == byte else { return false }
            index += 1
            return true
        }
        guard let year = digits(4), expect(45), let month = digits(2), expect(45), let day = digits(2),
              index < bytes.count, bytes[index] == 84 || bytes[index] == 32 else { return nil }
        index += 1
        guard let hour = digits(2), expect(58), let minute = digits(2) else { return nil }
        var second = 0, micro = 0
        if expect(58) {
            guard let value = digits(2) else { return nil }
            second = value
            if index < bytes.count, bytes[index] == 46 || bytes[index] == 44 {
                index += 1
                let start = index
                while index < bytes.count, (48...57).contains(bytes[index]) { index += 1 }
                guard index > start else { return nil }
                let fraction = bytes[start..<min(index, start + 6)].map { Int($0 - 48) }
                micro = fraction.reduce(0) { $0 * 10 + $1 } * Int(pow(10, Double(6 - fraction.count)))
            }
        }
        var offset = 0
        guard index < bytes.count else { return nil }
        if bytes[index] == 90 {
            index += 1
        } else if bytes[index] == 43 || bytes[index] == 45 {
            let sign = bytes[index] == 45 ? -1 : 1
            index += 1
            guard let hours = digits(2) else { return nil }
            var minutes = 0
            if index < bytes.count {
                _ = expect(58)
                guard let value = digits(2) else { return nil }
                minutes = value
            }
            guard hours < 24, minutes < 60 else { return nil }
            offset = sign * (hours * 3600 + minutes * 60)
        } else {
            return nil
        }
        guard index == bytes.count, (1...12).contains(month), (1...31).contains(day), hour < 24, minute < 60, second < 60 else {
            return nil
        }
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day
        components.hour = hour; components.minute = minute; components.second = second
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = calendar.date(from: components),
              calendar.component(.day, from: date) == day else { return nil }
        let seconds = Int64(date.timeIntervalSince1970.rounded()) - Int64(offset)
        return Double(seconds * 1_000_000 + Int64(micro)) / 1_000_000
    }
}

/// Current events keyed by provider/session/turn, in insertion order (the order Studio's Python dict kept,
/// which decides ties when trimming and selecting).
struct ActivityEvents: Equatable {
    private(set) var values: [ActivityEvent] = []

    subscript(key: String) -> ActivityEvent? { values.first { $0.key == key } }

    /// Replaces an event with the same key in place, or appends.
    mutating func set(_ event: ActivityEvent) {
        if let index = values.firstIndex(where: { $0.key == event.key }) { values[index] = event } else { values.append(event) }
    }

    mutating func removeAll(where shouldRemove: (ActivityEvent) -> Bool) { values.removeAll(where: shouldRemove) }

    /// Studio's `_merge`: out-of-order rejection, matching tool-result category, no resurrection after an end,
    /// wait clearing, session end and the session cap.
    mutating func merge(_ incoming: ActivityEvent) {
        var incoming = incoming
        let old = self[incoming.key]
        if let old, old.observedAt > incoming.observedAt { return }
        // Codex output records omit the tool name. Keep an observed category only for the exact matching
        // tool call; a generic or different call stays generic.
        let outputs: Set<String> = ["function_call_output", "custom_tool_call_output"]
        if let old, old.state == .running, incoming.state == .running, incoming.summary == .usingTool,
           outputs.contains(incoming.event),
           [.runningCommand, .readingFiles, .editingFiles, .searching].contains(old.summary),
           !old.waitToken.isEmpty, old.waitToken == incoming.waitToken {
            incoming.summary = old.summary
        }
        // A tail discovered after a hook must not resurrect an already-ended turn.
        if values.contains(where: {
            $0.key != incoming.key && $0.provider == incoming.provider && $0.sessionID == incoming.sessionID
                && $0.observedAt >= incoming.observedAt && ActivityEvent.terminalEvents.contains($0.event)
        }) { return }
        if let old, old.state.isWaiting, incoming.state == .running, !incoming.clearsWait {
            let matchingResult = (["PostToolUse", "postToolUse"] as Set).union(outputs).contains(incoming.event)
            if !(matchingResult && !old.waitToken.isEmpty && old.waitToken == incoming.waitToken),
               incoming.observedAt < old.observedAt + old.state.lifetime { return }
        }
        if ActivityEvent.terminalEvents.contains(incoming.event) {
            values.removeAll {
                $0.provider == incoming.provider && $0.sessionID == incoming.sessionID && $0.observedAt <= incoming.observedAt
            }
        }
        set(incoming)
        if values.count > ActivityLimits.maximumSessions {
            // Oldest first; equal times keep insertion order (a stable sort).
            let oldest = values.enumerated()
                .sorted { ($0.element.observedAt, $0.offset) < ($1.element.observedAt, $1.offset) }
                .prefix(values.count - ActivityLimits.maximumSessions).map(\.element.key)
            let dropped = Set(oldest)
            values.removeAll { dropped.contains($0.key) }
        }
    }
}
