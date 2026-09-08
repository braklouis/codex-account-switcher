import Foundation

@MainActor public protocol SwitchEnvironment: AnyObject {
    func validate(target: AuthSnapshot) throws
    func readLive() throws -> Data?
    func saveOutgoing(_ auth: Data) throws
    func quit() async throws
    func writeLive(_ auth: Data) throws
    func clearLive() throws
    func launch() async throws
}

public enum SwitchTransaction {
    /// The caller serializes operations. No force quit: a refused exit means no credential write.
    @MainActor public static func run(target: Data, environment: SwitchEnvironment) async throws {
        let selected = try AuthSnapshot(data: target)
        try environment.validate(target: selected)
        // Validate and save before asking the desktop to close.
        if let before = try environment.readLive() {
            _ = try AuthSnapshot(data: before)
            try environment.saveOutgoing(before)
        }
        try await environment.quit()
        let original: Data?
        do {
            original = try environment.readLive()
            if let original {
                _ = try AuthSnapshot(data: original)
                // Pick up tokens refreshed during graceful shutdown.
                try environment.saveOutgoing(original)
            }
        } catch {
            try? await environment.launch()
            throw error
        }
        do {
            try environment.writeLive(target)
            try await environment.launch()
        } catch {
            do {
                // A failed launch can still leave a process alive; stop it before restoring auth.
                try await environment.quit()
                if let original { try environment.writeLive(original) }
                else { try environment.clearLive() }
            } catch {
                throw SwitcherError("切换失败，恢复原登录也失败。原账号仍保存在本工具钥匙串中，请重新选择原账号或登录。")
            }
            do { try await environment.launch() }
            catch { throw SwitcherError("已恢复原登录，但 Codex 无法打开，请手动启动。") }
            throw SwitcherError("切换未完成，已恢复原账号并重新打开 Codex。")
        }
    }
}
