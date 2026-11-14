// Ported from AMG65 Studio's activity.py (CodexLogTail); see THIRD_PARTY_NOTICES.md.
import Darwin
import Foundation

/// Reads only new lifecycle records of recent Codex rollout logs: today's and yesterday's directories,
/// at most 2,048 entries each, eight recently modified files, 256 KiB and 2,048 records per file per poll.
/// No recursive scan; the logs are never written.
final class CodexLogTail {
    let home: URL
    private var offsets: [String: (device: dev_t, inode: ino_t, offset: Int)] = [:]
    private var turns: [String: String] = [:]
    private var skipPartial: Set<String> = []

    init(home: URL = CodexLogTail.defaultHome) {
        self.home = home
    }

    /// `$CODEX_HOME`, else `~/.codex`.
    static var defaultHome: URL {
        if let path = ProcessInfo.processInfo.environment["CODEX_HOME"], !path.isEmpty { return URL(fileURLWithPath: path) }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
    }

    /// `YYYY/MM/DD` of the local calendar day `daysBack` days before `time`.
    static func dayPath(_ time: TimeInterval, daysBack: Int32 = 0) -> String? {
        var seconds = time_t(time.rounded(.down))
        var parts = tm()
        guard localtime_r(&seconds, &parts) != nil else { return nil }
        if daysBack != 0 {
            parts.tm_mday -= daysBack
            parts.tm_hour = 12; parts.tm_min = 0; parts.tm_sec = 0; parts.tm_isdst = -1
            var shifted = mktime(&parts)
            guard shifted != -1, localtime_r(&shifted, &parts) != nil else { return nil }
        }
        return String(format: "%04d/%02d/%02d", Int(parts.tm_year) + 1900, Int(parts.tm_mon) + 1, Int(parts.tm_mday))
    }

    /// The most recently modified own regular `.jsonl` files of today and yesterday, newest first.
    func files(now: TimeInterval) -> [URL] {
        var found: [(modified: TimeInterval, path: String)] = []
        for daysBack: Int32 in [0, 1] {
            guard let day = Self.dayPath(now, daysBack: daysBack) else { continue }
            let directory = home.appendingPathComponent("sessions", isDirectory: true).appendingPathComponent(day).path
            guard let handle = opendir(directory) else { continue }
            defer { closedir(handle) }
            var index = 0
            while let entry = readdir(handle) {
                let name = withUnsafePointer(to: entry.pointee.d_name) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
                }
                if name == "." || name == ".." { continue }
                if index >= ActivityLimits.maximumDirectoryEntries { break }
                index += 1
                guard name.hasSuffix(".jsonl") else { continue }
                let path = directory + "/" + name
                var info = stat()
                guard lstat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, info.st_uid == getuid() else { continue }
                let modified = TimeInterval(info.st_mtimespec.tv_sec) + TimeInterval(info.st_mtimespec.tv_nsec) / 1e9
                if now - ActivityLimits.history <= modified && modified <= now + 5 { found.append((modified, path)) }
            }
        }
        return found.sorted { ($0.modified, $0.path) > ($1.modified, $1.path) }
            .prefix(ActivityLimits.maximumFiles).map { URL(fileURLWithPath: $0.path) }
    }

    /// The rollout session id from `…-<uuid>.jsonl`, else the file name.
    static func sessionName(_ name: String) -> String {
        let suffix = ".jsonl"
        guard name.hasSuffix(suffix) else { return name }
        let stem = Array(name.utf8.dropLast(suffix.utf8.count))
        guard stem.count >= 36 else { return name }
        let candidate = stem.suffix(36)
        let dashes: Set<Int> = [8, 13, 18, 23]
        for (offset, byte) in candidate.enumerated() {
            let valid = dashes.contains(offset)
                ? byte == 45 : (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte)
            if !valid { return name }
        }
        return String(decoding: candidate, as: UTF8.self)
    }

    func poll(now: TimeInterval) -> [ActivityEvent] {
        var events: [ActivityEvent] = []
        let paths = files(now: now)
        let active = Set(paths.map(\.path))
        offsets = offsets.filter { active.contains($0.key) }
        turns = turns.filter { active.contains($0.key) }
        skipPartial.formIntersection(active)
        for url in paths {
            let key = url.path
            let fd = open(key, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
            guard fd >= 0 else { continue }
            defer { close(fd) }
            var info = stat()
            guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, info.st_uid == getuid() else { continue }
            let size = Int(info.st_size)
            let old = offsets[key]
            let validOld = old.map { $0.device == info.st_dev && $0.inode == info.st_ino && $0.offset <= size } ?? false
            var start = validOld ? old!.offset : max(0, size - ActivityLimits.maximumTailBytes)
            if !validOld { turns[key] = nil }
            var lostPrefix = !validOld && start > 0
            if size - start > ActivityLimits.maximumTailBytes {
                start = size - ActivityLimits.maximumTailBytes
                lostPrefix = true
                turns[key] = nil
            }
            guard let data = PrivateIO.readRange(fd, offset: start, count: ActivityLimits.maximumTailBytes) else { continue }
            guard let boundary = data.lastIndex(of: 10) else {
                // Drop oversized lines instead of retaining prompts in memory.
                if data.count == ActivityLimits.maximumTailBytes {
                    offsets[key] = (info.st_dev, info.st_ino, start + data.count)
                    skipPartial.insert(key)
                }
                continue
            }
            offsets[key] = (info.st_dev, info.st_ino, start + boundary + 1)
            var lines = data[data.startIndex..<boundary].split(separator: 10, omittingEmptySubsequences: false)
            if lostPrefix || skipPartial.contains(key) {
                lines.removeFirst()
                skipPartial.remove(key)
            }
            let session = Self.sessionName(url.lastPathComponent)
            for line in lines.suffix(ActivityLimits.maximumRecordsPerFile) {
                if line.count > ActivityLimits.maximumInputBytes { continue }
                guard var record = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                      var payload = record["payload"] as? [String: Any] else { continue }
                if let turn = ActivityNormalizer.safeIdentifier(payload["turn_id"]) { turns[key] = turn }
                if record["type"] as? String == "response_item" {
                    // response_item has no turn_id; use an observed turn context. A bounded tail may begin
                    // mid-turn, so without one no identity is invented.
                    guard let turn = turns[key] else { continue }
                    payload["turn_id"] = turn
                    record["payload"] = payload
                }
                if let event = ActivityNormalizer.codexRecord(record, session: session, now: now) { events.append(event) }
            }
        }
        return events
    }
}
