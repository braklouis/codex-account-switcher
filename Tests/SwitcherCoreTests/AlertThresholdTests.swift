import XCTest
@testable import SwitcherCore
final class AlertThresholdTests: XCTestCase {
    func testThresholdsAndDeduplication() {
        var state = AlertThresholds()
        XCTAssertNil(state.evaluate(remaining: 75, resetsAt: 1000))
        XCTAssertEqual(state.evaluate(remaining: 74, resetsAt: 1000), 75)
        XCTAssertNil(state.evaluate(remaining: 73, resetsAt: 1000))
        XCTAssertEqual(state.evaluate(remaining: 49, resetsAt: 1000), 50)
        XCTAssertEqual(state.evaluate(remaining: 24, resetsAt: 1000), 25)
        XCTAssertNil(state.evaluate(remaining: 1, resetsAt: 1000))
    }
    func testJumpOnlyNotifiesLowestAndResetRearms() {
        var state = AlertThresholds()
        XCTAssertEqual(state.evaluate(remaining: 10, resetsAt: 1000), 25)
        XCTAssertNil(state.evaluate(remaining: 10, resetsAt: 1000))
        XCTAssertEqual(state.evaluate(remaining: 70, resetsAt: 2000, now: 1500), 75)
    }
    func testPersistsAcrossRelaunch() throws {
        var state = AlertThresholds()
        _ = state.evaluate(remaining: 49, resetsAt: 1000)
        var restored = try JSONDecoder().decode(AlertThresholds.self, from: JSONEncoder().encode(state))
        XCTAssertNil(restored.evaluate(remaining: 48, resetsAt: 1000))
    }
    func testResetEstimateChangesDoNotRepeatAfterRelaunch() throws {
        var state = AlertThresholds()
        XCTAssertEqual(state.evaluate(remaining: 51, resetsAt: 10000, now: 100), 75)
        var restored = try JSONDecoder().decode(AlertThresholds.self, from: JSONEncoder().encode(state))
        XCTAssertNil(restored.evaluate(remaining: 51, resetsAt: 10002, now: 200))
        XCTAssertNil(restored.evaluate(remaining: 51, resetsAt: nil, now: 300))
        XCTAssertNil(restored.evaluate(remaining: 51, resetsAt: 10004, now: 400))
        XCTAssertEqual(restored.evaluate(remaining: 49, resetsAt: 10004, now: 500), 50)
    }
    func testMissingResetDoesNotRearmOnQuotaFluctuation() {
        var state = AlertThresholds()
        XCTAssertEqual(state.evaluate(remaining: 21, resetsAt: nil), 25)
        XCTAssertNil(state.evaluate(remaining: 60, resetsAt: nil))
        XCTAssertNil(state.evaluate(remaining: 21, resetsAt: nil))
    }
}
