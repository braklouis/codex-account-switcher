import Foundation

public struct SwitcherError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// Claims are display hints, never proof of identity or authorization.
public struct AuthSnapshot {
    public let data: Data
    public let accountID: String
    public let subject: String
    public let email: String
    public let plan: String
    public let accessToken: String
    public var identity: String { subject + "|" + accountID }

    public init(data: Data) throws {
        guard data.count < 1_000_000,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["OPENAI_API_KEY"] == nil || root["OPENAI_API_KEY"] is NSNull,
              root["auth_mode"] == nil || root["auth_mode"] as? String == "chatgpt",
              let tokens = root["tokens"] as? [String: Any],
              let account = tokens["account_id"] as? String, !account.isEmpty,
              let access = tokens["access_token"] as? String, !access.isEmpty,
              let refresh = tokens["refresh_token"] as? String, !refresh.isEmpty,
              let idToken = tokens["id_token"] as? String,
              let claims = Self.claims(idToken),
              let subject = claims["sub"] as? String, !subject.isEmpty else {
            throw SwitcherError("无法读取 ChatGPT 会员登录。请通过官方浏览器登录后重试。")
        }
        let info = claims["https://api.openai.com/auth"] as? [String: Any] ?? [:]
        self.data = data; accountID = account; self.subject = subject; accessToken = access
        email = claims["email"] as? String ?? "未提供邮箱"
        plan = info["chatgpt_plan_type"] as? String ?? "unknown"
    }

    public static func claims(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var base = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base += String(repeating: "=", count: (4 - base.count % 4) % 4)
        guard let data = Data(base64Encoded: base) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

public struct Profile: Codable, Identifiable {
    public var id: UUID
    public var name: String
    public var auth: Data
    public var addedAt: Date
    public init(name: String, auth: Data) {
        id = UUID(); self.name = name; self.auth = auth; addedAt = Date()
    }
    public var snapshot: AuthSnapshot? { try? AuthSnapshot(data: auth) }
}

public struct QuotaWindow: Codable, Identifiable {
    public var usedPercent: Double
    public var windowDurationMins: Int?
    public var resetsAt: Double?
    public var id: String { "\(windowDurationMins ?? -1)-\(resetsAt ?? -1)" }
    public var remaining: Double { max(0, min(100, 100 - usedPercent)) }
    public var title: String {
        guard let minutes = windowDurationMins else { return "额度窗口" }
        if minutes == 10080 { return "每周" }
        if minutes % 60 == 0 { return "\(minutes / 60) 小时" }
        return "\(minutes) 分钟"
    }
}

public struct QuotaBucket: Codable {
    public var limitName: String?
    public var primary: QuotaWindow?
    public var secondary: QuotaWindow?
    public var planType: String?
}

public struct QuotaResponse: Decodable {
    public var rateLimits: QuotaBucket?
    public var rateLimitsByLimitId: [String: QuotaBucket]?
    public var accountId: String?
    public var buckets: [(String, QuotaBucket)] {
        if let all = rateLimitsByLimitId, !all.isEmpty { return all.sorted { $0.key < $1.key } }
        return rateLimits.map { [("codex", $0)] } ?? []
    }
}
