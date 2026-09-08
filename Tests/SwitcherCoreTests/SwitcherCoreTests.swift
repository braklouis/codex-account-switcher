import XCTest
@testable import SwitcherCore

func fixture(_ subject: String = "user-a", workspace: String = "workspace-a", refresh: String = "refresh-a") -> Data {
    let claims: [String: Any] = ["sub": subject, "email": "test@example.com", "https://api.openai.com/auth": ["chatgpt_plan_type": "plus"]]
    let payload = try! JSONSerialization.data(withJSONObject: claims, options: .sortedKeys).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    return try! JSONSerialization.data(withJSONObject: ["auth_mode": "chatgpt", "tokens": ["account_id": workspace, "id_token": "x.\(payload).x", "access_token": "test-access", "refresh_token": refresh]], options: .sortedKeys)
}

final class ModelsTests: XCTestCase {
    func testIdentitySeparatesUsersInSameWorkspace() throws {
        let a = try AuthSnapshot(data: fixture())
        let b = try AuthSnapshot(data: fixture("user-b"))
        XCTAssertNotEqual(a.identity, b.identity)
        XCTAssertEqual(a.email, "test@example.com")
        XCTAssertEqual(a.plan, "plus")
    }
    func testInvalidAuthRejectedWithoutEchoingSecrets() {
        for data in [Data("secret-invalid".utf8), Data("{}".utf8), fixture(refresh: "")] {
            XCTAssertThrowsError(try AuthSnapshot(data: data)) { error in
                XCTAssertFalse(error.localizedDescription.contains("secret-invalid"))
            }
        }
    }
    func testAPIKeysAreNotImported() throws {
        var object = try JSONSerialization.jsonObject(with: fixture()) as! [String: Any]
        object["OPENAI_API_KEY"] = "test-api-key"
        XCTAssertThrowsError(try AuthSnapshot(data: JSONSerialization.data(withJSONObject: object)))
    }
    func testQuotaUsesAllBucketsAndClampsRemaining() throws {
        let json = """
        {"rateLimits":{"primary":{"usedPercent":1}},"rateLimitsByLimitId":{
        "codex":{"primary":{"usedPercent":110,"windowDurationMins":300}},
        "spark":{"secondary":{"usedPercent":-2,"windowDurationMins":10080}}}}
        """
        let response = try JSONDecoder().decode(QuotaResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.buckets.count, 2)
        XCTAssertEqual(response.buckets[0].1.primary?.remaining, 0)
        XCTAssertEqual(response.buckets[1].1.secondary?.remaining, 100)
        XCTAssertEqual(response.buckets[1].1.secondary?.title, "每周")
    }
    func testMissingQuotaIsNotZero() throws {
        let result = try JSONDecoder().decode(QuotaResponse.self, from: Data("{}".utf8))
        XCTAssertTrue(result.buckets.isEmpty)
    }
    func testStoragePolicy() throws {
        for text in ["cli_auth_credentials_store = \"keyring\"", "cli_auth_credentials_store='auto'", "\"cli_auth_credentials_store\" = 'keyring'"] {
            XCTAssertThrowsError(try StoragePolicy.validate(config: text))
        }
        try StoragePolicy.validate(config: "# cli_auth_credentials_store = 'keyring'\ncli_auth_credentials_store = 'file' # okay")
        XCTAssertThrowsError(try StoragePolicy.validate(config: "forced_chatgpt_workspace_id = 'other'", targetAccountID: "mine"))
    }
}

final class SecureFilesTests: XCTestCase {
    func testAtomicWritePermissionsAndSymlinkRejection() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("auth.json")
        try SecureFiles.write(fixture(), to: file)
        let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o600)
        XCTAssertEqual(try SecureFiles.read(file), fixture())
        let link = directory.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        XCTAssertThrowsError(try SecureFiles.read(link))
        XCTAssertThrowsError(try SecureFiles.write(Data(), to: link))
        XCTAssertEqual(try SecureFiles.read(file), fixture())
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 2)
    }
}

