import Darwin
import Foundation
import Testing
@testable import KeyMapperUsage

/// A fake `CODEX_HOME` in a temporary directory with one rollout log of today's session directory.
struct CodexHomeFixture {
    let home = ActivityFixtures.temporaryDirectory()
    let path: URL
    let tail: CodexLogTail

    init() {
        let day = CodexLogTail.dayPath(ActivityFixtures.now)!
        let directory = home.appendingPathComponent("sessions").appendingPathComponent(day)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        path = directory.appendingPathComponent("rollout-11111111-1111-1111-1111-111111111111.jsonl")
        tail = CodexLogTail(home: home)
    }

    /// Writes (or appends) and sets the modification time to the fixture's "now", like `os.utime`.
    func write(_ data: Data, append: Bool = false, to url: URL? = nil) {
        let target = url ?? path
        let fd = open(target.path, O_WRONLY | O_CREAT | (append ? O_APPEND : O_TRUNC), 0o600)
        precondition(fd >= 0)
        _ = PrivateIO.writeAll(fd, data)
        close(fd)
        var times = [timeval(tv_sec: Int(ActivityFixtures.now), tv_usec: 0), timeval(tv_sec: Int(ActivityFixtures.now), tv_usec: 0)]
        utimes(target.path, &times)
    }

    func remove() { try? FileManager.default.removeItem(at: home) }
}

@Suite struct CodexLogTailTests {
    typealias F = ActivityFixtures

    @Test func explicitStartCompleteAndIgnoreMessageText() {
        for (kind, state) in [("task_started", ActivityState.running), ("task_complete", .completed)] {
            let event = ActivityNormalizer.codexRecord(F.record(kind, ["last_agent_message": "SECRET"]), session: "session", now: F.now)
            #expect(event?.state == state)
            #expect(!String(describing: event).contains("SECRET"))
        }
        #expect(ActivityNormalizer.codexRecord(F.record("agent_message", ["message": "Need approval?"]), session: "session", now: F.now) == nil)
    }

