import Foundation
import XCTest
@testable import SwitcherCore

final class UsagePaceEstimateTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    func testRejectsZeroOrMissingInvalidInputs() {
        let reset = start.addingTimeInterval(3_600)
        XCTAssertNil(UsagePaceEstimate(
            remainingPercent: 50,
            durationMinutes: 60,
            resetsAt: reset,
            now: start))
        XCTAssertNil(UsagePaceEstimate(
            remainingPercent: 50,
            durationMinutes: 0,
            resetsAt: reset,
            now: start.addingTimeInterval(1)))
        XCTAssertNil(UsagePaceEstimate(
            remainingPercent: 50,
            durationMinutes: 60,
            resetsAt: start.addingTimeInterval(3_601),
            now: start))
    }

    func testEstimatesLinearPaceAndDeficit() {
        let duration = 60.0 * 60
        let now = start.addingTimeInterval(duration * 0.25)
        let estimate = UsagePaceEstimate(
            remainingPercent: 25,
            durationMinutes: 60,
            resetsAt: start.addingTimeInterval(duration),
            now: now)

        XCTAssertNotNil(estimate)
        XCTAssertEqual(estimate?.expectedRemainingPercent ?? -1, 50, accuracy: 0.0001)
        XCTAssertEqual(estimate?.deficitPercent ?? -1, 25, accuracy: 0.0001)
        XCTAssertEqual(estimate?.estimatedSecondsUntilEmpty ?? -1, duration / 6, accuracy: 0.0001)
        XCTAssertFalse(estimate?.willLastToReset ?? true)
    }

    func testSufficientUsageWillLastToReset() {
        let duration = 60.0 * 60
        let estimate = UsagePaceEstimate(
            remainingPercent: 90,
            durationMinutes: 60,
            resetsAt: start.addingTimeInterval(duration),
            now: start.addingTimeInterval(duration * 0.5))

        XCTAssertNotNil(estimate)
        XCTAssertTrue(estimate?.willLastToReset ?? false)
        XCTAssertEqual(estimate?.estimatedSecondsUntilEmpty ?? -1, duration * 9, accuracy: 0.0001)
    }
}
