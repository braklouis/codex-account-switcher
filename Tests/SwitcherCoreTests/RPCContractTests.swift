import XCTest
@testable import SwitcherCore

final class RPCContractTests: XCTestCase {
    func testExternalTokenLoginCapabilityEnabled() {
        let capabilities = RPCContract.initializeParams["capabilities"] as? [String: Bool]
        XCTAssertEqual(capabilities?["experimentalApi"], true)
    }
    func testProtocolFailureDoesNotSuggestLogin() {
        let text = RPCContract.errorMessage(["code": -32600, "message": "account/login/start.chatgptAuthTokens requires experimentalApi capability"])
        XCTAssertTrue(text.contains("接口不兼容"))
        XCTAssertFalse(text.contains("重新登录"))
    }
    func testErrorsDoNotExposeServerText() {
        let text = RPCContract.errorMessage(["code": -32000, "message": "secret-token-value"])
        XCTAssertFalse(text.contains("secret-token-value"))
        XCTAssertTrue(RPCContract.errorMessage(["message": "HTTP 401 Unauthorized"]).contains("登录已过期"))
        XCTAssertTrue(RPCContract.errorMessage(["message": "connection timeout"]).contains("网络"))
    }
}
