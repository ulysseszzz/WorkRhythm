import XCTest
@testable import WorkRhythmCore

final class ActivityRecordsTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    private let day = Date(timeIntervalSince1970: 1_728_950_400)

    func testDrinkHistoryExcludesUndoOtherDaysAndFutureWithoutInventingLegacyVolume() {
        let start = calendar.startOfDay(for: day)
        let old = HydrationEvent(timestamp: start.addingTimeInterval(-1), source: "test", amountML: 600)
        let legacy = HydrationEvent(timestamp: start, source: "legacy")
        let tea = HydrationEvent(timestamp: start.addingTimeInterval(60), source: "test", amountML: 150, drinkPresetID: "tea")
        var undone = HydrationEvent(timestamp: start.addingTimeInterval(120), source: "test", amountML: 300)
        undone.voidedAt = start.addingTimeInterval(140)
        let future = HydrationEvent(timestamp: start.addingTimeInterval(600), source: "test", amountML: 450)
        let next = HydrationEvent(timestamp: start.addingTimeInterval(86400), source: "test")
        let rows = ActivityRecords.drinks([future, legacy, old, tea, undone, next],
                                          day: start, now: start.addingTimeInterval(300), calendar: calendar)
        XCTAssertEqual(rows.map(\.id), [tea.id, legacy.id])
        XCTAssertNil(rows.last?.amountML)
    }

    func testScreenObservationsAreNotInferredFromDeskOrActivityEvents() {
        let start = calendar.startOfDay(for: day)
        let lock = SystemEvent(timestamp: start.addingTimeInterval(60), type: "system_event",
                               metadata: "lockObserved(uptime: 123.0, idleSeconds: 0.0, stillInCorner: true)")
        let sleep = SystemEvent(timestamp: start.addingTimeInterval(62), type: "system_event",
                                metadata: "displaySleep(uptime: 125.0, idleSeconds: 2.0, stillInCorner: true)")
        let wake = SystemEvent(timestamp: start.addingTimeInterval(100), type: "system_event", metadata: "displayWake")
        let unrelated = [
            SystemEvent(timestamp: start, type: "state_transition", metadata: "active -> away"),
            SystemEvent(timestamp: start, type: "system_event", metadata: "confirmSleep"),
            SystemEvent(timestamp: start, type: "system_event", metadata: "userActivity"),
            SystemEvent(timestamp: start, type: "system_event", metadata: "idle"),
            SystemEvent(timestamp: start.addingTimeInterval(-1), type: "system_event", metadata: "unlock"),
            SystemEvent(timestamp: start.addingTimeInterval(86400), type: "system_event", metadata: "unlock")
        ]
        let rows = ActivityRecords.screens([lock, wake, sleep] + unrelated, day: start,
                                           now: start.addingTimeInterval(200), calendar: calendar)
        XCTAssertEqual(rows.map(\.title), ["屏幕亮起", "屏幕熄灭", "锁定屏幕"])
        XCTAssertEqual(rows.map(\.inactive), [false, true, true])
        XCTAssertEqual(rows.last?.timestamp, lock.timestamp)
    }

    func testAllSupportedScreenActionsAndUnknownFallback() {
        for action in ["lock", "unlock", "systemSleep", "systemWake", "lidClosed", "lidOpened",
                       "screenSaverStarted", "screenSaverStopped", "displayWake"] {
            XCTAssertNotNil(ScreenRecord(SystemEvent(timestamp: day, type: "system_event", metadata: action)))
        }
        XCTAssertNil(ScreenRecord(SystemEvent(timestamp: day, type: "system_event", metadata: "newUnknownInput")))
    }

    func testDeparturesIncludeLockLidAndActiveButExcludeReturnAndZeroLengthUpgrade() {
        let start = calendar.startOfDay(for: day)
        let locked = Session(kind: .locked, start: start.addingTimeInterval(60),
                             end: start.addingTimeInterval(120), trigger: "lock")
        var lid = Session(kind: .moving, start: start.addingTimeInterval(180),
                          end: start.addingTimeInterval(240), trigger: "lid_closed_possible_moving")
        lid.label = "Meal"
        let manualLock = Session(kind: .away, start: start.addingTimeInterval(300),
                                 end: start.addingTimeInterval(360), trigger: "manual_lock_recent_input")
        let activeLeave = Session(kind: .away, start: start.addingTimeInterval(420),
                                  end: start.addingTimeInterval(480), trigger: "hot_corner:br")
        let zeroUpgrade = Session(kind: .locked, start: start.addingTimeInterval(300),
                                  end: start.addingTimeInterval(300), trigger: "lock")
        let wakeLogin = Session(kind: .locked, start: start.addingTimeInterval(500),
                                end: start.addingTimeInterval(510), trigger: "display_wake")
        let work = Session(kind: .work, start: start, end: start.addingTimeInterval(30))
        let rows = ActivityRecords.departures([work, locked, lid, manualLock, activeLeave, zeroUpgrade, wakeLogin],
                                               day: start, now: start.addingTimeInterval(600), calendar: calendar)
        XCTAssertEqual(rows.map(\.kind), [.active, .lock, .lid, .lock])
        XCTAssertEqual(rows.map { $0.duration(at: start.addingTimeInterval(600)) }, [60, 60, 60, 60])
        XCTAssertEqual(rows[2].label, "Meal")
        XCTAssertEqual(AppSettings.labelTitle(rows[2].label), "用餐")
    }

    func testSelectedDayReadsPastDiagnosticFeedLimit() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let repo = try Repository(url: folder.appendingPathComponent("test.sqlite"))
        let start = calendar.startOfDay(for: day)
        try repo.transaction {
            for index in 0..<520 {
                try repo.save(SystemEvent(timestamp: start.addingTimeInterval(Double(index)),
                                          type: "system_event", metadata: "displayWake"))
            }
            try repo.save(SystemEvent(timestamp: start.addingTimeInterval(-1), type: "system_event", metadata: "unlock"))
            try repo.save(SystemEvent(timestamp: start.addingTimeInterval(86400), type: "system_event", metadata: "unlock"))
        }
        XCTAssertEqual(try repo.events().count, 500)
        let rows = try repo.events(in: calendar.dateInterval(of: .day, for: start)!)
        XCTAssertEqual(rows.count, 520)
        XCTAssertEqual(rows.last?.timestamp, start)
        XCTAssertEqual(rows.first?.timestamp, start.addingTimeInterval(519))
    }
}
