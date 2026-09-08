import Foundation

public struct MenuQuotaSummary {
    public let shortTerm: QuotaWindow?
    public let weekly: QuotaWindow?
    public init(quota: QuotaResponse?, unavailable: Bool = false) {
        guard !unavailable, let quota else { shortTerm = nil; weekly = nil; return }
        let bucket: QuotaBucket?
        if let all = quota.rateLimitsByLimitId, !all.isEmpty { bucket = all["codex"] }
        else { bucket = quota.rateLimits }
        let windows = [bucket?.primary, bucket?.secondary].compactMap { $0 }
        weekly = windows.first { $0.windowDurationMins == 10080 }
        shortTerm = windows.first { ($0.windowDurationMins ?? 0) > 0 && ($0.windowDurationMins ?? 10080) < 10080 }
    }
}
