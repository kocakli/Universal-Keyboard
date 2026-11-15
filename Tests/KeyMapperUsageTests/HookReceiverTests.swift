import Darwin
import Foundation
import Testing
@testable import KeyMapperUsage

@Suite struct HookReceiverTests {
    typealias F = ActivityFixtures

    /// Runs the receiver on a closed pipe carrying `input`, with a clean environment unless given one.
    private func receive(_ input: String, _ arguments: [String], environment: [String: String] = [:]) -> Data {
        var fds: [Int32] = [0, 0]
        precondition(pipe(&fds) == 0)
        _ = PrivateIO.writeAll(fds[1], Data(input.utf8))
        close(fds[1])
        defer { close(fds[0]) }
        return ActivityHookReceiver.run(arguments: arguments, input: fds[0], environment: environment)
    }

    @Test func receiverReturnsEmptyDecisionAndSanitizedState() throws {
        let root = F.temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let payload = #"{"session_id":"session","hook_event_name":"PermissionRequest","prompt":"DO NOT STORE ME"}"#
        let output = receive(payload, ["--provider", "claude", "--state-dir", root.path])
        #expect(output == Data("{}\n".utf8))
        let content = try String(contentsOf: root.appendingPathComponent("activity.json"), encoding: .utf8)
        #expect(!content.contains("DO NOT STORE ME"))
        #expect(!content.contains("\"session\""))
        #expect(content.contains("waiting_approval"))
    }

    @Test func signInProcessNeverBecomesAgentActivity() {
        let root = F.temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let output = receive(#"{"session_id":"login","hook_event_name":"UserPromptSubmit"}"#,
                             ["--provider", "claude", "--state-dir", root.path], environment: ["AMG65_STUDIO_AUTH_FLOW": "1"])
        #expect(output == Data("{}\n".utf8))
        #expect(F.contents(root).isEmpty)
    }

    @Test func invalidJSONNeverChangesAgentControl() {
        let root = F.temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        for input in ["{broken", "", "[]", #""text""#] {
            #expect(receive(input, ["--provider", "cursor", "--state-dir", root.path]) == Data("{}\n".utf8))
        }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("activity.json").path))
    }

    @Test func badArgumentsStillAnswerEmpty() {
        let root = F.temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let payload = #"{"session_id":"s","hook_event_name":"Stop"}"#
        let state = root.appendingPathComponent("state").path
        for arguments in [[], ["--provider"], ["--provider", "nope", "--state-dir", state], ["--provider", "claude", "--state-dir", "relative"],
                          ["--provider", "claude", "--provider", "codex", "--state-dir", state],
                          ["--provider", "claude", "--state-dir", state, "--extra", "x"], ["receive", "--provider", "claude"]] {
            #expect(receive(payload, arguments) == Data("{}\n".utf8))
        }
        #expect(F.contents(root).isEmpty)
        #expect(ActivityHookReceiver.options(["--state-dir", "/tmp/x", "--provider", "codex"])?.0 == .codex)
        #expect(ActivityHookReceiver.options(["--provider", "codex"])?.1 == ActivityStore.defaultDirectory)
    }

    @Test func inputTimeLimitEvenWithOpenPipe() {
        var fds: [Int32] = [0, 0]
        precondition(pipe(&fds) == 0)
        defer { close(fds[0]); close(fds[1]) }
        let start = ProcessInfo.processInfo.systemUptime
        #expect(ActivityHookReceiver.readPayload(fds[0], timeout: 0.03) == nil)
        #expect(ProcessInfo.processInfo.systemUptime - start < 0.5)
    }

    @Test func inputSizeLimit() {
        var fds: [Int32] = [0, 0]
        precondition(pipe(&fds) == 0)
        let writer = fds[1]
        _ = fcntl(writer, F_SETNOSIGPIPE, 1)
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            _ = PrivateIO.writeAll(writer, Data(repeating: UInt8(ascii: "x"), count: ActivityLimits.maximumInputBytes + 2))
            close(writer)
            done.signal()
        }
        #expect(ActivityHookReceiver.readPayload(fds[0]) == nil)
        close(fds[0])
        #expect(done.wait(timeout: .now() + 2) == .success)
    }

    @Test func boundedReadAcceptsAPayloadSentInPieces() {
        var fds: [Int32] = [0, 0]
        precondition(pipe(&fds) == 0)
        let writer = fds[1]
        DispatchQueue.global().async {
            _ = PrivateIO.writeAll(writer, Data(#"{"session_id":"#.utf8))
            usleep(20_000)
            _ = PrivateIO.writeAll(writer, Data(#""s","hook_event_name":"Stop"}"#.utf8))
            close(writer)
        }
        defer { close(fds[0]) }
        #expect(ActivityHookReceiver.readPayload(fds[0])?["hook_event_name"] as? String == "Stop")
    }

    /// The helper built next to this test bundle (`swift test` builds every target of the package).
    static var helperURL: URL? {
        var candidates = Bundle.allBundles.filter { $0.bundleURL.pathExtension == "xctest" }
            .map { $0.bundleURL.deletingLastPathComponent().appendingPathComponent("keymapper-usage") }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        candidates.append(root.appendingPathComponent(".build/debug/keymapper-usage"))
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    @Test(.enabled(if: HookReceiverTests.helperURL != nil, "keymapper-usage helper not built"))
    func bundledHelperAnswersEmptyAndRecordsOnlyCodes() throws {
        let root = F.temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let helper: URL = try #require(Self.helperURL)
        for (input, records) in [(#"{"session_id":"session","hook_event_name":"PermissionRequest","prompt":"DO NOT STORE ME"}"#, true),
                                 ("{broken", false)] {
            let state = root.appendingPathComponent(records ? "state" : "broken")
            let process = Process()
            process.executableURL = helper
            process.arguments = ["hook", "--provider", "claude", "--state-dir", state.path]
            process.environment = ["PATH": "/usr/bin:/bin"]
            let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
            process.standardInput = stdin; process.standardOutput = stdout; process.standardError = stderr
            try process.run()
            stdin.fileHandleForWriting.write(Data(input.utf8))
            try stdin.fileHandleForWriting.close()
            let output = stdout.fileHandleForReading.readDataToEndOfFile()
            let errors = stderr.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            #expect(process.terminationStatus == 0)
            #expect(output == Data("{}\n".utf8))
            #expect(errors.isEmpty)
            let journal = state.appendingPathComponent("activity.json")
            #expect(FileManager.default.fileExists(atPath: journal.path) == records)
            if records {
                let content = try String(contentsOf: journal, encoding: .utf8)
                #expect(!content.contains("DO NOT STORE ME") && content.contains("waiting_approval"))
                #expect(F.mode(journal) == 0o600 && F.mode(state) == 0o700)
            }
        }
    }
}
