import SwiftUI
import SwitcherCore

@MainActor final class AccountStore: ObservableObject, SwitchEnvironment {
    @Published var profiles: [Profile] = []
    @Published var activeIdentity: String?
    @Published var activeEmail: String?
    @Published var busy = false
    @Published var status = "账号保存在这台 Mac 的钥匙串中"
    @Published var error: String?
    @Published var loaded = false
    @Published var quotas: [UUID: QuotaResponse] = [:]
    @Published var quotaDates: [UUID: Date] = [:]
    @Published var quotaErrors: [UUID: String] = [:]
    private let vault = KeychainVault()
    let bridge = CodexBridge()
    let demo: Bool
    private var session: RPCSession?
    private var pollTask: Task<Void, Never>?

    init(demo: Bool = false) {
        self.demo = demo
        if demo { loadDemo() }
        else {
            reload()
            pollTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                while !Task.isCancelled {
                    if let self, !self.busy, self.loaded, !self.profiles.isEmpty { self.refreshQuotas() }
                    try? await Task.sleep(nanoseconds: 300_000_000_000)
                }
            }
        }
    }
    func reload() {
        guard !demo else { return }
        do { profiles = try vault.load(); loaded = true; refreshActive() }
        catch { loaded = false; self.error = error.localizedDescription }
    }
    func refreshActive() {
        guard !demo else { return }
        activeIdentity = nil; activeEmail = nil
        if let data = try? bridge.live(), let auth = try? AuthSnapshot(data: data) {
            activeIdentity = auth.identity; activeEmail = auth.email
        }
    }
    func persist(_ next: [Profile]) throws {
        guard loaded else { throw SwitcherError("请先解锁账号库。") }
        if !demo { try vault.save(next) }
        profiles = next
    }
    @discardableResult func saveAuth(_ data: Data, name: String? = nil) throws -> UUID {
        let auth = try AuthSnapshot(data: data)
        var next = profiles
        let id: UUID
        if let index = next.firstIndex(where: { $0.snapshot?.identity == auth.identity }) {
            next[index].auth = data; id = next[index].id
            if let name, !name.isEmpty { next[index].name = name }
        } else {
            let profile = Profile(name: name?.isEmpty == false ? name! : auth.email, auth: data)
            next.append(profile); id = profile.id
        }
        try persist(next)
        return id
    }
    func importCurrent() {
        perform {
            guard !self.demo else { self.status = "演示模式不会读取真实账号"; return }
            try self.bridge.validate()
            guard let data = try self.bridge.live() else { throw SwitcherError("没有找到当前登录。请点击“登录新账号”。") }
            try self.saveAuth(data)
            self.refreshActive(); self.status = "当前账号已保存"
        }
    }
    func addAccount() {
        perform {
            guard !self.demo else { self.status = "演示模式不会打开真实登录"; return }
            guard let cli = self.bridge.cliURL else { throw SwitcherError("找不到 Codex，请先安装桌面应用。") }
            let rpc = try RPCSession(cli: cli); self.session = rpc
            defer { rpc.stop(); self.session = nil }
            self.status = "请在浏览器中登录要添加的账号"
            try await rpc.start()
            let data = try await rpc.login()
            try self.saveAuth(data)
            self.status = "新账号已保存，可在列表中选择切换"
        }
    }
    func cancelLogin() { session?.stop() }
    func rename(_ profile: Profile, to name: String) {
        guard !busy else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 80 else { return }
        do {
            var next = profiles
            if let index = next.firstIndex(where: { $0.id == profile.id }) { next[index].name = trimmed }
            try persist(next)
        } catch { self.error = error.localizedDescription }
    }
    func remove(_ profile: Profile) {
        guard !busy else { return }
        do {
            try persist(profiles.filter { $0.id != profile.id })
            quotas.removeValue(forKey: profile.id); quotaDates.removeValue(forKey: profile.id)
            quotaErrors.removeValue(forKey: profile.id)
            status = "已移除保存的账号；当前 Codex 登录保持不变"
        } catch { self.error = error.localizedDescription }
    }
    func switchTo(_ profile: Profile) {
        perform {
            if self.demo { self.activeIdentity = profile.snapshot?.identity; self.activeEmail = profile.snapshot?.email; self.status = "演示切换完成"; return }
            self.refreshActive()
            guard profile.snapshot?.identity != self.activeIdentity else { self.status = "这个账号已经是当前账号"; return }
            self.status = "正在保存当前账号并重启 Codex…"
            guard let latest = self.profiles.first(where: { $0.id == profile.id }) else {
                throw SwitcherError("该账号已移除，请重新选择。")
            }
            try await SwitchTransaction.run(target: latest.auth, environment: self)
            self.refreshActive()
            self.status = "已切换登录并重新打开 Codex"
        }
    }
    func refreshQuotas() {
        perform {
            guard !self.demo else { self.status = "演示额度已更新"; return }
            self.refreshActive()
            guard let cli = self.bridge.cliURL else { throw SwitcherError("找不到 Codex。") }
            self.status = "正在读取各账号额度…"
            // Sequential requests avoid refresh bursts and keep each response tied to its profile.
            for profile in self.profiles {
                do {
                    var data = profile.auth
                    if profile.snapshot?.identity == self.activeIdentity, let live = try self.bridge.live() {
                        let liveAuth = try AuthSnapshot(data: live)
                        if liveAuth.identity == profile.snapshot?.identity { data = live; try self.saveAuth(live) }
                    }
                    let auth = try AuthSnapshot(data: data)
                    let rpc = try RPCSession(cli: cli)
                    defer { rpc.stop() }
                    try await rpc.start()
                    let quota = try await rpc.quota(auth: auth)
                    self.quotas[profile.id] = quota; self.quotaDates[profile.id] = Date()
                    self.quotaErrors.removeValue(forKey: profile.id)
                    await AppPreferences.shared.check(profile: profile, quota: quota)
                } catch {
                    self.quotaErrors[profile.id] = (error as? SwitcherError)?.message ?? "额度返回格式无法读取，请更新工具后重试"
                }
            }
            self.status = "额度检查完成"
        }
    }
    private func perform(_ action: @escaping @MainActor () async throws -> Void) {
        guard !busy, loaded else { return }
        busy = true; error = nil
        Task {
            defer { busy = false }
            do { try await action() }
            catch { self.error = (error as? SwitcherError)?.message ?? "操作未完成，请重试。"; status = "操作未完成" }
        }
    }
    func validate(target: AuthSnapshot) throws { try bridge.validate(target: target) }
    func readLive() throws -> Data? { try bridge.live() }
    func saveOutgoing(_ auth: Data) throws { try saveAuth(auth) }
    func quit() async throws { try await bridge.quit() }
    func writeLive(_ auth: Data) throws { try SecureFiles.write(auth, to: bridge.authURL) }
    func clearLive() throws {
        if FileManager.default.fileExists(atPath: bridge.authURL.path) { try FileManager.default.removeItem(at: bridge.authURL) }
    }
    func launch() async throws { try await bridge.launch() }

    private func loadDemo() {
        loaded = true
        for (index, name) in ["主力账号", "备用账号", "研究账号"].enumerated() {
            let claims: [String: Any] = ["sub": "demo-\(index)", "email": "account\(index + 1)@example.com", "https://api.openai.com/auth": ["chatgpt_plan_type": index == 0 ? "pro" : "plus"]]
            let payload = try! JSONSerialization.data(withJSONObject: claims).base64EncodedString()
            let auth: [String: Any] = ["auth_mode": "chatgpt", "tokens": ["account_id": "demo-\(index)", "id_token": "demo.\(payload).demo", "access_token": "demo", "refresh_token": "demo"]]
            let profile = Profile(name: name, auth: try! JSONSerialization.data(withJSONObject: auth))
            profiles.append(profile)
            let quota = "{\"rateLimits\":{\"primary\":{\"usedPercent\":\(index == 0 ? 62 : 12),\"windowDurationMins\":300},\"secondary\":{\"usedPercent\":\(index == 0 ? 79 : 25),\"windowDurationMins\":10080}}}"
            quotas[profile.id] = try! JSONDecoder().decode(QuotaResponse.self, from: Data(quota.utf8))
            quotaDates[profile.id] = Date()
        }
        activeIdentity = profiles[0].snapshot?.identity; activeEmail = profiles[0].snapshot?.email
        status = "演示模式 · 虚构账号，不读取或修改真实登录"
    }
}
