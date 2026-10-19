import Foundation

public struct DailySummary {
    public var date: Date
    public var work: Double = 0
    public var focus: Double = 0
    public var away: Double = 0
    public var moving: Double = 0
    public var locked: Double = 0
    public var idle: Double = 0
    public var breaks = 0
    public var lockLeaves = 0
    public var lidLeaves = 0
    public var recentInputLockLeaves = 0
    public var hotCornerLockLeaves = 0
    public var shortBreaks = 0
    public var longBreaks = 0
    public var averageWork: Double = 0
    public var medianWork: Double = 0
    public var longestWork: Double = 0
    public var averageBreak: Double = 0
    public var shortestBreak: Double = 0
    public var longestBreak: Double = 0
    public var averageInterval: Double = 0
    public var medianInterval: Double = 0
    public var minInterval: Double = 0
    public var maxInterval: Double = 0
    public var firstLeave: Date?
    public var lastLeave: Date?
    public var water = 0
    public var waterML = 0
    public var pomodoros = 0
    public var hourly: [Int] = Array(repeating: 0, count: 24)
    public var breaksPerWorkHour: Double { work > 0 ? Double(breaks) / (work / 3600) : 0 }
    public var leave: Double { away + moving + locked }
}

public final class DailySummaryCache {
    private var values: [Date: DailySummary] = [:]
    private let capacity: Int
    public var count: Int { values.count }
    public init(capacity: Int = 64) { self.capacity = max(1, capacity) }
    public func value(for day: Date, calendar: Calendar = .current,
                      load: () -> DailySummary) -> DailySummary {
        let key = calendar.startOfDay(for: day)
        if let value = values[key] { return value }
        if values.count >= capacity { values.removeAll(keepingCapacity: true) }
        let value = load()
        values[key] = value
        return value
    }
    public func invalidate(_ day: Date, calendar: Calendar = .current) {
        values.removeValue(forKey: calendar.startOfDay(for: day))
    }
    public func invalidateAll() { values.removeAll(keepingCapacity: true) }
}

