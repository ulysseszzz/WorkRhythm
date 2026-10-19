import XCTest
@testable import WorkRhythmCore

final class HydrationTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func testPresetDefaultsLegacyDecodeAndCapacityPersistence() throws {
        let old = try JSONDecoder().decode(HydrationPlan.self, from: Data(#"{"dailyTargetML":1600,"plannedDrinks":8}"#.utf8))
        XCTAssertEqual(DrinkPreset.allCases.map { old.servingML(for: $0) }, [500, 240, 350, 330, 500, 250])
        var plan = old
        plan.setServingML(550, for: .waterBottle)
        plan.setServingML(360, for: .coffee)
        let restored = try JSONDecoder().decode(HydrationPlan.self, from: JSONEncoder().encode(plan))
        XCTAssertEqual(restored.servingML(for: .waterBottle), 550)
        XCTAssertEqual(restored.servingML(for: .coffee), 360)
        XCTAssertEqual(restored.servingML(for: .cola), 330)
        XCTAssertEqual(restored.servingML, 200)
        plan.setServingML(-5, for: .coffee)
        plan.setServingML(9999, for: .milkTea)
        XCTAssertEqual(plan.servingML(for: .coffee), 10)
        XCTAssertEqual(plan.servingML(for: .milkTea), 2000)
    }
    func testLegacyUniformStepsMigrateOnceWithoutChangingHistory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try Repository(url: directory.appendingPathComponent("test.sqlite"))
        var settings = AppSettings()
        var plan = settings.waterPlan
        plan.presetVolumesML = ["waterBottle": 450, "tea": 450, "milk": 600, "coffee": 500]
        settings.hydrationPlan = plan
        try repository.saveSettings(settings)
        let ledger = try SessionLedger(repository: repository)
        try ledger.drink(at: now, source: "legacy", amountML: 450, drinkPresetID: DrinkPreset.waterBottle.rawValue)

        var migrated = try repository.settings().waterPlan
        XCTAssertTrue(migrated.migrateLegacyServingOptions())
        XCTAssertEqual(migrated.servingML(for: .waterBottle), 500)
        XCTAssertEqual(migrated.servingML(for: .tea), 500)
        XCTAssertEqual(migrated.servingML(for: .milk), 500)
        XCTAssertEqual(migrated.servingML(for: .coffee), 500)
        XCTAssertEqual(migrated.servingOptionsVersion, 1)
        settings.hydrationPlan = migrated
        try repository.saveSettings(settings)
        XCTAssertEqual(try repository.hydration().first?.amountML, 450)

        migrated = try repository.settings().waterPlan
        XCTAssertFalse(migrated.migrateLegacyServingOptions())
        XCTAssertEqual(migrated.servingML(for: .waterBottle), 500)
    }
    func testMixedDrinksRetainTypeVolumeUndoAndCSV() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repo = try Repository(url: directory.appendingPathComponent("test.sqlite"))
        let ledger = try SessionLedger(repository: repo)
        var plan = HydrationPlan()
        let originalTypes: [DrinkPreset] = [.waterBottle, .coffee, .milkTea, .cola]
        for (i, preset) in originalTypes.enumerated() {
            try ledger.drink(at: now.addingTimeInterval(Double(i)), source: "preset", amountML: plan.servingML(for: preset),
                             drinkPresetID: preset.rawValue)
        }
        let restored = try SessionLedger(repository: repo)
        XCTAssertEqual(restored.hydration.map(\.drinkPresetID), originalTypes.map { Optional($0.rawValue) })
        XCTAssertEqual(restored.hydration.map(\.amountML), [500, 240, 350, 330])
        XCTAssertEqual(HydrationProgress(events: restored.hydration, plan: plan, date: now).totalML, 1420)
        plan.setServingML(600, for: .milkTea)
        var settings = AppSettings(); settings.hydrationPlan = plan
        try repo.saveSettings(settings)
        XCTAssertEqual(try repo.settings().waterPlan.servingML(for: .milkTea), 600)
        XCTAssertEqual(try repo.hydration()[2].amountML, 350)
        try restored.undoDrink(id: restored.hydration.last!.id, at: now + 5)
        let reloaded = try repo.hydration()
        let progress = HydrationProgress(events: reloaded, plan: plan, date: now)
        XCTAssertEqual(progress.totalML, 1090)
        XCTAssertEqual(progress.count, 3)
        XCTAssertEqual(progress.lastEntry?.drinkTitle, "一杯奶茶")
        XCTAssertEqual(progress.lastEntry?.amountML, 350)
        let csv = StatisticsService.csv(sessions: [Session(kind: .work, start: now)], focuses: [],
                                         hydration: reloaded, now: now + 6)
        XCTAssertTrue(csv.contains("voided_at,drink_preset"))
        XCTAssertTrue(csv.contains("\"coffee\""))
        XCTAssertTrue(csv.contains("\"voided\",\"330\""))
        XCTAssertTrue(csv.split(separator: "\n").allSatisfy { $0.split(separator: ",", omittingEmptySubsequences: false).count == 12 })
        let summary = StatisticsService.summary(date: now, sessions: [], focuses: [], hydration: reloaded,
                                               settings: settings, now: now + 6)
        XCTAssertEqual(summary.waterML, 1090)
    }
    func testThemeMigrationPersistenceAndUnchangedProgress() throws {
        let oldPlan = Data(#"{"dailyTargetML":1800,"plannedDrinks":9,"customServingML":250}"#.utf8)
        let decoded = try JSONDecoder().decode(HydrationPlan.self, from: oldPlan)
        XCTAssertEqual(decoded.theme, .bottle)
        XCTAssertTrue(decoded.motionEnabled)
        XCTAssertEqual(decoded.servingML, 250)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try Repository(url: directory.appendingPathComponent("test.sqlite"))
        let ledger = try SessionLedger(repository: repository)
        try ledger.drink(at: now, source: "hydration_flowers", amountML: 250)
        for theme in HydrationTheme.allCases {
            var settings = AppSettings()
            var plan = decoded; plan.themeID = theme.rawValue; plan.ambientMotion = false
            settings.hydrationPlan = plan
            try repository.saveSettings(settings)
            let restored = try repository.settings().waterPlan
            XCTAssertEqual(restored.theme, theme); XCTAssertFalse(restored.motionEnabled)
            let progress = HydrationProgress(events: try repository.hydration(), plan: restored, date: now)
            XCTAssertEqual(progress.totalML, 250); XCTAssertEqual(progress.count, 1)
        }
        var future = decoded; future.themeID = "unknown_future_theme"
        XCTAssertEqual(future.theme, .bottle)
    }
    func testLegacySettingsAndEventsRemainReadableWithoutInventedVolumes() throws {
        let oldEvent = """
        {"id":"AE05023B-CBCE-4454-A766-C6609317AD95","timestamp":0,"source":"menu"}
        """
        let event = try JSONDecoder().decode(HydrationEvent.self, from: Data(oldEvent.utf8))
        XCTAssertNil(event.amountML); XCTAssertNil(event.voidedAt)
        XCTAssertNil(event.drinkPresetID); XCTAssertEqual(event.drinkTitle, "饮水")
        var original = AppSettings()
        original.hydrationMinutes = 120; original.corner = "tl"
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        object.removeValue(forKey: "hydrationPlan")
        let old = try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(old.hydrationMinutes, 120); XCTAssertEqual(old.corner, "tl")
        XCTAssertEqual(old.waterPlan.servingML, 200)
        XCTAssertEqual(old.waterPlan.targetML, 1600)
    }
    func testPlanSuggestionsOverridesAndBounds() {
        var plan = HydrationPlan()
        XCTAssertEqual(plan.suggestedServingML, 200)
        plan.dailyTargetML = 1800; plan.plannedDrinks = 7
        XCTAssertEqual(plan.suggestedServingML, 260)
        plan.customServingML = 150
        XCTAssertEqual(plan.servingML, 150)
        plan.plannedDrinks = 0; plan.dailyTargetML = -1
        XCTAssertEqual(plan.targetCount, 1); XCTAssertEqual(plan.targetML, 200)
        plan.customServingML = nil; plan.dailyTargetML = 6000; plan.plannedDrinks = 1
        XCTAssertEqual(plan.suggestedServingML, 2000)
        XCTAssertEqual(plan.servingML, plan.suggestedServingML)
    }
    func testVolumeAndUndoPersistAcrossRestartAndCSVMarksUndo() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try Repository(url: directory.appendingPathComponent("test.sqlite"))
        let ledger = try SessionLedger(repository: repository)
        try ledger.drink(at: now, source: "bottle", amountML: 200)
        try ledger.drink(at: now.addingTimeInterval(1), source: "notification", amountML: 250)
        let last = try XCTUnwrap(ledger.hydration.last)
        try ledger.undoDrink(id: last.id, at: now.addingTimeInterval(2))
        let reloaded = try SessionLedger(repository: repository)
        let progress = HydrationProgress(events: reloaded.hydration, plan: HydrationPlan(), date: now)
        XCTAssertEqual(progress.totalML, 200); XCTAssertEqual(progress.count, 1)
        XCTAssertEqual(progress.fraction, 0.125)
        let csv = StatisticsService.csv(sessions: [], focuses: [], hydration: reloaded.hydration, now: now)
        XCTAssertTrue(csv.contains("amount_ml,voided_at"))
        XCTAssertTrue(csv.contains("\"voided\",\"250\""))
        let summary = StatisticsService.summary(date: now, sessions: [], focuses: [], hydration: reloaded.hydration, settings: AppSettings(), now: now)
        XCTAssertEqual(summary.waterML, 200); XCTAssertEqual(summary.water, 1)
    }
    func testDayBoundaryOldRecordsCompletionAndOverGoal() {
        let day = Calendar.current.startOfDay(for: now)
        let events = [
            HydrationEvent(timestamp: day.addingTimeInterval(-1), source: "yesterday", amountML: 500),
            HydrationEvent(timestamp: now, source: "legacy"),
            HydrationEvent(timestamp: now, source: "bottle", amountML: 1700)
        ]
        let progress = HydrationProgress(events: events, plan: HydrationPlan(), date: now)
        XCTAssertEqual(progress.totalML, 1700); XCTAssertEqual(progress.count, 2)
        XCTAssertEqual(progress.legacyCount, 1); XCTAssertTrue(progress.completed)
        XCTAssertEqual(progress.fraction, 1); XCTAssertEqual(progress.remainingDrinks, 0)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: day)!
        XCTAssertEqual(HydrationProgress(events: events, plan: HydrationPlan(), date: tomorrow).totalML, 0)
    }
    func testChangingServingPreservesHistoryAndUndoIsIdempotent() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try Repository(url: directory.appendingPathComponent("test.sqlite"))
        let ledger = try SessionLedger(repository: repository)
        var settings = AppSettings()
        try ledger.drink(at: now, source: "bottle", amountML: settings.waterPlan.servingML)
        var plan = settings.waterPlan; plan.customServingML = 300; settings.hydrationPlan = plan
        try repository.saveSettings(settings)
        try ledger.drink(at: now, source: "bottle", amountML: settings.waterPlan.servingML)
        XCTAssertEqual(try repository.hydration().map(\.amountML), [200, 300])
        XCTAssertEqual(try repository.settings().waterPlan.servingML, 300)
        let id = ledger.hydration[1].id
        try ledger.undoDrink(id: id, at: now); try ledger.undoDrink(id: id, at: now)
        XCTAssertEqual(HydrationProgress(events: ledger.hydration, plan: plan, date: now).totalML, 200)
    }
}
