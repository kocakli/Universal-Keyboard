// Ported from AMG65 Studio's activity.py; see THIRD_PARTY_NOTICES.md.
import Darwin
import Foundation

/// Atomic, user-only journal of current activity metadata (not an event history). Written by the hook
/// receiver in the `keymapper-usage` helper, read by the app.
public struct ActivityStore: Sendable {
    public let directory: URL
    public var fileURL: URL { directory.appendingPathComponent("activity.json") }
    var lockURL: URL { directory.appendingPathComponent("activity.lock") }

    public init(directory: URL = ActivityStore.defaultDirectory) {
        self.directory = directory
    }

    /// `~/Library/Application Support/KeyMapper/activity/` (directory 0700, `activity.json` 0600).
    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KeyMapper", isDirectory: true).appendingPathComponent("activity", isDirectory: true)
    }

    struct Unsafe: Error {}

    /// Valid current events; empty for a missing, foreign, oversized, linked or malformed journal.
    /// Each row is validated on its own, so one bad row drops only that row.
    func read() -> [ActivityEvent] {
        let fd = open(fileURL.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { return [] }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, info.st_uid == getuid(),
              info.st_size <= ActivityLimits.maximumStateBytes,
              let data = PrivateIO.readAll(fd, limit: ActivityLimits.maximumStateBytes),
              let document = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let schema = JSONValue.number(document["schema"]), schema == 1,
              let rows = document["events"] as? [Any] else { return [] }
        return rows.prefix(ActivityLimits.maximumSessions).compactMap { ActivityEvent(row: $0) }
    }

    /// Merges one event under the process lock and atomically replaces the journal. False on any failure.
    @discardableResult
    func record(_ event: ActivityEvent) -> Bool {
        guard event.isWellFormed else { return false }
        return (try? withLock { () -> Bool in
            var events = ActivityEvents()
            for old in read() where old.observedAt >= event.observedAt - ActivityLimits.history { events.set(old) }
            events.merge(event)
            let document: [String: Any] = ["schema": 1, "events": events.values.map(\.row)]
            guard let data = try? JSONSerialization.data(withJSONObject: document, options: [.sortedKeys]),
                  data.count <= ActivityLimits.maximumStateBytes else { return false }
            return PrivateIO.replace(fileURL, with: data, temporaryPrefix: ".activity-", mode: 0o600)
        }) ?? false
    }

    private func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        var info = stat()
        guard lstat(directory.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR, info.st_uid == getuid(),
              chmod(directory.path, 0o700) == 0 else { throw Unsafe() }
    }

    /// Bounded exclusive lock (0.15 s) on a regular user-owned lock file; a linked lock file is refused.
    private func withLock<T>(_ body: () throws -> T) throws -> T {
        try prepareDirectory()
        let fd = open(lockURL.path, O_RDWR | O_CREAT | O_NOFOLLOW | O_NONBLOCK, 0o600)
        guard fd >= 0 else { throw Unsafe() }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, info.st_uid == getuid(),
              fchmod(fd, 0o600) == 0 else { throw Unsafe() }
        let deadline = ProcessInfo.processInfo.systemUptime + 0.15
        while flock(fd, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EWOULDBLOCK || errno == EINTR, ProcessInfo.processInfo.systemUptime < deadline else { throw Unsafe() }
            usleep(10_000)
        }
        return try body()
    }
}

/// Small POSIX helpers shared by the activity journal, the Codex log tail and the hook installer.
enum PrivateIO {
    /// Reads to end of file; nil on an error or when more than `limit` bytes arrive.
    static func readAll(_ fd: Int32, limit: Int) -> Data? {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let count = Darwin.read(fd, &buffer, min(buffer.count, limit + 1 - data.count))
            if count == 0 { return data }
            if count < 0 { if errno == EINTR { continue }; return nil }
            data.append(contentsOf: buffer.prefix(count))
            if data.count > limit { return nil }
        }
    }

    /// Up to `count` bytes starting at `offset` (fewer at end of file); nil on an error.
    static func readRange(_ fd: Int32, offset: Int, count: Int) -> Data? {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while data.count < count {
            let got = pread(fd, &buffer, min(buffer.count, count - data.count), off_t(offset + data.count))
            if got == 0 { break }
            if got < 0 { if errno == EINTR { continue }; return nil }
            data.append(contentsOf: buffer.prefix(got))
        }
        return data
    }

    static func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { raw in
            var written = 0
            while written < raw.count {
                let count = Darwin.write(fd, raw.baseAddress! + written, raw.count - written)
                if count < 0 { if errno == EINTR { continue }; return false }
                written += count
            }
            return true
        }
    }

    /// Writes a new file next to `url` with `mode`, syncs it and returns its path; the caller renames or unlinks it.
    static func temporaryFile(beside url: URL, prefix: String, data: Data, mode: mode_t) -> String? {
        var template = Array((url.deletingLastPathComponent().path + "/" + prefix + "XXXXXX").utf8CString)
        let fd = template.withUnsafeMutableBufferPointer { mkstemp($0.baseAddress!) }
        guard fd >= 0 else { return nil }
        let path = String(cString: template)
        let ok = fchmod(fd, mode) == 0 && writeAll(fd, data) && fsync(fd) == 0
        close(fd)
        guard ok else { unlink(path); return nil }
        return path
    }

    /// Atomic replacement: the destination (even a symbolic link) is replaced, never followed.
    static func replace(_ url: URL, with data: Data, temporaryPrefix: String, mode: mode_t) -> Bool {
        guard let temporary = temporaryFile(beside: url, prefix: temporaryPrefix, data: data, mode: mode) else { return false }
        guard rename(temporary, url.path) == 0 else { unlink(temporary); return false }
        return true
    }
}
