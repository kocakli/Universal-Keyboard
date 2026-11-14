// Ported from AMG65 Studio's activity_hooks.py (receiver); see THIRD_PARTY_NOTICES.md.
import Darwin
import Foundation

/// Passive agent hook receiver: `keymapper-usage hook --provider <codex|claude|cursor> [--state-dir <absolute path>]`.
/// Reads bounded JSON from stdin, records only fixed codes and opaque ids, and always answers `{}` with exit
/// status 0. It cannot approve, deny, answer, continue, rewrite input, inject prompts or use the network.
public enum ActivityHookReceiver {
    public static let response = Data("{}\n".utf8)

    /// Runs the receiver and exits; observation failures never change the agent's permission or completion.
    public static func main(arguments: [String]) -> Never {
        signal(SIGPIPE, SIG_IGN)
        let output = run(arguments: arguments)
        _ = PrivateIO.writeAll(STDOUT_FILENO, output)
        exit(0)
    }

    static func run(arguments: [String], input: Int32 = STDIN_FILENO,
                    environment: [String: String] = ProcessInfo.processInfo.environment) -> Data {
        // A dedicated account sign-in is not an agent job (AMG65 Studio marks its sign-in processes).
        guard environment["AMG65_STUDIO_AUTH_FLOW"] != "1", let (provider, directory) = options(arguments) else {
            return response
        }
        // Receipt time is captured before reading; payloads never supply timestamps.
        let now = Date().timeIntervalSince1970
        if let payload = readPayload(input), let event = ActivityNormalizer.hook(provider: provider.rawValue, payload: payload, now: now) {
            ActivityStore(directory: directory).record(event)
        }
        return response
    }

    /// `--provider` (required) and `--state-dir` (absolute, optional), each once; nil for anything else.
    static func options(_ arguments: [String]) -> (ActivityProvider, URL)? {
        guard arguments.count % 2 == 0 else { return nil }
        var values: [String: String] = [:]
        for index in stride(from: 0, to: arguments.count, by: 2) {
            let name = arguments[index]
            guard ["--provider", "--state-dir"].contains(name), values[name] == nil else { return nil }
            values[name] = arguments[index + 1]
        }
        guard let provider = values["--provider"].flatMap(ActivityProvider.init(rawValue:)) else { return nil }
        guard let path = values["--state-dir"] else { return (provider, ActivityStore.defaultDirectory) }
        guard path.hasPrefix("/") else { return nil }
        return (provider, URL(fileURLWithPath: path, isDirectory: true))
    }

    /// At most 256 KiB within `timeout` seconds, even if the caller leaves stdin open; parsed only at end of input.
    static func readPayload(_ fd: Int32, timeout: TimeInterval = 0.5) -> [String: Any]? {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { return nil }
            var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, Int32((remaining * 1000).rounded(.up)))
            if ready < 0 { if errno == EINTR { continue }; return nil }
            if ready == 0 { return nil }
            let count = Darwin.read(fd, &buffer, min(buffer.count, ActivityLimits.maximumInputBytes + 1 - data.count))
            if count < 0 { if errno == EINTR || errno == EAGAIN { continue }; return nil }
            if count == 0 { return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] }
            data.append(contentsOf: buffer.prefix(count))
            if data.count > ActivityLimits.maximumInputBytes { return nil }
        }
    }
}
