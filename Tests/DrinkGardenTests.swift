import XCTest
@testable import WorkRhythmCore

final class DrinkGardenTests: XCTestCase {
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    func event(_ type: DrinkPreset?, _ ml: Int = 500) -> HydrationEvent {
        HydrationEvent(timestamp: date, source: "test", amountML: ml, drinkPresetID: type?.rawValue)
    }
    func testSingleDrinkFlowersAndWaterColorsAreDistinct() {
        let expected: [GardenRecipe] = [.dew, .sunshine, .velvet, .starlight, .teaBell, .milkLily]
        for (type, recipe) in zip(DrinkPreset.allCases, expected) {
            let garden = DrinkGarden(events: [event(type)])
            XCTAssertEqual(garden.recipe, recipe)
            XCTAssertEqual(garden.unlocked, [recipe])
        }
    }
    func testRecipesUsePresenceNotAdditionalVolumeAndOrderDoesNotMatter() {
        let a = [event(.waterBottle), event(.coffee, 250)]
        XCTAssertEqual(DrinkGarden(events: a).recipe, .morning)
        XCTAssertEqual(DrinkGarden(events: a), DrinkGarden(events: a.reversed()))
        XCTAssertEqual(DrinkGarden(events: [event(.milkTea), event(.coffee)]).recipe, .latte)
        XCTAssertEqual(DrinkGarden(events: [event(.milkTea), event(.waterBottle)]).recipe, .peach)
        XCTAssertEqual(DrinkGarden(events: DrinkPreset.allCases.map { event($0) }).recipe, .rainbow)
        let one = DrinkGarden(events: [event(.coffee, 500)])
        let split = DrinkGarden(events: [event(.coffee, 250), event(.coffee, 250)])
        XCTAssertEqual(one, split)
    }
    func testSliderStopsAndLegacyVolumeProjection() {
        XCTAssertEqual(DrinkPreset.displayOrder.map(\.shortTitle), ["茶", "水", "奶茶", "牛奶", "可乐", "咖啡"])
        XCTAssertEqual(DrinkAmount.steps, [150, 300, 450, 600])
        for step in DrinkAmount.steps {
            XCTAssertTrue(DrinkAmount.isSliderValue(step))
            XCTAssertEqual(DrinkAmount.sliderValue(step), step)
        }
        for value in [0, 149, 250, 330, 500, 601, 700] { XCTAssertFalse(DrinkAmount.isSliderValue(value)) }
        XCTAssertEqual(DrinkAmount.sliderValue(500), 450)
        XCTAssertEqual(DrinkAmount.sliderValue(700), 600)
        XCTAssertEqual(DrinkAmount.sliderValue(0), 150)
        XCTAssertEqual(DrinkAmount.sliderValue(330), 300)
    }
    func testTeaMilkPersistenceUndoAndLegacyRainbow() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repo = try Repository(url: directory.appendingPathComponent("test.sqlite"))
        let ledger = try SessionLedger(repository: repo)
        try ledger.drink(at: date, source: "slider", amountML: 150, drinkPresetID: "tea")
        try ledger.drink(at: date + 1, source: "slider", amountML: 600, drinkPresetID: "milk")
        let events = try repo.hydration()
        XCTAssertEqual(events.map(\.amountML), [150, 600])
        XCTAssertEqual(events.map(\.drinkTitle), ["一杯茶", "一杯牛奶"])
        XCTAssertEqual(DrinkGarden(events: events).recipe, .matcha)
        let csv = StatisticsService.csv(sessions: [], focuses: [], hydration: events, now: date + 2)
        XCTAssertTrue(csv.contains("\"tea\"")); XCTAssertTrue(csv.contains("\"milk\""))
        try ledger.undoDrink(id: events[1].id, at: date + 2)
        XCTAssertEqual(DrinkGarden(events: try repo.hydration()).recipe, .teaBell)
        XCTAssertEqual(DrinkGarden(events: [event(.milk), event(.coffee)]).recipe, .creamDahlia)
        XCTAssertEqual(DrinkGarden(events: [.waterBottle, .coffee, .milkTea, .cola].map { event($0) }).recipe, .rainbow)
    }
    func testUndoAndDayBoundaryRecomputeRecipes() {
        var coffee = event(.coffee)
        coffee.voidedAt = date + 1
        let water = event(.waterBottle)
        var yesterday = event(.milkTea)
        yesterday.timestamp = Calendar.current.startOfDay(for: date) - 1
        let p = HydrationProgress(events: [water, coffee, yesterday], plan: HydrationPlan(), date: date)
        XCTAssertEqual(p.garden.recipe, .dew)
        XCTAssertEqual(p.totalML, 500)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: date)!
        XCTAssertFalse(HydrationProgress(events: [water, coffee], plan: HydrationPlan(), date: tomorrow).garden.hasDrinks)
    }
    func testUnknownVolumesAndUnknownTypesDoNotInventIngredients() {
        let legacy = HydrationEvent(timestamp: date, source: "old")
        let unknown = HydrationEvent(timestamp: date, source: "future", amountML: 500, drinkPresetID: "future")
        let garden = DrinkGarden(events: [legacy, unknown])
        XCTAssertTrue(garden.unlocked.isEmpty)
        XCTAssertEqual(DrinkGarden(events: [event(nil)]).recipe, .dew)
    }
    func testRemovedIvyMapsToGardenWithoutChangingSavedAmounts() throws {
        let json = Data(#"{"dailyTargetML":1600,"plannedDrinks":8,"themeID":"ivy","presetVolumesML":{"coffee":500}}"#.utf8)
        let plan = try JSONDecoder().decode(HydrationPlan.self, from: json)
        XCTAssertEqual(plan.theme, .flowers)
        XCTAssertEqual(plan.servingML(for: .coffee), 500)
        XCTAssertEqual(HydrationTheme.allCases, [.bottle, .flowers])
    }
    func testActualAmountInputValidationAndPreferencesRoundtrip() throws {
        XCTAssertEqual(DrinkAmount.parse(" 500 "), 500)
        XCTAssertEqual(DrinkAmount.parse("10"), 10)
        XCTAssertEqual(DrinkAmount.parse("2000"), 2000)
        for input in ["", "0", "-10", "2001", "500ml", "abc", "250.5"] { XCTAssertNil(DrinkAmount.parse(input)) }
        var plan = HydrationPlan()
        plan.lastDrinkPresetID = DrinkPreset.coffee.rawValue
        plan.setServingML(500, for: .coffee)
        plan.setServingML(700, for: .milkTea)
        let restored = try JSONDecoder().decode(HydrationPlan.self, from: JSONEncoder().encode(plan))
        XCTAssertEqual(restored.selectedDrink, .coffee)
        XCTAssertEqual(restored.servingML(for: .coffee), 500)
        XCTAssertEqual(restored.servingML(for: .milkTea), 700)
    }
    func testGardenTrophyAwardsOnceUpgradesAndSurvivesUndoRestart() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repo = try Repository(url: directory.appendingPathComponent("test.sqlite"))
        let ledger = try SessionLedger(repository: repo)
        var plan = HydrationPlan()
        plan.dailyTargetML = 300

        try ledger.drink(at: date, source: "slider", amountML: 150, drinkPresetID: DrinkPreset.coffee.rawValue)
        XCTAssertNil(try ledger.awardGardenTrophy(for: date, plan: plan))
        try ledger.drink(at: date + 1, source: "slider", amountML: 150, drinkPresetID: DrinkPreset.coffee.rawValue)
        let first = try XCTUnwrap(ledger.awardGardenTrophy(for: date, plan: plan))
        XCTAssertEqual(first.recipe, .sunshine)
        XCTAssertEqual(first.totalML, 300)
        XCTAssertEqual(first.targetML, 300)

        try ledger.drink(at: date + 2, source: "slider", amountML: 150, drinkPresetID: DrinkPreset.milk.rawValue)
        let upgraded = try XCTUnwrap(ledger.awardGardenTrophy(for: date, plan: plan))
        XCTAssertEqual(upgraded.id, first.id)
        XCTAssertEqual(upgraded.recipe, .creamDahlia)
        XCTAssertEqual(ledger.gardenTrophies.count, 1)
        for event in ledger.hydration { try ledger.undoDrink(id: event.id, at: date + 3) }
        XCTAssertEqual(ledger.gardenTrophies.first?.recipe, .creamDahlia)

        let restored = try SessionLedger(repository: repo)
        XCTAssertEqual(restored.gardenTrophies, ledger.gardenTrophies)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: date)!
        try restored.drink(at: tomorrow, source: "slider", amountML: 300, drinkPresetID: DrinkPreset.tea.rawValue)
        _ = try restored.awardGardenTrophy(for: tomorrow, plan: plan)
        XCTAssertEqual(restored.gardenTrophies.count, 2)
    }
    func testHistoricalHydrationBackfillsStableTrophies() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repo = try Repository(url: directory.appendingPathComponent("test.sqlite"))
        let writer = try SessionLedger(repository: repo)
        try writer.drink(at: date, source: "old", amountML: 600, drinkPresetID: DrinkPreset.tea.rawValue)
        let restored = try SessionLedger(repository: repo)
        var plan = HydrationPlan()
        plan.dailyTargetML = 600
        try restored.backfillGardenTrophies(plan: plan)
        try restored.backfillGardenTrophies(plan: plan)
        let trophy = try XCTUnwrap(restored.gardenTrophies.first)
        XCTAssertEqual(restored.gardenTrophies.count, 1)
        XCTAssertEqual(trophy.recipe, .teaBell)
        XCTAssertEqual(trophy.totalML, 600)
        XCTAssertEqual(trophy.targetML, 600)
        XCTAssertEqual(try Repository(url: repo.url).gardenTrophies().count, 1)
    }
}
