import Foundation
import Darwin

public enum SecureFiles {
    public static func ensureDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        guard values.isSymbolicLink != true, values.isDirectory == true else {
            throw SwitcherError("目录不是普通本地目录，已停止操作。")
        }
    }

    public static func read(_ url: URL) throws -> Data {
        let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw SwitcherError("无法读取登录文件。请确认 Codex 已登录且使用文件存储。") }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var statbuf = stat()
        guard fstat(fd, &statbuf) == 0, statbuf.st_mode & S_IFMT == S_IFREG,
              statbuf.st_size < 1_000_000 else { throw SwitcherError("登录文件类型或大小不正确。") }
        return try handle.readToEnd() ?? Data()
    }

    /// Temp file is private from creation; rename commits in the same directory atomically.
    public static func write(_ data: Data, to url: URL) throws {
        try ensureDirectory(url.deletingLastPathComponent())
        if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            throw SwitcherError("登录文件是符号链接，已停止操作。")
        }
        let temp = url.deletingLastPathComponent().appendingPathComponent(".switch-" + UUID().uuidString)
        let fd = Darwin.open(temp.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw SwitcherError("无法创建安全的临时文件。") }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
        defer { try? handle.close(); try? FileManager.default.removeItem(at: temp) }
        try handle.write(contentsOf: data)
        guard fsync(fd) == 0, Darwin.rename(temp.path, url.path) == 0 else {
            throw SwitcherError("保存失败，原登录文件未被替换。")
        }
    }
}

public enum StoragePolicy {
    /// Conservative on explicit overrides; the app never rewrites the user's config.
    public static func validate(config: String, targetAccountID: String? = nil) throws {
        for raw in config.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") { continue }
            if line.range(of: #"^["']?cli_auth_credentials_store["']?\s*="#, options: .regularExpression) != nil,
               line.range(of: #"=\s*["']file["']\s*(#.*)?$"#, options: .regularExpression) == nil {
                throw SwitcherError("当前 Codex 配置使用钥匙串或自动存储。本版本仅切换文件存储，不会修改你的配置。")
            }
            if line.hasPrefix("forced_login_method"), line.contains("api") {
                throw SwitcherError("当前配置限定 API 登录，不能切换会员账号。")
            }
            if line.hasPrefix("forced_chatgpt_workspace_id"), let targetAccountID,
               !line.contains("\"\(targetAccountID)\"") && !line.contains("'\(targetAccountID)'") {
                throw SwitcherError("目标账号不符合当前工作区限制。")
            }
        }
    }
}
