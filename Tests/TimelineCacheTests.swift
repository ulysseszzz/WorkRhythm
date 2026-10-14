import XCTest
@testable import WorkRhythmCore

final class TimelineCacheTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }
    private var day: Date { Date(timeIntervalSince1970: 1_792_022_400) } // UTC midnight
    func testHistoricalCacheHitDoesNotReadHistoryAndTodayAdvances() {
        let c = calendar
        let date = c.startOfDay(for: day)
        let cache = DayTimelineCache()
        var loads = 0
        func load() -> (sessions: [Session], focuses: [FocusSession]) {
            loads += 1
            return ([Session(kind: .work, start: date)], [])
        }
        let today = cache.snapshot(day: date, now: date + 600, version: 0, calendar: c, load: load)
        let repeated = cache.snapshot(day: date, now: date + 600, version: 0, calendar: c, load: load)
        XCTAssertTrue(today === repeated)
        XCTAssertEqual(loads, 1)
        let later = cache.snapshot(day: date, now: date + 615, version: 0, calendar: c, load: load)
        XCTAssertEqual(later.activity.duration(.work), 615)
        XCTAssertFalse(today === later)
        XCTAssertEqual(cache.count, 1)
        let historical = cache.snapshot(day: date, now: date + 86400, version: 0, calendar: c, load: load)
        let tick = cache.snapshot(day: date, now: date + 90000, version: 0, calendar: c, load: load)
        XCTAssertTrue(historical === tick)
        XCTAssertEqual(loads, 3)
        let rewind = cache.snapshot(day: date, now: date + 300, version: 0, calendar: c, load: load)
        XCTAssertEqual(rewind.activity.duration(.work), 300)
    }
    func testVersionTimezoneAndLRUEviction() {
        let c = calendar
        let cache = DayTimelineCache(capacity: 2)
        let now = day + 86400 * 10
        func get(_ d: Date, version: UInt64 = 0, cal: Calendar? = nil) -> DayTimelineSnapshot {
            cache.snapshot(day: d, now: now, version: version, calendar: cal ?? c) { ([], []) }
        }
        let a = get(day), b = get(day + 86400)
        XCTAssertTrue(a === get(day))
        _ = get(day + 172800)
        XCTAssertEqual(cache.count, 2)
        XCTAssertTrue(a === get(day))
        XCTAssertFalse(b === get(day + 86400))
        XCTAssertFalse(a === get(day, version: 1))
        XCTAssertEqual(cache.count, 1)
        var zone = c
        zone.timeZone = TimeZone(secondsFromGMT: 3600)!
        let shifted = get(day, version: 1, cal: zone)
        XCTAssertNotEqual(shifted.range.start, get(day, version: 1).range.start)
    }
    func testSnapshotFiltersAndPreviousDepartureStrictlyEarlier() {
        let d = calendar.startOfDay(for: day)
        let old = Session(kind: .away, start: d - 60, end: d + 10)
        let zero = Session(kind: .away, start: d + 30, end: d + 30)
        let a = Session(kind: .away, start: d + 60, end: d + 100)
        let b = Session(kind: .away, start: d + 60, end: d + 100)
        let later = Session(kind: .away, start: d + 150, end: d + 200)
        let sessions = [later, old, a, b, zero]
        let snapshot = DayTimelineSnapshot(day: d, sessions: sessions, focuses: [], now: d + 600, calendar: calendar)
        XCTAssertEqual(snapshot.previousAwayIntervals[a.id], 30)
        XCTAssertEqual(snapshot.previousAwayIntervals[b.id], 30)
        XCTAssertEqual(snapshot.previousAwayIntervals[later.id], 90)
        XCTAssertNil(snapshot.previousAwayIntervals[old.id])
        let hour = DateInterval(start: d, duration: 120)
        XCTAssertEqual(snapshot.records(in: hour, includeIdle: true).map(\.id),
                       DayActivity.records(sessions, in: hour, now: d + 600, includeIdle: true).map(\.id))
    }
    func testLedgerRevisionUpdatesForEditsButNotHydration() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try Repository(url: directory.appendingPathComponent("test.sqlite"))
        let ledger = try SessionLedger(repository: repository)
        let initial = ledger.timelineRevision
        try ledger.transition(Transition(state: .active, at: day, reason: "fixture", confidence: 1))
        XCTAssertGreaterThan(ledger.timelineRevision, initial)
        let opened = ledger.timelineRevision
        try ledger.label(id: ledger.sessions[0].id, value: "label")
        XCTAssertGreaterThan(ledger.timelineRevision, opened)
        let labeled = ledger.timelineRevision
        try ledger.drink(at: day, source: "fixture", amountML: 200)
        XCTAssertEqual(ledger.timelineRevision, labeled)
        try ledger.startFocus(minutes: 25, at: day)
        let running = ledger.timelineRevision
        XCTAssertGreaterThan(running, labeled)
        try ledger.pauseFocus(at: day + 60)
        XCTAssertGreaterThan(ledger.timelineRevision, running)
        let paused = ledger.timelineRevision
        try ledger.resumeFocus(at: day + 90)
        XCTAssertGreaterThan(ledger.timelineRevision, paused)
        let resumed = ledger.timelineRevision
        try ledger.closeAll(at: day + 120)
        XCTAssertGreaterThan(ledger.timelineRevision, resumed)
    }
    func testEventRevisionTracksWritesAndPruningOnly() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repo = try Repository(url: directory.appendingPathComponent("test.sqlite"))
        let initial = repo.eventRevision
        try repo.save(SystemEvent(timestamp: day, type: "fixture", metadata: ""))
        XCTAssertGreaterThan(repo.eventRevision, initial)
        let written = repo.eventRevision
        try repo.saveSettings(AppSettings())
        XCTAssertEqual(repo.eventRevision, written)
        try repo.pruneEvents(before: day - 1)
        XCTAssertEqual(repo.eventRevision, written)
        try repo.pruneEvents(before: day + 1)
        XCTAssertGreaterThan(repo.eventRevision, written)
        XCTAssertTrue(try repo.events().isEmpty)
    }
}
