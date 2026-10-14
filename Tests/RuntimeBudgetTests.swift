import XCTest
@testable import WorkRhythmCore

final class RuntimeBudgetTests: XCTestCase {
    func testSleepAndLockedCadencePreserveRecoveryDeadline() {
        XCTAssertNil(RuntimeBudget.heartbeatInterval(sleeping: true, displayAwake: false, locked: true))
        XCTAssertEqual(RuntimeBudget.heartbeatInterval(sleeping: false, displayAwake: true, locked: false), 15)
        XCTAssertEqual(RuntimeBudget.heartbeatInterval(sleeping: false, displayAwake: false, locked: false), 30)
        XCTAssertEqual(RuntimeBudget.heartbeatInterval(sleeping: false, displayAwake: true, locked: true), 30)
        // A transition/checkpoint between ticks must not push crash recovery out to 45 seconds.
        XCTAssertEqual(RuntimeBudget.heartbeatDelay(interval: 15, sinceCheckpoint: 28), 2)
        XCTAssertEqual(RuntimeBudget.heartbeatDelay(interval: 30, sinceCheckpoint: 17), 13)
        XCTAssertEqual(RuntimeBudget.heartbeatDelay(interval: 15, sinceCheckpoint: 0), 15)
        XCTAssertEqual(RuntimeBudget.heartbeatDelay(interval: 30, sinceCheckpoint: 40), 0.1)
    }
    func testAnimationBudgetUnderPowerAndThermalConstraints() {
        XCTAssertEqual(RuntimeBudget.animationFPS(lowPower: false, thermallyConstrained: false), 12)
        XCTAssertEqual(RuntimeBudget.animationFPS(lowPower: true, thermallyConstrained: false), 6)
        XCTAssertEqual(RuntimeBudget.animationFPS(lowPower: false, thermallyConstrained: true), 0)
        XCTAssertEqual(RuntimeBudget.animationFPS(lowPower: true, thermallyConstrained: true), 0)
    }
    func testPrecomputedCornerGeometryAndReconfiguration() {
        let screens = [("external", CGRect(x: -1600, y: -200, width: 1600, height: 1000)),
                       ("main", CGRect(x: 0, y: 0, width: 1440, height: 900))]
        let targets = HotCornerGeometry.targets(screens: screens, corners: ["tl", "br"], requiredModifiers: ["tl": 8])
        XCTAssertNil(HotCornerGeometry.match(point: CGPoint(x: -1600, y: 799), targets: targets, modifiers: 0))
        let match = HotCornerGeometry.match(point: CGPoint(x: -1597, y: 796), targets: targets, modifiers: 8)
        XCTAssertEqual(match?.corner, "tl"); XCTAssertEqual(match?.screen, "external")
        XCTAssertNil(HotCornerGeometry.match(point: CGPoint(x: -1596, y: 795), targets: targets, modifiers: 8))
        XCTAssertEqual(HotCornerGeometry.match(point: CGPoint(x: 1439, y: 0), targets: targets, modifiers: 0)?.corner, "br")
        let changed = HotCornerGeometry.targets(screens: screens, corners: ["tr"], requiredModifiers: [:])
        XCTAssertNil(HotCornerGeometry.match(point: CGPoint(x: 1439, y: 0), targets: changed, modifiers: 0))
        XCTAssertEqual(HotCornerGeometry.match(point: CGPoint(x: 1439, y: 899), targets: changed, modifiers: 0)?.corner, "tr")
    }
}