@MainActor final class FakeEnvironment: SwitchEnvironment {
    var live: Data? = fixture()
    var events: [String] = []
    var saved: [Data] = []
    var refuseQuit = false
    var failSave = false
    var failWrites = 0
    var failLaunches = 0
    var afterQuit: Data?
    func validate(target: AuthSnapshot) throws { events.append("validate") }
    func readLive() throws -> Data? { events.append("read"); return live }
    func saveOutgoing(_ auth: Data) throws {
        events.append("save")
        if failSave { throw SwitcherError("save failure") }
        saved.append(auth)
    }
    func quit() async throws {
        events.append("quit")
        if refuseQuit { throw SwitcherError("quit refused") }
        if let afterQuit { live = afterQuit }
    }
    func writeLive(_ auth: Data) throws {
        events.append("write")
        if failWrites > 0 { failWrites -= 1; throw SwitcherError("write failure") }
        live = auth
    }
    func clearLive() throws { events.append("clear"); live = nil }
    func launch() async throws {
        events.append("launch")
        if failLaunches > 0 { failLaunches -= 1; throw SwitcherError("launch failure") }
    }
}

final class TransactionTests: XCTestCase {
    @MainActor func testSuccessSavesFreshShutdownTokens() async throws {
        let env = FakeEnvironment(); env.afterQuit = fixture(refresh: "new-refresh")
        let target = fixture("user-b")
        try await SwitchTransaction.run(target: target, environment: env)
        XCTAssertEqual(env.live, target)
        XCTAssertEqual(env.saved.last, env.afterQuit)
        XCTAssertEqual(env.events, ["validate", "read", "save", "quit", "read", "save", "write", "launch"])
    }
    @MainActor func testRefusedQuitDoesNotWrite() async {
        let env = FakeEnvironment(); env.refuseQuit = true
        do { try await SwitchTransaction.run(target: fixture("b"), environment: env); XCTFail() } catch {}
        XCTAssertFalse(env.events.contains("write"))
        XCTAssertEqual(env.live, fixture())
    }
    @MainActor func testKeychainFailureStopsBeforeQuit() async {
        let env = FakeEnvironment(); env.failSave = true
        do { try await SwitchTransaction.run(target: fixture("b"), environment: env); XCTFail() } catch {}
        XCTAssertFalse(env.events.contains("quit"))
    }
    @MainActor func testLaunchFailureRollsBack() async {
        let env = FakeEnvironment(); env.failLaunches = 1
        do { try await SwitchTransaction.run(target: fixture("b"), environment: env); XCTFail() } catch {}
        XCTAssertEqual(env.live, fixture())
        XCTAssertEqual(env.events.suffix(5), ["write", "launch", "quit", "write", "launch"])
    }
    @MainActor func testWriteFailureRollsBack() async {
        let env = FakeEnvironment(); env.failWrites = 1
        do { try await SwitchTransaction.run(target: fixture("b"), environment: env); XCTFail() } catch {}
        XCTAssertEqual(env.live, fixture())
    }
    @MainActor func testNoOriginalAuthRollbackRemovesTarget() async {
        let env = FakeEnvironment(); env.live = nil; env.failLaunches = 1
        do { try await SwitchTransaction.run(target: fixture("b"), environment: env); XCTFail() } catch {}
        XCTAssertNil(env.live)
        XCTAssertTrue(env.events.contains("clear"))
    }
    @MainActor func testRollbackFailureIsExplicit() async {
        let env = FakeEnvironment(); env.failWrites = 2
        do { try await SwitchTransaction.run(target: fixture("b"), environment: env); XCTFail() }
        catch { XCTAssertTrue(error.localizedDescription.contains("恢复原登录也失败")) }
    }
    @MainActor func testInvalidTargetDoesNotQuit() async {
        let env = FakeEnvironment()
        do { try await SwitchTransaction.run(target: Data(), environment: env); XCTFail() } catch {}
        XCTAssertTrue(env.events.isEmpty)
    }
}
