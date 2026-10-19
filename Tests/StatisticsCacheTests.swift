import XCTest
@testable import WorkRhythmCore

final class StatisticsCacheTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    func testClockTickInvalidatesCurrentDayButKeepsHistoricalSummary() {
        let cache = DailySummaryCache()
        let today = Date(timeIntervalSince1970: 1_792_022_400)
        let history = today.addingTimeInterval(-86400)
        var todayLoads = 0
        var historyLoads = 0

        _ = cache.value(for: today, calendar: calendar) {
            todayLoads += 1
            return DailySummary(date: today)
        }
        _ = cache.value(for: history, calendar: calendar) {
            historyLoads += 1
            return DailySummary(date: history)
        }

        cache.invalidate(today.addingTimeInterval(15), calendar: calendar)
        _ = cache.value(for: today, calendar: calendar) {
            todayLoads += 1
            return DailySummary(date: today)
        }
        _ = cache.value(for: history, calendar: calendar) {
            historyLoads += 1
            return DailySummary(date: history)
        }

        XCTAssertEqual(todayLoads, 2)
        XCTAssertEqual(historyLoads, 1)
        XCTAssertEqual(cache.count, 2)
    }

    func testDataRevisionInvalidatesEveryCachedDay() {
        let cache = DailySummaryCache()
        let day = Date(timeIntervalSince1970: 1_792_022_400)
        var loads = 0
        for offset in [0.0, -86400] {
            _ = cache.value(for: day.addingTimeInterval(offset), calendar: calendar) {
                loads += 1
                return DailySummary(date: day.addingTimeInterval(offset))
            }
        }
        cache.invalidateAll()
        _ = cache.value(for: day, calendar: calendar) {
            loads += 1
            return DailySummary(date: day)
        }
        XCTAssertEqual(loads, 3)
        XCTAssertEqual(cache.count, 1)
    }
}
