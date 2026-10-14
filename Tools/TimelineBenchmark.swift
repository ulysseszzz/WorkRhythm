// Compile with Sources/Core/*.swift and -O. Baseline 1.5: add -D BASELINE_COMPARE.
// Synthetic in-memory data only. Measures view-data preparation, not drawing, app CPU%, or power.
import Foundation

@main
enum TimelineBenchmark {
    static func main() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_792_022_400))
        let now = day.addingTimeInterval(86400 * 2)
        var output: [[String: Any]] = []
        for dayCount in [30, 365] {
            var sessions: [Session] = []
            var focuses: [FocusSession] = []
            for d in 0..<dayCount {
                let base = day.addingTimeInterval(-Double(d) * 86400)
                for i in 0..<96 {
                    let start = base.addingTimeInterval(Double(i) * 900)
                    sessions.append(Session(kind: i % 4 == 3 ? .away : .work,
                                            start: start, end: start.addingTimeInterval(900)))
                }
                for i in 0..<6 {
                    let start = base.addingTimeInterval(Double(i * 4) * 3600)
                    focuses.append(FocusSession(start: start, end: start + 1800, plannedDuration: 1800,
                        segments: [FocusSegment(start: start, end: start + 1800)], completed: true))
                }
            }
            #if !BASELINE_COMPARE
            let cache = DayTimelineCache()
            #endif
            func prepare(_ iteration: Int) -> Double {
                let selected = iteration % 3 == 0
                    ? DateInterval(start: day, duration: 86400)
                    : DateInterval(start: day + Double(8 + iteration % 10) * 3600, duration: 3600)
                #if BASELINE_COMPARE
                let activity = DayActivity(day: day, sessions: sessions, focuses: focuses, now: now, calendar: calendar)
                let records = DayActivity.records(sessions, in: selected, now: now)
                var checksum = Double(records.count) + activity.duration(.work)
                for session in records where session.kind == .away {
                    if let previous = sessions.filter({ $0.kind == .away && $0.start >= day && $0.start < session.start })
                        .max(by: { $0.start < $1.start }) {
                        checksum += session.start.timeIntervalSince(previous.start)
                    }
                }
                let visibleFocus = focuses.filter { focus in
                    focus.segments.contains {
                        StatisticsService.overlap(start: $0.start, end: $0.end, range: selected, now: now) > 0
                    }
                }
                #else
                let snapshot = cache.snapshot(day: day, now: now, version: 0, calendar: calendar) { (sessions, focuses) }
                let records = snapshot.records(in: selected, includeIdle: false)
                var checksum = Double(records.count) + snapshot.activity.duration(.work)
                for session in records where session.kind == .away {
                    checksum += snapshot.previousAwayIntervals[session.id] ?? 0
                }
                let visibleFocus = snapshot.focusRecords(in: selected)
                #endif
                checksum += Double(visibleFocus.count)
                return checksum
            }
            let coldStart = ProcessInfo.processInfo.systemUptime
            let coldChecksum = prepare(0)
            let coldMS = (ProcessInfo.processInfo.systemUptime - coldStart) * 1000
            var samples: [Double] = []
            var checksum = coldChecksum
            for _ in 0..<5 {
                let start = ProcessInfo.processInfo.systemUptime
                for i in 0..<30 { checksum += prepare(i) }
                samples.append((ProcessInfo.processInfo.systemUptime - start) * 1000 / 30)
            }
            output.append(["history_days": dayCount, "sessions": sessions.count, "focuses": focuses.count,
                           "cold_ms": coldMS, "repeat_ms_median": samples.sorted()[2],
                           "repeat_ms_rounds": samples, "checksum": checksum])
        }
        let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        print(String(decoding: data, as: UTF8.self))
    }
}
