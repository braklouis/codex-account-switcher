import AppKit
import Foundation
import SwitcherCore

@MainActor final class CodexBridge {
    let bundleID = "com.openai.codex"
    var appURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) }
    var cliURL: URL? { appURL?.appendingPathComponent("Contents/Resources/codex") }
    var home: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex") }
    var authURL: URL { home.appendingPathComponent("auth.json") }
    var running: [NSRunningApplication] { NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) }

    func validate(target: AuthSnapshot? = nil) throws {
        guard let appURL, let cliURL, FileManager.default.isExecutableFile(atPath: cliURL.path),
              Bundle(url: appURL)?.bundleIdentifier == bundleID else {
            throw SwitcherError("找不到 Codex 桌面应用。请先安装并启动一次。")
        }
        if let override = ProcessInfo.processInfo.environment["CODEX_HOME"],
           URL(fileURLWithPath: override).standardizedFileURL != home.standardizedFileURL {
            throw SwitcherError("检测到自定义 CODEX_HOME。本版本仅支持默认目录。")
        }
        let configURL = home.appendingPathComponent("config.toml")
        let config = FileManager.default.fileExists(atPath: configURL.path)
            ? try String(contentsOf: configURL, encoding: .utf8) : ""
        try StoragePolicy.validate(config: config, targetAccountID: target?.accountID)
        if (try? home.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            throw SwitcherError("Codex 目录是符号链接，本版本不修改此目录。")
        }
    }
    func live() throws -> Data? {
        guard FileManager.default.fileExists(atPath: authURL.path) else { return nil }
        return try SecureFiles.read(authURL)
    }
    func quit() async throws {
        let apps = running
        for app in apps where !app.terminate() {
            throw SwitcherError("Codex 没有同意退出。请先完成任务并手动退出，再试一次。")
        }
        for _ in 0..<100 {
            if running.isEmpty { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw SwitcherError("Codex 尚未退出，未替换登录。请完成任务后重试。")
    }
    func launch() async throws {
        guard let appURL else { throw SwitcherError("找不到 Codex。") }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let app = try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
        try await Task.sleep(nanoseconds: 800_000_000)
        guard !app.isTerminated else { throw SwitcherError("Codex 启动后退出。") }
    }
}

/// A short-lived stdio server in an isolated home. Never runs a model task.
@MainActor final class RPCSession {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private var buffer = Data()
    private var nextID = 0
    private var pending: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    private var notifications: [[String: Any]] = []
    private(set) var directory: URL
    private var stopped = false

    init(cli: URL) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("codex-accounts-" + UUID().uuidString)
        try SecureFiles.ensureDirectory(directory)
        // Private home also prevents logs, sessions or plugins being written to the live Codex home.
        try SecureFiles.write(Data("cli_auth_credentials_store = \"file\"\n[analytics]\nenabled = false\n".utf8),
                              to: directory.appendingPathComponent("config.toml"))
        process.executableURL = cli
        process.arguments = ["app-server", "--stdio"]
        process.currentDirectoryURL = directory
        var env = ProcessInfo.processInfo.environment
        env["CODEX_HOME"] = directory.path
        for key in ["OPENAI_API_KEY", "OPENAI_BASE_URL", "CODEX_ACCESS_TOKEN"] { env.removeValue(forKey: key) }
        process.environment = env
        process.standardInput = input; process.standardOutput = output
        process.standardError = FileHandle.nullDevice // Never persist raw auth diagnostics.
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { @MainActor in self?.receive(data) }
        }
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in self?.failAll(SwitcherError("Codex 服务已退出，请重试。")) }
        }
        do { try process.run() }
        catch { try? FileManager.default.removeItem(at: directory); throw SwitcherError("无法启动本机 Codex 服务。") }
    }
    func start() async throws {
        _ = try await request("initialize", ["clientInfo": ["name": "codex_accounts", "title": "Codex Accounts", "version": "0.1.0"], "capabilities": NSNull()])
        try send(["method": "initialized"])
    }
    private func send(_ object: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(10)
        try input.fileHandleForWriting.write(contentsOf: data)
    }
    func request(_ method: String, _ params: [String: Any]? = nil) async throws -> [String: Any] {
        guard !stopped, process.isRunning else { throw SwitcherError("Codex 服务没有运行。") }
        nextID += 1
        let id = nextID
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            do {
                var message: [String: Any] = ["id": id, "method": method]
                if let params { message["params"] = params }
                try send(message)
            } catch { pending.removeValue(forKey: id)?.resume(throwing: SwitcherError("无法连接 Codex 服务。")) }
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                self?.pending.removeValue(forKey: id)?.resume(throwing: SwitcherError("请求超时，请重试。"))
            }
        }
    }
    private func receive(_ data: Data) {
        if data.isEmpty { failAll(SwitcherError("Codex 服务连接结束。")); return }
        buffer.append(data)
        guard buffer.count < 4_000_000 else { stop(); return }
        while let index = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<index]); buffer.removeSubrange(...index)
            guard let message = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { continue }
            // External-token auth may ask for renewal. Never rotate saved refresh tokens during quota reads.
            if message["method"] != nil, let id = message["id"] {
                try? send(["id": id, "error": ["code": -32000, "message": "Please sign in again in Codex Accounts."]])
            } else if let id = message["id"] as? Int, let waiting = pending.removeValue(forKey: id) {
                if message["error"] != nil { waiting.resume(throwing: SwitcherError("请求未成功。登录可能已过期，请重新登录，或稍后重试。")) }
                else { waiting.resume(returning: message["result"] as? [String: Any] ?? [:]) }
            } else if message["method"] as? String == "account/login/completed" {
                notifications.append(message["params"] as? [String: Any] ?? [:])
            }
        }
    }
    func login() async throws -> Data {
        let result = try await request("account/login/start", ["type": "chatgpt"])
        guard let loginID = result["loginId"] as? String,
              let text = result["authUrl"] as? String, let url = URL(string: text),
              url.scheme == "https", let host = url.host,
              host == "auth.openai.com" || host == "auth0.openai.com" else {
            throw SwitcherError("Codex 没有返回有效的官方登录地址。")
        }
        guard NSWorkspace.shared.open(url) else { throw SwitcherError("无法打开浏览器。请检查默认浏览器设置。") }
        for _ in 0..<1800 {
            try Task.checkCancellation()
            guard !stopped, process.isRunning else { throw SwitcherError("登录已取消。") }
            if let completion = notifications.first(where: { $0["loginId"] as? String == loginID }) {
                guard completion["success"] as? Bool == true else { throw SwitcherError("登录未完成，请重试。") }
                return try SecureFiles.read(directory.appendingPathComponent("auth.json"))
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        _ = try? await request("account/login/cancel", ["loginId": loginID])
        throw SwitcherError("登录已超时，请重新开始。")
    }
    func quota(auth: AuthSnapshot) async throws -> QuotaResponse {
        _ = try await request("account/login/start", ["type": "chatgptAuthTokens", "accessToken": auth.accessToken, "chatgptAccountId": auth.accountID])
        let result = try await request("account/rateLimits/read")
        let quota = try JSONDecoder().decode(QuotaResponse.self, from: JSONSerialization.data(withJSONObject: result))
        if let account = quota.accountId, account != auth.accountID { throw SwitcherError("额度返回的账号不匹配，已丢弃结果。") }
        return quota
    }
    private func failAll(_ error: Error) {
        let all = pending; pending.removeAll()
        for continuation in all.values { continuation.resume(throwing: error) }
    }
    func stop() {
        guard !stopped else { return }
        stopped = true
        output.fileHandleForReading.readabilityHandler = nil
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
        failAll(SwitcherError("操作已取消。"))
        let process = process; let directory = directory
        Task {
            for _ in 0..<30 where process.isRunning { try? await Task.sleep(nanoseconds: 100_000_000) }
            if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
            // Only our isolated helper is terminated; never the desktop application.
            for _ in 0..<20 where process.isRunning { try? await Task.sleep(nanoseconds: 50_000_000) }
            if !process.isRunning { try? FileManager.default.removeItem(at: directory) }
        }
    }
}
