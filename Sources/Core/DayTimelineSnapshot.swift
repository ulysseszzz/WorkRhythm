import Foundation

/// Immutable, day-scoped view data. Filtering an hour never scans the full history.
public final class DayTimelineSnapshot {
    public let activity: DayActivity
    public let sessions: [Session]
    public let focuses: [FocusSession]
    public let previousAwayIntervals: [UUID: TimeInterval]
    public let now: Date
    public var range: DateInterval { activity.range }

    public init(day: Date, sessions: [Session], focuses: [FocusSession], now: Date,
                calendar: Calendar = .current) {
        self.now = now
        let range = calendar.dateInterval(of: .day, for: day)!
        self.sessions = DayActivity.records(sessions, in: range, now: now, includeIdle: true)
        self.focuses = focuses.filter { focus in
            focus.segments.contains {
                StatisticsService.overlap(start: $0.start, end: $0.end ?? focus.end ?? focus.pausedAt,
                                          range: range, now: now) > 0
            }
        }.sorted { $0.start > $1.start }
        activity = DayActivity(day: day, sessions: self.sessions, focuses: self.focuses, now: now, calendar: calendar)
        // Preserve the previous strictly earlier departure even if two records share a timestamp.
        var previous: Date?
        var currentGroup: Date?
        var intervals: [UUID: TimeInterval] = [:]
        let departures = sessions.filter {
            $0.kind == .away && $0.start >= range.start && $0.start < range.end && $0.start <= now
        }.sorted { $0.start < $1.start }
        for session in departures {
            if session.start != currentGroup {
                previous = currentGroup
                currentGroup = session.start
            }
            if let previous { intervals[session.id] = session.start.timeIntervalSince(previous) }
        }
        previousAwayIntervals = intervals
    }
    public func records(in interval: DateInterval, includeIdle: Bool) -> [Session] {
        sessions.filter {
            (includeIdle || $0.kind != .idle)
                && StatisticsService.overlap(start: $0.start, end: $0.end, range: interval, now: now) > 0
        }
    }
    public func focusRecords(in interval: DateInterval) -> [FocusSession] {
        focuses.filter { focus in
            focus.segments.contains {
                StatisticsService.overlap(start: $0.start, end: $0.end ?? focus.end ?? focus.pausedAt,
                                          range: interval, now: now) > 0
            }
        }
    }
}

/// Main-thread owned LRU. Historical days survive clock ticks; data edits invalidate all entries.
/// The loader is lazy, so cache hits do not copy or scan the ledger's history.
public final class DayTimelineCache {
    private struct Entry {
        let day: Date
        let calendar: Calendar
        let observedEnd: Date
        let snapshot: DayTimelineSnapshot
    }
    private var entries: [Entry] = []
    private var version: UInt64?
    private let capacity: Int
    public var count: Int { entries.count }
    public init(capacity: Int = 4) { self.capacity = max(1, capacity) }
    public func snapshot(day: Date, now: Date, version: UInt64, calendar: Calendar = .current,
                         load: () -> (sessions: [Session], focuses: [FocusSession])) -> DayTimelineSnapshot {
        if self.version != version { entries.removeAll(keepingCapacity: true); self.version = version }
        let range = calendar.dateInterval(of: .day, for: day)!
        let observedEnd = max(range.start, min(now, range.end))
        if let index = entries.firstIndex(where: {
            $0.day == range.start && $0.calendar == calendar && $0.observedEnd == observedEnd
        }) {
            let entry = entries.remove(at: index)
            entries.append(entry)
            return entry.snapshot
        }
        // Replace today's stale value instead of retaining every 15-second generation.
        entries.removeAll { $0.day == range.start && $0.calendar == calendar }
        let data = load()
        let value = DayTimelineSnapshot(day: day, sessions: data.sessions, focuses: data.focuses,
                                        now: now, calendar: calendar)
        if entries.count >= capacity { entries.removeFirst() }
        entries.append(Entry(day: range.start, calendar: calendar, observedEnd: observedEnd, snapshot: value))
        return value
    }
}
