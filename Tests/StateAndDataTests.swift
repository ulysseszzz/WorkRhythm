import XCTest
@testable import WorkRhythmCore

final class StateAndDataTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    func machine() -> WorkstationStateMachine {
        let m = WorkstationStateMachine()
        m.handle(.userActivity, at: start)
        return m
    }
    func testChineseCompactDurationFormatting() {
        XCTAssertEqual(DurationText.short(0), "0秒")
        XCTAssertEqual(DurationText.short(59), "59秒")
        XCTAssertEqual(DurationText.short(60), "1分")
        XCTAssertEqual(DurationText.short(62), "1分 2秒")
        XCTAssertEqual(DurationText.short(3600), "1时")
        XCTAssertEqual(DurationText.short(4500), "1时 15分")
    }
    func enter(_ m: WorkstationStateMachine, offset: Double = 0) {
        m.handle(.cornerEntered(name: "br", screen: "2", x: 1500, y: -600, uptime: 100 + offset), at: start.addingTimeInterval(offset))
    }
    func sleep(_ m: WorkstationStateMachine, offset: Double = 0.4, idle: Double = 0.4) {
        m.handle(.displaySleep(uptime: 100 + offset, idleSeconds: idle, stillInCorner: true), at: start.addingTimeInterval(offset))
    }
    func testRealCandidateCommitsOnceAndRapidWakeEnds() {
        let m = machine(); var transitions: [Transition] = []
        m.onTransition = { transitions.append($0) }
        enter(m); sleep(m)
        XCTAssertTrue(m.hasPending)
        sleep(m)
        m.handle(.displayWake, at: start.addingTimeInterval(0.8))
        m.handle(.confirmSleep, at: start.addingTimeInterval(2))
        XCTAssertEqual(transitions.filter { $0.state == .away }.count, 1)
        XCTAssertEqual(transitions.first?.at, start.addingTimeInterval(0.4))
        XCTAssertEqual(m.state, .active)
    }
    func testIdleSleepNeverAway() {
        let m = machine(); enter(m); sleep(m, offset: 600, idle: 600)
        m.handle(.confirmSleep, at: start.addingTimeInterval(602))
        XCTAssertEqual(m.state, .displaySleep)
    }
    func observedLock(_ m: WorkstationStateMachine, offset: Double = 0.4, inside: Bool = true, idle: Double = 0.4) {
        m.handle(.lockObserved(uptime: 100 + offset, idleSeconds: idle, stillInCorner: inside), at: start.addingTimeInterval(offset))
    }
    func testCornerLockWithoutDisplaySleepStartsAwayAndUnlockEnds() {
        let m = machine(); var transitions: [Transition] = []
        m.onTransition = { transitions.append($0) }
        enter(m); observedLock(m)
        m.handle(.confirmSleep, at: start.addingTimeInterval(2))
        XCTAssertEqual(m.state, .away)
        XCTAssertTrue(m.displayAwake)
        XCTAssertEqual(transitions.first?.at, start.addingTimeInterval(0.4))
        XCTAssertTrue(transitions.first?.reason.hasPrefix("hot_corner_lock:") == true)
        m.handle(.displayWake, at: start.addingTimeInterval(3))
        XCTAssertEqual(m.state, .away, "Duplicate wake is not return from lock-only Away")
        m.handle(.unlock, at: start.addingTimeInterval(80))
        XCTAssertEqual(m.state, .active)
    }
    func testLockThenSleepAndDuplicateLockProduceOneAway() {
        let m = machine(); var away: [Transition] = []
        m.onTransition = { if $0.state == .away { away.append($0) } }
        enter(m); observedLock(m); observedLock(m, offset: 0.5)
        sleep(m, offset: 0.6)
        m.handle(.confirmSleep, at: start.addingTimeInterval(2))
        m.handle(.displayWake, at: start.addingTimeInterval(80))
        m.handle(.unlock, at: start.addingTimeInterval(81))
        XCTAssertEqual(away.count, 1)
        XCTAssertEqual(away.first?.at, start.addingTimeInterval(0.4))
        XCTAssertEqual(m.state, .active)
    }
    func testImmediateUnlockCommitsAndClosesSingleShortAway() {
        let m = machine(); var away = 0
        m.onTransition = { if $0.state == .away { away += 1 } }
        enter(m); observedLock(m)
        m.handle(.unlock, at: start.addingTimeInterval(0.8))
        m.handle(.confirmSleep, at: start.addingTimeInterval(2))
        XCTAssertEqual(away, 1); XCTAssertEqual(m.state, .active)
    }
    func testKeyboardOrMenuLockWithRecentInputStartsAway() {
        for idle in [0.0, 0.4, 5.0] {
            let m = machine()
            observedLock(m, inside: false, idle: idle)
            m.handle(.confirmSleep, at: start.addingTimeInterval(2))
            XCTAssertEqual(m.state, .away)
            m.handle(.unlock, at: start.addingTimeInterval(80))
            XCTAssertEqual(m.state, .active)
        }
    }
    func testAutomaticStaleAndScreensaverLocksNeverAway() {
        for idle in [5.001, 60, 600] {
            let m = machine()
            observedLock(m, inside: false, idle: idle)
            m.handle(.confirmSleep, at: start.addingTimeInterval(602))
            XCTAssertEqual(m.state, .locked)
        }
        let saver = machine()
        saver.handle(.screenSaverStarted, at: start.addingTimeInterval(0.1))
        observedLock(saver, inside: false, idle: 0.2)
        saver.handle(.confirmSleep, at: start.addingTimeInterval(2))
        XCTAssertNotEqual(saver.state, .away)
    }
    func testWorkspaceLockBeforeDetailedObservationCanUpgradeToAway() {
        let m = machine(); var reasons: [String] = []
        m.onTransition = { reasons.append($0.reason) }
        m.handle(.lock, at: start.addingTimeInterval(0.2))
        XCTAssertEqual(m.state, .locked)
        observedLock(m, offset: 0.4, inside: false, idle: 0.4)
        m.handle(.confirmSleep, at: start.addingTimeInterval(2))
        XCTAssertEqual(m.state, .away)
        XCTAssertTrue(reasons.contains { $0.hasPrefix("manual_lock_recent_input") })
    }
    func testManualLockCandidateSurvivesLockScreenSaverUI() {
        let m = machine()
        observedLock(m, inside: false, idle: 0.2)
        m.handle(.screenSaverStarted, at: start.addingTimeInterval(0.5))
        m.handle(.confirmSleep, at: start.addingTimeInterval(2))
        XCTAssertEqual(m.state, .away)
    }
    func testPowerEventsWinPendingHotCornerLock() {
        for blocker in [Input.lidClosed, .systemSleep] {
            let m = machine(); enter(m); observedLock(m)
            m.handle(blocker, at: start.addingTimeInterval(0.6))
            m.handle(.confirmSleep, at: start.addingTimeInterval(2))
            XCTAssertFalse(m.hasPending); XCTAssertNotEqual(m.state, .away)
        }
    }
    func testLockOriginSurvivesFocusPauseAndPersistence() throws {
        let repo = try repository(); let ledger = try SessionLedger(repository: repo)
        try ledger.transition(Transition(state: .active, at: start, reason: "input", confidence: 1))
        try ledger.startFocus(minutes: 25, at: start)
        let m = machine()
        m.onTransition = { transition in
            do {
                try ledger.transition(transition)
                if !transition.state.atDesk { try ledger.pauseFocus(at: transition.at) }
            } catch { XCTFail("Persistence failed: \(error)") }
        }
        enter(m); observedLock(m)
        m.handle(.confirmSleep, at: start.addingTimeInterval(2))
        m.handle(.unlock, at: start.addingTimeInterval(80))
        let away = try XCTUnwrap(repo.sessions().first { $0.kind == .away })
        XCTAssertEqual(away.duration(at: start), 79.6, accuracy: 0.001)
        XCTAssertTrue(away.trigger.hasPrefix("hot_corner_lock:"))
        XCTAssertEqual(try repo.focuses().first?.actualDuration ?? 0, 0.4, accuracy: 0.001)
    }
    func testPassingCornerWithoutSleepDoesNothing() {
        let m = machine(); enter(m); m.handle(.cornerExited, at: start)
        XCTAssertEqual(m.state, .active)
        sleep(m); XCTAssertFalse(m.hasPending)
    }
    func testLockAndScreensaverExcludeCandidate() {
        for blocker in [Input.lock, .screenSaverStarted] {
            let m = machine(); enter(m); m.handle(blocker, at: start.addingTimeInterval(0.1))
            sleep(m); m.handle(.confirmSleep, at: start.addingTimeInterval(3))
            XCTAssertNotEqual(m.state, .away)
        }
    }
    func testLidAndSystemSleepWinAllPendingOrders() {
        for blocker in [Input.lidClosed, .systemSleep] {
            for before in [true, false] {
                let m = machine(); enter(m)
                if before { m.handle(blocker, at: start.addingTimeInterval(0.2)) }
                sleep(m)
                if !before { m.handle(blocker, at: start.addingTimeInterval(0.6)) }
                m.handle(.confirmSleep, at: start.addingTimeInterval(3))
                XCTAssertFalse(m.hasPending)
                XCTAssertNotEqual(m.state, .away)
            }
        }
    }
    func testLateSleepReclassifiesAndDarkWakeDoesNotStartWork() {
        let m = machine(); var rollback = false
        m.onTransition = { rollback = rollback || $0.rollbackRecentAway }
        enter(m); sleep(m)
        m.handle(.confirmSleep, at: start.addingTimeInterval(2))
        m.handle(.systemSleep, at: start.addingTimeInterval(2.2))
        XCTAssertTrue(rollback)
        m.handle(.systemWake, at: start.addingTimeInterval(40))
        XCTAssertEqual(m.state, .systemSleep)
    }
    func testSecurityLockAfterDisplaySleepDoesNotEraseAway() {
        let m = machine(); enter(m); sleep(m)
        m.handle(.lock, at: start.addingTimeInterval(0.6))
        m.handle(.confirmSleep, at: start.addingTimeInterval(2))
        XCTAssertEqual(m.state, .away)
        m.handle(.displayWake, at: start.addingTimeInterval(80))
        XCTAssertEqual(m.state, .locked)
        m.handle(.unlock, at: start.addingTimeInterval(85))
        XCTAssertEqual(m.state, .active)
    }
    func testEstablishedAwaySurvivesSystemSleep() {
        let m = machine(); enter(m); sleep(m)
        m.handle(.confirmSleep, at: start.addingTimeInterval(2))
        m.handle(.systemSleep, at: start.addingTimeInterval(100))
        m.handle(.systemWake, at: start.addingTimeInterval(400))
        XCTAssertEqual(m.state, .away)
        m.handle(.displayWake, at: start.addingTimeInterval(401))
        XCTAssertEqual(m.state, .active)
    }
    func testEstablishedLockSurvivesSystemSleepUntilUnlock() {
        let m = machine(); var transitions: [WorkstationState] = []
        m.onTransition = { transitions.append($0.state) }
        m.handle(.lock, at: start.addingTimeInterval(1))
        m.handle(.systemSleep, at: start.addingTimeInterval(10))
        m.handle(.systemWake, at: start.addingTimeInterval(100))
        m.handle(.displayWake, at: start.addingTimeInterval(101))
        XCTAssertEqual(m.state, .locked)
        XCTAssertEqual(transitions.filter { $0 == .locked }.count, 1)
        XCTAssertFalse(transitions.contains(.systemSleep))
        m.handle(.unlock, at: start.addingTimeInterval(105))
        XCTAssertEqual(m.state, .active)
    }
    func testClamshellWithExternalInputStopsMoving() {
        let m = machine(); m.handle(.lidClosed, at: start)
        XCTAssertEqual(m.state, .moving)
        m.handle(.userActivity, at: start.addingTimeInterval(10))
        XCTAssertEqual(m.state, .active)
    }
    func testStaleCornerAndMouseNoLongerAtCornerReject() {
        let m = machine(); enter(m)
        m.handle(.displaySleep(uptime: 100.5, idleSeconds: 0, stillInCorner: false), at: start)
        XCTAssertFalse(m.hasPending)
    }
    func testScreenSaverAfterSleepCancelsPending() {
        let m = machine(); enter(m); sleep(m)
        m.handle(.screenSaverStarted, at: start.addingTimeInterval(0.6))
        m.handle(.confirmSleep, at: start.addingTimeInterval(2))
        XCTAssertEqual(m.state, .displaySleep)
    }
    func testFourCornersAndNegativeDisplayCoordinates() {
        let screens = [("builtIn", CGRect(x: 0, y: 0, width: 1512, height: 982)),
                       ("external", CGRect(x: -1920, y: -200, width: 1920, height: 1080))]
        for (name, point) in [("tl", CGPoint(x: -1920, y: 879)), ("tr", CGPoint(x: -1, y: 879)),
                              ("bl", CGPoint(x: -1920, y: -200)), ("br", CGPoint(x: -1, y: -200))] {
            let hit = HotCornerGeometry.match(point: point, screens: screens, corners: [name], modifiers: 0, requiredModifiers: [:])
            XCTAssertEqual(hit?.corner, name); XCTAssertEqual(hit?.screen, "external")
        }
        XCTAssertNil(HotCornerGeometry.match(point: CGPoint(x: 50, y: 50), screens: screens, corners: ["bl"], modifiers: 0, requiredModifiers: [:]))
    }
    func testModifierHotCornerAndNoConfiguredCorner() {
        let screens = [("one", CGRect(x: 0, y: 0, width: 100, height: 100))]
        let point = CGPoint(x: 0, y: 0)
        XCTAssertNil(HotCornerGeometry.match(point: point, screens: screens, corners: ["bl"], modifiers: 0, requiredModifiers: ["bl": 1 << 17]))
        XCTAssertNotNil(HotCornerGeometry.match(point: point, screens: screens, corners: ["bl"], modifiers: 1 << 17, requiredModifiers: ["bl": 1 << 17]))
        XCTAssertNil(HotCornerGeometry.match(point: point, screens: screens, corners: [], modifiers: 0, requiredModifiers: [:]))
    }
    func testDaylightSavingDurationUsesActualElapsedTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let spring = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8))!
        let next = calendar.date(byAdding: .day, value: 1, to: spring)!
        let session = Session(kind: .away, start: spring, end: next)
        let summary = StatisticsService.summary(date: spring, sessions: [session], focuses: [], hydration: [], settings: AppSettings(), now: next, calendar: calendar)
        XCTAssertEqual(summary.away, 23 * 3600)
    }
    func testRepeatedCyclesNeedFreshCornerAndCannotDoubleCount() {
        let m = machine(); var count = 0
        m.onTransition = { if $0.state == .away { count += 1 } }
        enter(m); sleep(m); m.handle(.displayWake, at: start.addingTimeInterval(1))
        sleep(m, offset: 1.2); m.handle(.displayWake, at: start.addingTimeInterval(1.3))
        XCTAssertEqual(count, 1)
        enter(m, offset: 2); sleep(m, offset: 2.1)
        m.handle(.displayWake, at: start.addingTimeInterval(2.2))
        XCTAssertEqual(count, 2)
    }
    func repository() throws -> Repository {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("WorkRhythmTest-\(UUID())/test.sqlite")
        addTeardownBlock { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        return try Repository(url: url)
    }
    func testPersistenceRecoveryDoesNotInventHours() throws {
        let repo = try repository()
        let ledger = try SessionLedger(repository: repo)
        try ledger.transition(Transition(state: .active, at: start, reason: "input", confidence: 1))
        try repo.saveCheckpoint(Checkpoint(timestamp: start.addingTimeInterval(30), bootID: "one", cleanShutdown: false))
        let reloaded = try SessionLedger(repository: repo)
        try reloaded.recover(checkpoint: repo.checkpoint(), now: start.addingTimeInterval(3600))
        let work = try XCTUnwrap(reloaded.sessions.first { $0.kind == .work })
        XCTAssertEqual(work.duration(at: start.addingTimeInterval(3600)), 30)
        XCTAssertTrue(work.recovered)
        XCTAssertEqual(reloaded.sessions.last?.kind, .unknown)
    }
    func testIdleAndFocusDoNotSplitWorkButAwayDoes() throws {
        let ledger = try SessionLedger(repository: repository())
        for (i, state) in [WorkstationState.active, .idle, .focus, .away, .active].enumerated() {
            try ledger.transition(Transition(state: state, at: start.addingTimeInterval(Double(i * 60)), reason: "", confidence: 1))
        }
        let work = ledger.sessions.filter { $0.kind == .work }
        XCTAssertEqual(work.count, 2)
        XCTAssertEqual(work.first?.duration(at: start), 180)
    }
    func testCrossMidnightSplitsDurationNotCount() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let midnight = cal.startOfDay(for: start)
        let s = Session(kind: .away, start: midnight.addingTimeInterval(-120), end: midnight.addingTimeInterval(300))
        let before = StatisticsService.summary(date: midnight.addingTimeInterval(-3600), sessions: [s], focuses: [], hydration: [], settings: AppSettings(), now: midnight.addingTimeInterval(600), calendar: cal)
        let after = StatisticsService.summary(date: midnight, sessions: [s], focuses: [], hydration: [], settings: AppSettings(), now: midnight.addingTimeInterval(600), calendar: cal)
        XCTAssertEqual(before.away, 120); XCTAssertEqual(before.breaks, 1)
        XCTAssertEqual(after.away, 300); XCTAssertEqual(after.breaks, 0)
    }
    func testLockAndLidAreCountedAsDeparturesWithoutDoubleCountingLockUpgrade() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let midnight = cal.startOfDay(for: start)
        let sessions = [
            Session(kind: .away, start: midnight.addingTimeInterval(60),
                    end: midnight.addingTimeInterval(120), trigger: "hot_corner:br"),
            Session(kind: .locked, start: midnight.addingTimeInterval(180),
                    end: midnight.addingTimeInterval(300), trigger: "lock"),
            Session(kind: .moving, start: midnight.addingTimeInterval(360),
                    end: midnight.addingTimeInterval(540), trigger: "lid_closed_possible_moving"),
            Session(kind: .locked, start: midnight.addingTimeInterval(600),
                    end: midnight.addingTimeInterval(600), trigger: "lock"),
            Session(kind: .away, start: midnight.addingTimeInterval(600),
                    end: midnight.addingTimeInterval(660), trigger: "manual_lock_recent_input"),
            Session(kind: .displaySleep, start: midnight.addingTimeInterval(720),
                    end: midnight.addingTimeInterval(900), trigger: "automatic")
        ]
        let summary = StatisticsService.summary(date: midnight, sessions: sessions, focuses: [],
                                                hydration: [], settings: AppSettings(),
                                                now: midnight.addingTimeInterval(1000), calendar: cal)
        XCTAssertEqual(summary.away, 120)
        XCTAssertEqual(summary.locked, 120)
        XCTAssertEqual(summary.moving, 180)
        XCTAssertEqual(summary.leave, 420)
        XCTAssertEqual(summary.breaks, 4)
        XCTAssertEqual(summary.lockLeaves, 2)
        XCTAssertEqual(summary.lidLeaves, 1)
        XCTAssertEqual(summary.averageBreak, 105)
    }
    func testFocusPauseExcludesAwayAndPersists() throws {
        let repo = try repository(); let ledger = try SessionLedger(repository: repo)
        try ledger.startFocus(minutes: 25, at: start)
        try ledger.pauseFocus(at: start.addingTimeInterval(100))
        try ledger.resumeFocus(at: start.addingTimeInterval(400))
        try ledger.finishFocus(at: start.addingTimeInterval(500), completed: false)
        let focus = try XCTUnwrap(repo.focuses().first)
        XCTAssertEqual(focus.actualDuration, 200)
        XCTAssertEqual(focus.pauseDuration, 300)
        XCTAssertTrue(focus.interrupted)
    }
    func testDepartureLabelsPersistForLockAndLid() throws {
        let repo = try repository()
        let ledger = try SessionLedger(repository: repo)
        try ledger.transition(Transition(state: .locked, at: start, reason: "lock", confidence: 1))
        try ledger.transition(Transition(state: .active, at: start.addingTimeInterval(60), reason: "unlock", confidence: 1))
        try ledger.transition(Transition(state: .moving, at: start.addingTimeInterval(120),
                                         reason: "lid_closed_possible_moving", confidence: 1))
        let locked = try XCTUnwrap(ledger.sessions.first { $0.kind == .locked })
        let lid = try XCTUnwrap(ledger.sessions.first { $0.kind == .moving })
        try ledger.label(id: locked.id, value: "会议")
        try ledger.label(id: lid.id, value: "用餐")
        let restored = try SessionLedger(repository: repo)
        XCTAssertEqual(restored.sessions.first { $0.id == locked.id }?.label, "会议")
        XCTAssertEqual(restored.sessions.first { $0.id == lid.id }?.label, "用餐")
    }
    func testReminderSuppressionGraceAndFocus() {
        var settings = AppSettings(); settings.hydrationMinutes = 1; settings.returnGraceSeconds = 120
        var policy = ReminderPolicy(now: start, settings: settings, lastDrink: start.addingTimeInterval(-3600))
        for state in [WorkstationState.away, .moving, .systemSleep, .displaySleep, .locked] {
            XCTAssertTrue(policy.due(state: state, awake: true, locked: false, workStart: start, settings: settings, now: start.addingTimeInterval(200)).isEmpty)
        }
        XCTAssertTrue(policy.due(state: .active, awake: true, locked: false, workStart: nil, settings: settings, now: start.addingTimeInterval(50)).isEmpty)
        XCTAssertEqual(policy.due(state: .active, awake: true, locked: false, workStart: nil, settings: settings, now: start.addingTimeInterval(121)), ["water"])
    }
    func testDatabaseRollbackAndBackup() throws {
        let repo = try repository()
        enum Failure: Error { case expected }
        XCTAssertThrowsError(try repo.transaction {
            try repo.save(Session(kind: .away, start: start))
            throw Failure.expected
        })
        XCTAssertTrue(try repo.sessions().isEmpty)
        try repo.save(Session(kind: .work, start: start))
        let backup = repo.url.deletingLastPathComponent().appendingPathComponent("backup.sqlite")
        try repo.backup(to: backup)
        XCTAssertEqual(try Repository(url: backup).sessions().count, 1)
    }
}