public enum StatisticsService {
    public static func overlap(start: Date, end: Date?, range: DateInterval, now: Date) -> Double {
        max(0, min(end ?? now, range.end, now).timeIntervalSince(max(start, range.start)))
    }
    public static func mean(_ values: [Double]) -> Double { values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count) }
    public static func median(_ values: [Double]) -> Double {
        let v = values.sorted(); guard !v.isEmpty else { return 0 }
        return v.count % 2 == 0 ? (v[v.count / 2 - 1] + v[v.count / 2]) / 2 : v[v.count / 2]
    }
    public static func summary(date: Date, sessions: [Session], focuses: [FocusSession], hydration: [HydrationEvent],
                               settings: AppSettings, now: Date = Date(), calendar: Calendar = .current) -> DailySummary {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let range = DateInterval(start: start, end: end)
        var result = DailySummary(date: start)
        func inside(_ d: Date) -> Bool { d >= start && d < end }
        let relevant = sessions.filter { $0.start < end && ($0.end ?? now) > start }
        var workDurations: [Double] = []
        for s in relevant {
            let duration = overlap(start: s.start, end: s.end, range: range, now: now)
            switch s.kind {
            case .work: result.work += duration; if !s.recovered { workDurations.append(duration) }
            case .away: result.away += duration
            case .moving: result.moving += duration
            case .locked: result.locked += duration
            case .idle: result.idle += duration
            default: break
            }
        }
        // A lock can be upgraded to an inferred manual leave at the same timestamp.
        // Return-side login screens and zero-length intermediate sessions are not new departures.
        let leaves = sessions.filter { DepartureRecord($0) != nil && inside($0.start) }
            .sorted { $0.start < $1.start }
        let complete = leaves.filter { $0.end != nil && !$0.recovered }
        let lengths = complete.map { $0.duration(at: now) }
        result.breaks = leaves.count
        result.lockLeaves = leaves.filter { $0.kind == .locked || ($0.kind == .away && $0.trigger.contains("lock")) }.count
        result.lidLeaves = leaves.filter { $0.kind == .moving }.count
        result.recentInputLockLeaves = leaves.filter {
            DepartureRecord($0)?.lockOrigin == .recentInput
        }.count
        result.hotCornerLockLeaves = leaves.filter {
            DepartureRecord($0)?.lockOrigin == .hotCorner
        }.count
        result.shortBreaks = complete.filter { $0.duration(at: now) < (settings.breakThresholds.sorted().dropFirst().first ?? 10) * 60 }.count
        result.longBreaks = complete.count - result.shortBreaks
        result.averageBreak = mean(lengths); result.shortestBreak = lengths.min() ?? 0; result.longestBreak = lengths.max() ?? 0
        result.averageWork = mean(workDurations); result.longestWork = workDurations.max() ?? 0
        result.medianWork = median(workDurations)
        // Intervals are start-to-start, within the local calendar day; never count an overnight gap.
        let intervals = zip(leaves, leaves.dropFirst()).map { max(0, $1.start.timeIntervalSince($0.start)) }
        result.averageInterval = mean(intervals); result.medianInterval = median(intervals)
        result.minInterval = intervals.min() ?? 0; result.maxInterval = intervals.max() ?? 0
        result.firstLeave = leaves.first?.start; result.lastLeave = leaves.last?.start
        for s in leaves { result.hourly[calendar.component(.hour, from: s.start)] += 1 }
        for f in focuses {
            result.focus += f.segments.reduce(0) { $0 + overlap(start: $1.start, end: $1.end, range: range, now: now) }
            if f.completed, let finished = f.end, inside(finished) { result.pomodoros += 1 }
        }
        let drinks = hydration.filter { inside($0.timestamp) && $0.voidedAt == nil }
        result.water = drinks.count
        result.waterML = drinks.reduce(0) { $0 + max(0, $1.amountML ?? 0) }
        return result
    }
    public static func csv(sessions: [Session], focuses: [FocusSession], hydration: [HydrationEvent], now: Date) -> String {
        let iso = ISO8601DateFormatter()
        func cell(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        var rows = ["record_type,id,start,end,duration_seconds,trigger,confidence,label,status,amount_ml,voided_at,drink_preset"]
        for s in sessions {
            rows.append([s.kind.rawValue, s.id.uuidString, iso.string(from: s.start), s.end.map(iso.string) ?? "",
                         String(format: "%.3f", s.duration(at: now)), s.trigger, String(s.confidence), s.label,
                         s.recovered ? "censored" : (s.end == nil ? "open" : "complete"), "", "", ""].map(cell).joined(separator: ","))
        }
        for f in focuses {
            rows.append(["focus", f.id.uuidString, iso.string(from: f.start), f.end.map(iso.string) ?? "",
                         String(format: "%.3f", f.elapsed(at: now)), "pomodoro", "1", "",
                         f.completed ? "completed" : (f.end == nil ? "open_or_paused" : "interrupted"), "", "", ""].map(cell).joined(separator: ","))
        }
        for h in hydration {
            rows.append(["hydration", h.id.uuidString, iso.string(from: h.timestamp), "", "0", h.source, "1", "",
                         h.voidedAt == nil ? "done" : "voided", h.amountML.map(String.init) ?? "",
                         h.voidedAt.map(iso.string) ?? "", h.drinkPresetID ?? ""].map(cell).joined(separator: ","))
        }
        return rows.joined(separator: "\n") + "\n"
    }
}

public struct ReminderPolicy {
    public var hydrationDue: Date
    public var sedentarySnoozeUntil: Date = .distantPast
    public var eligibleAfter: Date
    public var lastHydrationNotification: Date = .distantPast
    public var lastSedentaryNotification: Date = .distantPast
    public init(now: Date, settings: AppSettings, lastDrink: Date?) {
        hydrationDue = (lastDrink ?? now).addingTimeInterval(settings.hydrationMinutes * 60)
        eligibleAfter = now.addingTimeInterval(settings.returnGraceSeconds)
    }
    public func allowed(state: WorkstationState, awake: Bool, locked: Bool, now: Date) -> Bool {
        state.atDesk && awake && !locked && now >= eligibleAfter
    }
    public mutating func due(state: WorkstationState, awake: Bool, locked: Bool, workStart: Date?,
                             settings: AppSettings, now: Date) -> [String] {
        guard allowed(state: state, awake: awake, locked: locked, now: now) else { return [] }
        var result: [String] = []
        let focusAllowsWater = state != .focus || now.timeIntervalSince(hydrationDue) >= settings.hydrationMinutes * 60
        if settings.hydrationEnabled && focusAllowsWater && now >= hydrationDue &&
            now.timeIntervalSince(lastHydrationNotification) >= 30 * 60 {
            result.append("water"); lastHydrationNotification = now
        }
        if settings.sedentaryEnabled, state != .focus, let workStart,
           now.timeIntervalSince(workStart) >= settings.sedentaryMinutes * 60,
           now >= sedentarySnoozeUntil, now.timeIntervalSince(lastSedentaryNotification) >= 30 * 60 {
            result.append("sedentary"); lastSedentaryNotification = now
        }
        return result
    }
}
