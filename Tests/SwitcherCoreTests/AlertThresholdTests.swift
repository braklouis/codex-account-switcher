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
        XCTAssertEqual(state.evaluate(remaining: 70, resetsAt: 2000), 75)
    }
    func testPersistsAcrossRelaunch() throws {
        var state = AlertThresholds()
        _ = state.evaluate(remaining: 49, resetsAt: 1000)
        var restored = try JSONDecoder().decode(AlertThresholds.self, from: JSONEncoder().encode(state))
        XCTAssertNil(restored.evaluate(remaining: 48, resetsAt: 1000))
    }
}
