import XCTest
@testable import WorkRhythmCore

final class DayActivityTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private var day: Date { date("2026-10-13T00:00:00Z") }
    private func time(_ minutes: Double) -> Date { day.addingTimeInterval(minutes * 60) }

    func testWorkIdleAndEffectiveFocusNeverDoubleCount() {
        let sessions = [Session(kind: .work, start: time(540), end: time(600)),
                        Session(kind: .idle, start: time(550), end: time(565))]
        let focus = FocusSession(start: time(555), end: time(590), plannedDuration: 3600,
                                 segments: [FocusSegment(start: time(555), end: time(560)),
                                            FocusSegment(start: time(580), end: time(590))])
        let activity = DayActivity(day: day, sessions: sessions, focuses: [focus], now: time(600), calendar: calendar)
        let hour = activity.hours[9]
        XCTAssertEqual(hour.duration(.work), 35 * 60)
        XCTAssertEqual(hour.duration(.idle), 10 * 60)
        XCTAssertEqual(hour.duration(.focus), 15 * 60)
        XCTAssertEqual(hour.spans.reduce(0) { $0 + $1.duration }, 3600)
        XCTAssertEqual(hour.spans.map(\.kind), [.work, .idle, .focus, .idle, .work, .focus, .work])
    }
    func testClipCrossDayAndCrossHourAndLeaveFutureEmpty() {
        let sessions = [Session(kind: .away, start: time(-10), end: time(10)),
                        Session(kind: .work, start: time(50)),
                        Session(kind: .moving, start: time(120), end: time(130))]
        let activity = DayActivity(day: day, sessions: sessions, focuses: [], now: time(75), calendar: calendar)
        XCTAssertEqual(activity.hours[0].duration(.away), 600)
        XCTAssertEqual(activity.hours[0].duration(.unknown), 2400)
        XCTAssertEqual(activity.hours[0].duration(.work), 600)
        XCTAssertEqual(activity.hours[1].duration(.work), 900)
        XCTAssertTrue(activity.hours.dropFirst(2).allSatisfy { $0.spans.isEmpty })
        XCTAssertEqual(activity.spans.reduce(0) { $0 + $1.duration }, 75 * 60)
    }
    func testOffDeskWinsOverOverlappingFocusAndDuplicateWork() {
        let sessions = [Session(kind: .work, start: time(540), end: time(600)),
                        Session(kind: .work, start: time(540), end: time(600)),
                        Session(kind: .away, start: time(570), end: time(580))]
        let focus = FocusSession(start: time(560), plannedDuration: 3600,
                                 segments: [FocusSegment(start: time(560))], pausedAt: time(590))
        let activity = DayActivity(day: day, sessions: sessions, focuses: [focus], now: time(600), calendar: calendar)
        XCTAssertEqual(activity.hours[9].duration(.away), 600)
        XCTAssertEqual(activity.hours[9].duration(.focus), 1200)
        XCTAssertEqual(activity.hours[9].duration(.work), 1800)
    }
    func testLockAndLidRemainDistinctDepartureKindsWhileSleepIsUnavailable() {
        let sessions = [
            Session(kind: .locked, start: time(60), end: time(70)),
            Session(kind: .moving, start: time(70), end: time(80)),
            Session(kind: .systemSleep, start: time(80), end: time(90))
        ]
        let activity = DayActivity(day: day, sessions: sessions, focuses: [], now: time(100), calendar: calendar)
        XCTAssertEqual(activity.duration(.locked), 600)
        XCTAssertEqual(activity.duration(.moving), 600)
        XCTAssertEqual(activity.duration(.unavailable), 600)
    }
    func testEmptyPastIsUnknownWhileFutureHasNoSpans() {
        let past = DayActivity(day: day, sessions: [], focuses: [], now: time(1440), calendar: calendar)
        XCTAssertEqual(past.duration(.unknown), 86400)
        XCTAssertEqual(past.hours.count, 24)
        let future = DayActivity(day: time(1440), sessions: [], focuses: [], now: time(600), calendar: calendar)
        XCTAssertTrue(future.spans.isEmpty)
        XCTAssertTrue(future.hours.allSatisfy { $0.spans.isEmpty })
    }
    func testDaylightSavingDaysUseActualHoursWithUniqueIdentity() {
        var c = calendar
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        for (value, count) in [("2026-03-08T12:00:00Z", 23), ("2026-11-01T12:00:00Z", 25)] {
            let d = date(value)
            let activity = DayActivity(day: d, sessions: [], focuses: [], now: d.addingTimeInterval(86400), calendar: c)
            XCTAssertEqual(activity.hours.count, count)
            XCTAssertEqual(Set(activity.hours.map(\.id)).count, count)
            XCTAssertEqual(Set(activity.hours.map(\.label)).count, count)
            XCTAssertEqual(activity.spans.reduce(0) { $0 + $1.duration }, Double(count) * 3600)
        }
    }
    func testDetailsNewestFirstAndSelectedHourClipsBoundaries() {
        let sessions = [Session(kind: .away, start: time(540), end: time(550)),
                        Session(kind: .work, start: time(550), end: time(600)),
                        Session(kind: .away, start: time(600), end: time(610)),
                        Session(kind: .idle, start: time(580), end: time(585))]
        let all = DayActivity.records(sessions, in: DateInterval(start: day, duration: 86400), now: time(620))
        XCTAssertEqual(all.map(\.start), [time(600), time(550), time(540)])
        let selected = DayActivity.records(sessions, in: DateInterval(start: time(540), end: time(600)),
                                          now: time(620), includeIdle: true)
        XCTAssertEqual(selected.map(\.start), [time(580), time(550), time(540)])
    }
}
