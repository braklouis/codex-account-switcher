import Foundation
import SwiftUI
import Darwin

/// A small, read-only dashboard backed by the installed CodexBar CLI.
/// It deliberately never reads provider credentials or changes the active account.
struct ProviderDashboard: View {
    private static let providers = ["codex", "claude", "cursor", "gemini", "openrouter", "grok", "kimi"]
    @State private var selectedProvider = "codex"
    @State private var rows: [String: ProviderUsage] = [:]
    @State private var loading = false
    @State private var lastRefresh: Date?
    @State private var toolMissing = false
    @State private var costRows: [String: LocalCost] = [:]
    @State private var failedProviders: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            Picker(tr("提供商", "Provider"), selection: $selectedProvider) {
                ForEach(Self.providers, id: \.self) { provider in
                    Text(ProviderUsage.displayName(provider)).tag(provider)
                }
            }
            .pickerStyle(.segmented)
            .disabled(loading)
            .padding(20)
            ScrollView {
                if let row = rows[selectedProvider] {
                    ProviderUsageCard(usage: row)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                } else if loading {
                    HStack { ProgressView(); Text(tr("正在读取额度…", "Loading usage…")).foregroundStyle(.secondary) }
                        .frame(maxWidth: .infinity, alignment: .center).padding(45)
                } else if toolMissing {
                    emptyState("找不到 CodexBar", "Install CodexBar 0.60.2 at /opt/homebrew/bin/codexbar or /usr/local/bin/codexbar.", "terminal")
                } else {
                    emptyState("尚未读取", "Click Refresh to load provider usage.", "chart.bar.xaxis")
                }
                if let cost = costRows[selectedProvider] { LocalCostCard(cost: cost).padding(20) }
                if failedProviders.contains(selectedProvider) {
                    Text(tr("查询未完成，请检查登录状态后重试。", "The query did not complete. Check your login and retry."))
                        .font(.caption).foregroundStyle(.secondary).padding(20)
                }
                Link(tr("配置此平台", "Set up this provider"), destination: URL(string: "https://github.com/steipete/CodexBar/blob/main/docs/\(selectedProvider).md")!)
                    .padding(.bottom, 20)
            }
        }
        .frame(minWidth: 560, minHeight: 420)
        .background(Color(nsColor: .windowBackgroundColor))
        .task { if rows.isEmpty { await refresh() } }
        .onChange(of: selectedProvider) { _, _ in Task { await refresh() } }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("TOKENDECK").font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(2).foregroundStyle(.teal)
                Text(tr("提供商额度", "Provider usage")).font(.system(size: 25, weight: .semibold))
                Text(tr("各平台剩余额度、重置时间与消耗。", "Remaining quota, reset times and consumption across your AI services."))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            Button { Task { await refresh() } } label: {
                Label(tr("刷新", "Refresh"), systemImage: "arrow.clockwise")
            }
            .disabled(loading)
        }.padding(22)
    }

    private func emptyState(_ title: String, _ message: String, _ icon: String) -> some View {
        ContentUnavailableView { Label(tr(title, title == "找不到 CodexBar" ? "CodexBar not found" : "Not loaded"), systemImage: icon) }
            description: { Text(tr(message, message)) }
            .padding(.vertical, 35)
    }

    private func tr(_ chinese: String, _ english: String) -> String { L10n.isEnglish ? english : chinese }

    @MainActor
    private func refresh() async {
        guard !loading else { return }
        loading = true
        defer { loading = false; lastRefresh = Date() }
        let provider = selectedProvider
        let result = await ProviderCLI.fetch(provider: provider)
        if let row = result.row { rows[provider] = row; failedProviders.remove(provider) }
        else { failedProviders.insert(provider) }
        toolMissing = result.toolMissing
        if ["codex", "claude", "cursor"].contains(provider) {
            if let cost = await ProviderCLI.fetchCost(provider: provider) { costRows[provider] = cost }
        }
    }
}

