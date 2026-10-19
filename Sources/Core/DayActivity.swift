import Foundation

/// Mutually exclusive display categories. Focus/idle refine work rather than adding time to it.
public enum DayActivityKind: Int, CaseIterable {
    case unknown, work, idle, focus, unavailable, locked, moving, away
    public var title: String {
        switch self {
        case .work: return "在工位"
        case .focus: return "专注"
        case .idle: return "阅读 / 静默"
        case .away: return "离座"
        case .moving: return "合盖离座"
        case .locked: return "锁屏离座"
        case .unavailable: return "设备睡眠"
        case .unknown: return "未记录"
        }
    }
    static func from(_ kind: SessionKind) -> Self {
        switch kind {
        case .work: return .work
        case .idle: return .idle
        case .away: return .away
        case .moving: return .moving
        case .locked: return .locked
        case .displaySleep, .systemSleep: return .unavailable
        case .unknown: return .unknown
        }
    }
}

public struct DayActivitySpan: Identifiable {
    public var id: Date { start }
    public let start: Date
    public var end: Date
    public let kind: DayActivityKind
    public var duration: TimeInterval { end.timeIntervalSince(start) }
}

public struct DayActivityHour: Identifiable {
    public var id: Date { start }
    public let start: Date
    public let end: Date
    public let label: String
    public let spans: [DayActivitySpan]
    public var range: DateInterval { DateInterval(start: start, end: end) }
    public func duration(_ kind: DayActivityKind) -> TimeInterval {
        spans.filter { $0.kind == kind }.reduce(0) { $0 + $1.duration }
    }
}

public struct DayActivity {
    public let range: DateInterval
    public let spans: [DayActivitySpan]
    public let hours: [DayActivityHour]
    public func duration(_ kind: DayActivityKind) -> TimeInterval {
        spans.filter { $0.kind == kind }.reduce(0) { $0 + $1.duration }
    }
    public static func records(_ sessions: [Session], in interval: DateInterval,
                               now: Date, includeIdle: Bool = false) -> [Session] {
        sessions.filter {
            StatisticsService.overlap(start: $0.start, end: $0.end, range: interval, now: now) > 0
                && (includeIdle || $0.kind != .idle)
        }.sorted {
            $0.start == $1.start ? $0.id.uuidString < $1.id.uuidString : $0.start > $1.start
        }
    }

    public init(day: Date, sessions: [Session], focuses: [FocusSession], now: Date,
                calendar: Calendar = .current) {
        let range = calendar.dateInterval(of: .day, for: day)!
        self.range = range
        let observedEnd = min(now, range.end)
        struct Edge { let date: Date; let kind: DayActivityKind; let delta: Int }
        var edges: [Edge] = []
        func add(_ start: Date, _ end: Date?, _ kind: DayActivityKind) {
            let a = max(start, range.start), b = min(end ?? now, observedEnd)
            guard b > a else { return }
            edges.append(Edge(date: a, kind: kind, delta: 1))
            edges.append(Edge(date: b, kind: kind, delta: -1))
        }
        for session in sessions { add(session.start, session.end, .from(session.kind)) }
        for focus in focuses {
            // Only effective segments; a pause must not fill a whole planned focus interval.
            for segment in focus.segments {
                add(segment.start, segment.end ?? focus.end ?? focus.pausedAt, .focus)
            }
        }
        edges.sort { $0.date < $1.date }
        var active = Array(repeating: 0, count: DayActivityKind.allCases.count)
        var result: [DayActivitySpan] = []
        var cursor = range.start
        var i = 0
        while cursor < observedEnd {
            while i < edges.count && edges[i].date <= cursor {
                active[edges[i].kind.rawValue] += edges[i].delta
                i += 1
            }
            let end = min(i < edges.count ? edges[i].date : observedEnd, observedEnd)
            let kind = DayActivityKind.allCases.reversed().first { active[$0.rawValue] > 0 } ?? .unknown
            if result.last?.kind == kind {
                result[result.count - 1].end = end
            } else {
                result.append(DayActivitySpan(start: cursor, end: end, kind: kind))
            }
            cursor = end
        }
        spans = result
        var buckets: [DayActivityHour] = []
        var spanIndex = 0
        cursor = range.start
        while cursor < range.end {
            let end = min(calendar.dateInterval(of: .hour, for: cursor)!.end, range.end)
            var pieces: [DayActivitySpan] = []
            while spanIndex < result.count && result[spanIndex].end <= cursor { spanIndex += 1 }
            var next = spanIndex
            while next < result.count && result[next].start < end {
                let span = result[next]
                let a = max(cursor, span.start), b = min(end, span.end)
                if b > a { pieces.append(DayActivitySpan(start: a, end: b, kind: span.kind)) }
                next += 1
            }
            let label = String(format: "%02d", calendar.component(.hour, from: cursor))
            buckets.append(DayActivityHour(start: cursor, end: end, label: label, spans: pieces))
            cursor = end
        }
        // Keep repeated DST hours distinct both in identity and in their displayed labels.
        let counts = Dictionary(grouping: buckets, by: \.label).mapValues(\.count)
        hours = buckets.map { hour in
            guard counts[hour.label, default: 0] > 1 else { return hour }
            let zone = calendar.timeZone.abbreviation(for: hour.start) ?? ""
            return DayActivityHour(start: hour.start, end: hour.end,
                                   label: "\(hour.label) \(zone)", spans: hour.spans)
        }
    }
}
