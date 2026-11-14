// Ported from AMG65 Studio's activity.py (ActivityCollector); see THIRD_PARTY_NOTICES.md.
import Foundation

/// One provider's current activity as shown in the app and on the keyboard. `unknown` (or `stale`) is
/// missing information, never success. Times are seconds since 1970.
public struct ActivityRow: Equatable, Sendable {
    public let provider: ActivityProvider
    public let state: ActivityState
    public let summary: ActivitySummary
    /// The latest observation; nil when there is none within the last ten minutes.
    public let observedAt: TimeInterval?
    /// When that observation stops being fresh.
    public let expiresAt: TimeInterval?
    public let source: ActivitySource?
    /// Sessions currently queued, running or waiting.
    public let activeCount: Int
    /// The latest observation expired without a newer one.
    public let stale: Bool
}

/// Merges the hook journal with recent Codex rollout logs and derives one row per provider.
public final class ActivityCollector: @unchecked Sendable {
    let store: ActivityStore
    let logs: CodexLogTail?
    private let lock = NSLock()
    private var events = ActivityEvents()
    private var lastScan = -TimeInterval.infinity
    /// Codex rollout logs are polled at most this often.
    static let scanInterval: TimeInterval = 2

    /// `codexHome` nil means `$CODEX_HOME` or `~/.codex`; `scanCodex: false` reads only the hook journal.
    public init(stateDirectory: URL = ActivityStore.defaultDirectory, codexHome: URL? = nil, scanCodex: Bool = true) {
        store = ActivityStore(directory: stateDirectory)
        logs = scanCodex ? CodexLogTail(home: codexHome ?? CodexLogTail.defaultHome) : nil
    }

    /// Rows for codex, claude and cursor, in that order.
    public func snapshot(now date: Date = Date()) -> [ActivityRow] {
        lock.lock(); defer { lock.unlock() }
        let now = date.timeIntervalSince1970
        for event in store.read() where now - ActivityLimits.history <= event.observedAt && event.observedAt <= now + 5 {
            events.merge(event)
        }
        if let logs, now < lastScan || now - lastScan >= Self.scanInterval {
            lastScan = now
            let polled = logs.poll(now: now).enumerated()
                .sorted { ($0.element.observedAt, $0.offset) < ($1.element.observedAt, $1.offset) }
            for (_, event) in polled { events.merge(event) }
        }
        events.removeAll { $0.observedAt < now - ActivityLimits.history }
        let active: Set<ActivityState> = [.queued, .running, .waitingApproval, .waitingInput]
        return ActivityProvider.allCases.map { provider in
            let all = events.values.filter { $0.provider == provider }
            let fresh = all.filter { $0.state != .unknown && $0.observedAt + $0.state.lifetime > now }
            // `max(by:)` keeps the first of equal elements, like Python's max().
            let current = fresh.max { ($0.state.priority, $0.observedAt) < ($1.state.priority, $1.observedAt) }
            let latest = current ?? all.max { $0.observedAt < $1.observedAt }
            let state = current?.state ?? .unknown
            return ActivityRow(provider: provider, state: state, summary: state == .unknown ? .unknown : latest!.summary,
                               observedAt: latest?.observedAt, expiresAt: latest.map { $0.observedAt + $0.state.lifetime },
                               source: latest?.source,
                               activeCount: Set(fresh.filter { active.contains($0.state) }.map(\.sessionID)).count,
                               stale: latest.map { $0.state != .unknown } == true && state == .unknown)
        }
    }

    /// The row to show when one provider must be picked: approval, input, error, running, queued, completed;
    /// the most recent wins among equals. Nil when every provider is unknown.
    public static func selected(_ rows: [ActivityRow]) -> ActivityRow? {
        rows.filter { $0.state != .unknown }
            .max { ($0.state.priority, $0.observedAt ?? 0) < ($1.state.priority, $1.observedAt ?? 0) }
    }
}