private struct ProviderUsageCard: View {
    let usage: ProviderUsage
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "circle.grid.2x2.fill").foregroundStyle(.teal)
                Text(usage.name).font(.headline)
                Spacer()
                if let account = usage.account, !account.isEmpty { Text(account).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            if let error = usage.errorMessage {
                Label(error, systemImage: "info.circle").font(.system(size: 12)).foregroundStyle(.orange)
            }
            if usage.windows.isEmpty && usage.errorMessage == nil && (usage.details ?? []).isEmpty && usage.credits == nil {
                Text(L10n.isEnglish ? "No usage window was provided by this provider." : "该提供商没有返回可用的额度窗口。").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(usage.windows.enumerated()), id: \.offset) { _, window in UsageWindowView(window: window) }
            if let credits = usage.credits {
                HStack {
                    Label(L10n.isEnglish ? "Credits remaining" : "剩余 Credits", systemImage: "creditcard")
                    Spacer(); Text("\(credits.remaining.formatted(.number.precision(.fractionLength(0...2)))) \(credits.unit)").fontWeight(.semibold)
                }.font(.system(size: 12)).padding(.top, 2)
            }
            ForEach(Array((usage.details ?? []).enumerated()), id: \.offset) { _, section in
                if let title = section.title, let detailRows = section.rows, !detailRows.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        ForEach(Array(detailRows.enumerated()), id: \.offset) { _, row in
                            HStack {
                                Text(row.label ?? "—").foregroundStyle(.secondary)
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(row.value ?? "—").fontWeight(.medium)
                                    if let secondary = row.secondaryValue { Text(secondary).font(.caption2).foregroundStyle(.secondary) }
                                }
                            }.font(.system(size: 11))
                        }
                    }.padding(.top, 2)
                }
            }
            if let cost = usage.cost, cost.todayUSD != nil || cost.last30DaysUSD != nil {
                Text(L10n.isEnglish ? "Local usage estimate · not subscription billing" : "本地使用估算 · 不代表订阅账单")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                HStack {
                    if let today = cost.todayUSD { Text((L10n.isEnglish ? "Today " : "今日 ") + today.formatted(.currency(code: "USD"))) }
                    if let month = cost.last30DaysUSD { Text((L10n.isEnglish ? "30 days " : "近 30 天 ") + month.formatted(.currency(code: "USD"))) }
                }.font(.caption).foregroundStyle(.secondary)
            }
            if let updated = usage.updatedAt { Text(updated, style: .relative).font(.caption2).foregroundStyle(.secondary) }
        }
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.08)))
    }
}

