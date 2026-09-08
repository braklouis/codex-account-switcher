import XCTest
@testable import SwitcherCore
final class MenuQuotaSummaryTests: XCTestCase {
    func decode(_ text: String) throws -> QuotaResponse { try JSONDecoder().decode(QuotaResponse.self, from: Data(text.utf8)) }
    func testPrimaryCanBeWeeklyWithoutShortWindow() throws {
        let quota = try decode(#"{"rateLimits":{"primary":{"usedPercent":46,"windowDurationMins":10080}}}"#)
        let summary = MenuQuotaSummary(quota: quota)
        XCTAssertNil(summary.shortTerm)
        XCTAssertEqual(summary.weekly?.remaining, 54)
    }
    func testOnlyCodexBucketNotReserve() throws {
        let quota = try decode(#"{"rateLimitsByLimitId":{"reserve":{"primary":{"usedPercent":0,"windowDurationMins":300}},"codex":{"primary":{"usedPercent":30,"windowDurationMins":300},"secondary":{"usedPercent":10,"windowDurationMins":10080}}}}"#)
        XCTAssertEqual(MenuQuotaSummary(quota: quota).shortTerm?.remaining, 70)
        XCTAssertEqual(MenuQuotaSummary(quota: quota).weekly?.remaining, 90)
        XCTAssertNil(MenuQuotaSummary(quota: quota, unavailable: true).weekly)
    }
    func testMissingCodexIsNotAnotherModelQuota() throws {
        let quota = try decode(#"{"rateLimitsByLimitId":{"spark":{"primary":{"usedPercent":0,"windowDurationMins":300}}}}"#)
        XCTAssertNil(MenuQuotaSummary(quota: quota).shortTerm)
    }
}
