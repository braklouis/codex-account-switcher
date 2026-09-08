import Foundation

public enum RPCContract {
    public static var initializeParams: [String: Any] {
        ["clientInfo": ["name": "codex_accounts", "title": "Codex Accounts", "version": "0.1.1"],
         "capabilities": ["experimentalApi": true]]
    }

    // Classify locally; never show raw server text that may contain credentials or account data.
    public static func errorMessage(_ error: [String: Any]) -> String {
        let message = (error["message"] as? String ?? "").lowercased()
        let code = error["code"] as? Int
        if message.contains("experimentalapi") || code == -32600 || code == -32601 || code == -32602 {
            return "Codex 接口不兼容，请更新账号工具后重试"
        }
        if message.contains("401") || message.contains("unauthorized") || message.contains("token expired") {
            return "登录已过期，请重新登录此账号"
        }
        if message.contains("429") || message.contains("too many requests") {
            return "查询过于频繁，请稍后重试"
        }
        if message.contains("403") || message.contains("forbidden") {
            return "额度查询被服务拒绝，请检查账号权限或网络"
        }
        if message.contains("timeout") || message.contains("connect") || message.contains("network") {
            return "无法连接额度服务，请检查网络后重试"
        }
        return "额度请求失败，请稍后重试（服务错误 \(code ?? -1)）"
    }
}