    @Test func futureAncientInvalidAndUnknownSchemas() {
        let rows: [Any] = [F.record("task_started", at: F.now + 10), F.record("task_started", at: F.now - 700),
                           ["timestamp": "bad", "payload": [String: Any]()], [Any](),
                           F.record("approval_looking_but_undocumented")]
        for row in rows {
            #expect(ActivityNormalizer.codexRecord(row, session: "session", now: F.now) == nil)
        }
        #expect(ActivityNormalizer.codexRecord(F.record([Any]()), session: "session", now: F.now) == nil)
        #expect(ActivityNormalizer.codexRecord(F.record("item_completed", ["item": ["type": [String: Any]()]]),
                                               session: "session", now: F.now) == nil)
        #expect(ActivityNormalizer.codexRecord(F.record("item_completed", ["item": ["type": "CommandExecution"]]),
                                               session: "session", now: F.now)?.summary == .runningCommand)
    }

    @Test func incrementalNoReplayAndTruncate() {
        let f = CodexHomeFixture(); defer { f.remove() }
        f.write(F.line(F.record("task_started")))
        #expect(f.tail.poll(now: F.now).count == 1)
        #expect(f.tail.poll(now: F.now).isEmpty)
        f.write(F.line(F.record("task_complete", at: F.now + 1)), append: true)
        #expect(f.tail.poll(now: F.now + 1).first?.state == .completed)
        f.write(F.line(F.record("task_started", at: F.now + 2)))
        #expect(f.tail.poll(now: F.now + 2).first?.state == .running)
    }

    @Test func partialLinesOnlyProcessedAfterNewline() {
        let f = CodexHomeFixture(); defer { f.remove() }
        let data = F.line(F.record("task_started"))
        let split = data.count / 2
        f.write(data.prefix(split))
        #expect(f.tail.poll(now: F.now).isEmpty)
        f.write(data.suffix(from: split), append: true)
        #expect(f.tail.poll(now: F.now).count == 1)
    }

    @Test func largeLineIsSkippedTailIsBounded() {
        let f = CodexHomeFixture(); defer { f.remove() }
        var data = Data(repeating: UInt8(ascii: "x"), count: ActivityLimits.maximumTailBytes + 100)
        data.append(10)
        data.append(F.line(F.record("task_complete")))
        f.write(data)
        let events = f.tail.poll(now: F.now)
        #expect(events.count == 1)
        #expect(events.first?.state == .completed)
    }

    @Test func oversizedStreamAcrossPollsDoesNotParseLineSuffix() {
        let f = CodexHomeFixture(); defer { f.remove() }
        f.write(Data(repeating: UInt8(ascii: "x"), count: ActivityLimits.maximumTailBytes))
        #expect(f.tail.poll(now: F.now).isEmpty)
        f.write(F.line(F.record("task_started")) + F.line(F.record("task_complete")), append: true)
        #expect(f.tail.poll(now: F.now).map(\.state) == [.completed])
    }

    @Test func symlinkLogNotRead() throws {
        let f = CodexHomeFixture(); defer { f.remove() }
        let outside = f.home.appendingPathComponent("outside.jsonl")
        f.write(F.line(F.record("task_started")), to: outside)
        try FileManager.default.createSymbolicLink(at: f.path, withDestinationURL: outside)
        #expect(f.tail.poll(now: F.now).isEmpty)
    }

    @Test func oldOrForeignNamedFilesAreSkipped() {
        let f = CodexHomeFixture(); defer { f.remove() }
        let text = f.path.deletingLastPathComponent().appendingPathComponent("notes.txt")
        f.write(F.line(F.record("task_started")), to: text)
        #expect(f.tail.poll(now: F.now).isEmpty)
        f.write(F.line(F.record("task_started")))
        // Modified more than ten minutes before "now": not a recent rollout.
        #expect(f.tail.poll(now: F.now + 601).isEmpty)
    }

    @Test func toolContextAndExplicitInputCallID() {
        let f = CodexHomeFixture(); defer { f.remove() }
        let start = F.record("task_started")
        let call: [String: Any] = ["timestamp": start["timestamp"]!, "type": "response_item", "payload": [
            "type": "function_call", "name": "request_user_input", "call_id": "private-call", "arguments": "SECRET",
        ]]
        f.write(F.line(start) + F.line(call))
        let events = f.tail.poll(now: F.now)
        #expect(events.count == 2)
        #expect(events.last?.state == .waitingInput)
        #expect(events.first?.turnID == events.last?.turnID)
        #expect(!String(describing: events).contains("SECRET"))
        #expect(!String(describing: events).contains("private-call"))
        // The rollout file's UUID is the (hashed) session.
        #expect(events.first?.sessionID == ActivityNormalizer.opaque("codex:11111111-1111-1111-1111-111111111111"))
    }

    @Test func responseItemWithoutTurnContextIsNotInvented() {
        let f = CodexHomeFixture(); defer { f.remove() }
        let row: [String: Any] = ["timestamp": F.record("x")["timestamp"]!, "type": "response_item",
                                  "payload": ["type": "function_call", "name": "exec_command"]]
        f.write(F.line(row))
        #expect(f.tail.poll(now: F.now).isEmpty)
    }

    @Test func collectorReadsRealSourceClassWithoutWritingLog() throws {
        let f = CodexHomeFixture(); defer { f.remove() }
        let original = F.line(F.record("task_started"))
        f.write(original)
        let state = f.home.appendingPathComponent("state")
        let collector = ActivityCollector(stateDirectory: state, codexHome: f.home)
        let selected = ActivityCollector.selected(collector.snapshot(now: Date(timeIntervalSince1970: F.now)))
        #expect(selected?.source == .codexLog)
        #expect(selected?.state == .running)
        #expect(try Data(contentsOf: f.path) == original)
        #expect(!FileManager.default.fileExists(atPath: state.path))
    }

    @Test func logsArePolledAtMostEveryTwoSeconds() {
        let f = CodexHomeFixture(); defer { f.remove() }
        f.write(F.line(F.record("task_started")))
        let collector = ActivityCollector(stateDirectory: f.home.appendingPathComponent("state"), codexHome: f.home)
        func state(_ now: TimeInterval) -> ActivityState? {
            ActivityCollector.selected(collector.snapshot(now: Date(timeIntervalSince1970: now)))?.state
        }
        #expect(state(F.now) == .running)
        f.write(F.line(F.record("task_complete", at: F.now + 1)), append: true)
        #expect(state(F.now + 1) == .running)
        #expect(state(F.now + 2) == .completed)
    }

    @Test func dayDirectoriesAreLocalTodayAndYesterday() {
        #expect(CodexLogTail.dayPath(F.now)?.count == 10)
        let today = CodexLogTail.dayPath(F.now)!
        let yesterday = CodexLogTail.dayPath(F.now, daysBack: 1)!
        #expect(yesterday < today)
        #expect(CodexLogTail.dayPath(F.now - 86_400 * 3, daysBack: 0)! < yesterday)
    }

    @Test func sessionNameIsTheRolloutUUID() {
        #expect(CodexLogTail.sessionName("rollout-2026-11-07T08-00-00-0199aBcD-1111-2222-3333-444455556666.jsonl")
                == "0199aBcD-1111-2222-3333-444455556666")
        #expect(CodexLogTail.sessionName("rollout.jsonl") == "rollout.jsonl")
        #expect(CodexLogTail.sessionName("x-0199abcd-1111-2222-3333-44445555666g.jsonl") == "x-0199abcd-1111-2222-3333-44445555666g.jsonl")
    }

    @Test func eventTimesFollowPythonFromisoformat() {
        let cases: [(String, TimeInterval?)] = [
            ("2026-11-07T08:30:00Z", 1_794_040_200), ("2026-11-07T08:30:00.123Z", 1_794_040_200.123),
            ("2026-11-07 08:30:00+02:00", 1_794_033_000), ("2026-11-07T08:30Z", 1_794_040_200),
            ("2026-11-07T08:30:00.1234567Z", 1_794_040_200.123456), ("2026-11-07T08:30:00+0200", 1_794_033_000),
            ("2026-11-07T08:30:00+02", 1_794_033_000), ("2026-11-07T08:30:00.5+05:30", 1_794_020_400.5),
            ("2026-11-07T08:30:00", nil), ("2026-11-07", nil), ("2026-02-30T00:00:00Z", nil),
            ("2026-11-07T08:30:00Z" + String(repeating: " ", count: 40), nil), ("bad", nil),
        ]
        for (text, expected) in cases {
            #expect(ActivityNormalizer.eventTime(text) == expected, "\(text)")
        }
        #expect(ActivityNormalizer.eventTime(1_794_040_200) == nil)
        #expect(ActivityNormalizer.eventTime(F.isoformat(F.now + 0.5)) == F.now + 0.5)
    }
}