private struct UsageWindowView: View {
    let window: UsageWindow
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack { Text(window.label).font(.system(size: 12, weight: .medium)); Spacer(); Text("\(Int(window.remaining.rounded()))%").font(.system(size: 20, weight: .semibold, design: .rounded)).monospacedDigit() }
            ProgressView(value: max(0, min(100, window.remaining)), total: 100).tint(window.remaining <= 10 ? .red : window.remaining <= 25 ? .orange : .teal)
            if let reset = window.resetAt {
                HStack { Image(systemName: "clock"); Text(reset, style: .relative); Spacer(); Text(reset, style: .date) }
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

private struct ProviderUsage: Decodable {
    let id: String
    let name: String
    let identity: Identity?
    let windows: [UsageWindow]
    let credits: Credits?
    let cost: UsageCost?
    let providerError: ProviderError?
    let details: [UsageDetailSection]?
    let updatedAt: Date?
    var account: String? { identity?.accountEmail ?? identity?.plan }
    var errorMessage: String? {
        guard providerError != nil else { return nil }
        return L10n.isEnglish ? "Unavailable or account setup is required. Sign in with the provider and refresh." : "暂不可用或需要先完成账号设置。请登录该提供商后刷新。"
    }
    static func displayName(_ id: String) -> String { ["claude":"Claude", "cursor":"Cursor", "gemini":"Gemini", "openrouter":"OpenRouter", "grok":"Grok", "kimi":"Kimi Code"][id] ?? id.capitalized }
    struct Identity: Decodable { let accountEmail: String?; let plan: String? }
    struct Credits: Decodable { let remaining: Double; let unit: String }
    struct UsageCost: Decodable { let todayUSD: Double?; let last30DaysUSD: Double? }
    struct ProviderError: Decodable { let message: String?; let code: Int?; let kind: String? }
    struct UsageDetailSection: Decodable { let title: String?; let rows: [UsageDetailRow]? }
    struct UsageDetailRow: Decodable { let label: String?; let value: String?; let secondaryValue: String? }
    private enum CodingKeys: String, CodingKey {
        case id, name, identity, windows, credits, cost, updatedAt, details
        case providerError = "error"
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? Self.displayName(id)
        identity = try c.decodeIfPresent(Identity.self, forKey: .identity)
        windows = try c.decodeIfPresent([UsageWindow].self, forKey: .windows) ?? []
        credits = try c.decodeIfPresent(Credits.self, forKey: .credits)
        cost = try c.decodeIfPresent(UsageCost.self, forKey: .cost)
        providerError = try c.decodeIfPresent(ProviderError.self, forKey: .providerError)
        details = try c.decodeIfPresent([UsageDetailSection].self, forKey: .details)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }
}

private struct UsageWindow: Decodable {
    let label: String
    let remainingPercent: Double
    let resetAt: Date?
    var remaining: Double { remainingPercent }
    private enum CodingKeys: String, CodingKey { case label, remainingPercent, resetAt }
}

private struct ProviderCLI {
    struct Result { var row: ProviderUsage?; var toolMissing = false }
    static func fetch(provider: String) async -> Result {
        await Task.detached(priority: .utility) {
            let value = run(provider: provider)
            return Result(row: value.0, toolMissing: value.1)
        }.value
    }

    static func fetchCost(provider: String) async -> LocalCost? {
        await Task.detached(priority: .utility) {
            guard let payload = execute(arguments: ["cost", "--provider", provider, "--format", "json", "--days", "30"]) else { return nil }
            return (try? JSONDecoder().decode([LocalCost].self, from: payload))?.first
        }.value
    }

    static func decodeUsage(_ payload: Data, provider: String) -> ProviderUsage? {
        guard let json = try? JSONSerialization.jsonObject(with: payload),
              let source = (json as? [[String: Any]])?.first ?? json as? [String: Any],
              source["provider"] as? String == provider else { return nil }
        let usage = source["usage"] as? [String: Any] ?? [:]
        var normalized: [String: Any] = ["id": provider, "windows": []]
        for key in ["identity", "details", "updatedAt"] {
            if let value = usage[key], !(value is NSNull) { normalized[key] = value }
        }
        if source["error"] != nil { normalized["error"] = ["code": 1] }
        let names = L10n.isEnglish ? ["Primary quota", "Weekly / secondary", "Additional quota"] : ["主要额度", "每周 / 次要额度", "其他额度"]
        var windows: [[String: Any]] = []
        for (index, key) in ["primary", "secondary", "tertiary"].enumerated() {
            guard let window = usage[key] as? [String: Any], window["isSyntheticPlaceholder"] as? Bool != true, let used = window["usedPercent"] as? Double, used.isFinite else { continue }
            let minutes = window["windowMinutes"] as? Double
            var label = names[index]
            if let minutes, minutes > 0 {
                label = minutes >= 1440 ? String(format: L10n.isEnglish ? "%.0f days" : "%.0f 天", minutes / 1440) : String(format: L10n.isEnglish ? "%.1f hours" : "%.1f 小时", minutes / 60)
            }
            var mapped: [String: Any] = ["label": label, "remainingPercent": max(0, min(100, 100 - used))]
            if let reset = window["resetsAt"] as? String { mapped["resetAt"] = reset }
            windows.append(mapped)
        }
        normalized["windows"] = windows
        if let credits = source["credits"] as? [String: Any], let remaining = credits["remaining"] as? Double {
            normalized["credits"] = ["remaining": remaining, "unit": "credits"]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: normalized) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions.insert(.withFractionalSeconds)
            if let date = formatter.date(from: text) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid date"))
        }
        return try? decoder.decode(ProviderUsage.self, from: data)
    }

    private static func run(provider: String) -> (ProviderUsage?, Bool) {
        guard executable != nil else { return (nil, true) }
        guard let payload = execute(arguments: ["usage", "--provider", provider, "--format", "json", "--web-timeout", "12"]) else { return (nil, false) }
        return (decodeUsage(payload, provider: provider), false)
    }
    private static var executable: String? {
        ["/opt/homebrew/bin/codexbar", "/usr/local/bin/codexbar"].first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    }
    private static func execute(arguments: [String]) -> Data? {
        guard let path = executable else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let buffer = OutputBuffer()
        let reader = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            while true {
                let chunk = output.fileHandleForReading.availableData
                if chunk.isEmpty { break }
                buffer.append(chunk)
            }
            reader.signal()
        }
        let deadline = Date().addingTimeInterval(45)
        while process.isRunning && Date() < deadline { usleep(50_000) }
        let timedOut = process.isRunning
        if timedOut {
            process.terminate()
            let grace = Date().addingTimeInterval(1)
            while process.isRunning && Date() < grace { usleep(20_000) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        let completed = reader.wait(timeout: .now() + 2) == .success
        guard !timedOut, completed else { return nil }
        return buffer.snapshot()
    }
}

private final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private var overflow = false
    func append(_ chunk: Data) {
        lock.lock(); defer { lock.unlock() }
        let limit = 4_000_000
        if data.count + chunk.count > limit { overflow = true }
        data.append(chunk.prefix(max(0, limit - data.count)))
    }
    func snapshot() -> Data? {
        lock.lock(); defer { lock.unlock() }
        return overflow || data.isEmpty ? nil : data
    }
}

private struct LocalCost: Decodable {
    let provider: String
    let last30DaysTokens: Int64?
    let last30DaysCostUSD: Double?
    let provenance: String?
    let totals: Totals?
    struct Totals: Decodable {
        let inputTokens: Int64?
        let outputTokens: Int64?
        let cacheReadTokens: Int64?
    }
}

private struct LocalCostCard: View {
    let cost: LocalCost
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.isEnglish ? "Last 30 days · local usage" : "近 30 天 · 本地消耗").font(.headline)
            if let tokens = cost.last30DaysTokens { LabeledContent("Tokens", value: tokens.formatted()) }
            if let input = cost.totals?.inputTokens { LabeledContent(L10n.isEnglish ? "Input (includes cached reads)" : "输入（含缓存读取）", value: input.formatted()) }
            if let cached = cost.totals?.cacheReadTokens { LabeledContent(L10n.isEnglish ? "Cached reads" : "缓存读取", value: cached.formatted()) }
            if let output = cost.totals?.outputTokens { LabeledContent(L10n.isEnglish ? "Output" : "输出", value: output.formatted()) }
            if let dollars = cost.last30DaysCostUSD {
                LabeledContent(L10n.isEnglish ? "Estimated cost" : "估算成本", value: dollars.formatted(.currency(code: "USD")))
            }
            Text(L10n.isEnglish ? "Local records may be incomplete. Cost is an estimate, not your subscription bill. Shared local history is not limited to the active account." : "本地记录可能不完整。费用为估算，不是会员实际账单；共享历史也不限于当前账号。")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(20).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
    }
}
