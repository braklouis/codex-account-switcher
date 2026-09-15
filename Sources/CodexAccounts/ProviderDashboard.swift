import Foundation
import SwiftUI
import Darwin

/// A small, read-only dashboard backed by the installed CodexBar CLI.
/// It deliberately never reads provider credentials or changes the active account.
@MainActor final class ProviderUsageStore: ObservableObject {
    static let shared = ProviderUsageStore()
    @Published private(set) var rows: [String: [ProviderUsage]] = [:]
    @Published private(set) var selectedAccounts: [String: Int] = [:]
    @Published private(set) var loadingProviders: Set<String> = []
    var loading: Bool { !loadingProviders.isEmpty }
    func isLoading(_ provider: String) -> Bool { loadingProviders.contains(provider) }
    @Published private(set) var errors: [String: String] = [:]
    private var refreshedAt: [String: Date] = [:]
    private var selectionKeys: [String: String] = UserDefaults.standard.dictionary(forKey: "providerAccountSelections") as? [String: String] ?? [:]
    private var activeTasks: [String: Task<ProviderCLI.Result, Never>] = [:]

    private let fetch: (String) async -> ProviderCLI.Result
    init(fetch: @escaping (String) async -> ProviderCLI.Result = { await ProviderCLI.fetch(provider: $0) }) {
        self.fetch = fetch
    }

    func selectedUsage(provider: String) -> ProviderUsage? {
        guard let values = rows[provider], !values.isEmpty else { return nil }
        return values[min(max(0, selectedAccounts[provider] ?? 0), values.count - 1)]
    }
    func selectAccount(provider: String, index: Int) {
        guard let values = rows[provider], values.indices.contains(index) else { return }
        selectedAccounts[provider] = index
        // Unlabelled rows cannot be identified reliably after a provider reorders its response.
        if let key = values[index].account { selectionKeys[provider] = key }
        else { selectionKeys.removeValue(forKey: provider) }
        UserDefaults.standard.set(selectionKeys, forKey: "providerAccountSelections")
    }
    func refresh(provider: String, force: Bool = false) async {
        // Coalesce duplicate requests without blocking unrelated products.
        if let task = activeTasks[provider] {
            _ = await task.value
            return
        }
        guard !Task.isCancelled else { return }
        guard force || Date().timeIntervalSince(refreshedAt[provider] ?? .distantPast) >= 60 else { return }
        loadingProviders.insert(provider)
        let task = Task { await fetch(provider) }
        activeTasks[provider] = task
        let result = await task.value
        defer { activeTasks.removeValue(forKey: provider); loadingProviders.remove(provider) }
        refreshedAt[provider] = Date()
        if result.rows.isEmpty {
            errors[provider] = result.toolMissing
                ? (L10n.isEnglish ? "CodexBar is not installed." : "未找到 CodexBar。")
                : (L10n.isEnglish ? "Could not refresh. Try again or check login settings." : "刷新失败，请重试或检查登录配置。")
            return
        }
        errors.removeValue(forKey: provider)
        rows[provider] = result.rows
        if let key = selectionKeys[provider], let index = result.rows.firstIndex(where: { $0.account == key }) {
            selectedAccounts[provider] = index
        } else { selectedAccounts[provider] = 0 }
    }
}

struct ProviderDashboard: View {
    @ObservedObject private var products = ProductPreferences.shared
    @ObservedObject private var usage = ProviderUsageStore.shared
    var showProducts: () -> Void = {}
    var codexAccounts: AnyView?
    @State private var showsCost = false
    @State private var costs: [String: LocalCost] = [:]
    @State private var costLoading = false
    @State private var costError: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker(L10n.isEnglish ? "Product" : "产品", selection: $products.selected) {
                    ForEach(products.enabled, id: \.self) { id in
                        Text(ProductPreferences.catalog.first { $0.id == id }?.name ?? id)
                            .tag(id)
                    }
                }.labelsHidden().fixedSize()
                Spacer()
                if products.selected != "codex" || codexAccounts == nil {
                Button { Task { await usage.refresh(provider: products.selected, force: true) } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help(L10n.isEnglish ? "Refresh usage" : "刷新额度")
                .disabled(usage.isLoading(products.selected))
                }
            }.padding(16)
            Divider()
            VStack(spacing: 0) {
                if products.selected == "codex", let codexAccounts {
                    codexAccounts
                } else {
                ScrollView {
                    VStack(spacing: 16) {
                        if let rows = usage.rows[products.selected], rows.count > 1 {
                            Picker(L10n.isEnglish ? "Viewing account" : "查看账号", selection: Binding(
                                get: { usage.selectedAccounts[products.selected] ?? 0 },
                                set: { usage.selectAccount(provider: products.selected, index: $0) })) {
                                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in Text(row.account ?? "Account \(index + 1)").tag(index) }
                            }
                        }
                        if let row = usage.selectedUsage(provider: products.selected) { ProviderUsageCard(usage: row) }
                        else if usage.isLoading(products.selected) { ProgressView().padding(40) }
                        else { ContentUnavailableView(L10n.isEnglish ? "Connect your account" : "连接你的账号", systemImage: "person.crop.circle.badge.plus") }
                        if let error = usage.errors[products.selected] { Text(error).font(.caption).foregroundStyle(.orange) }
                        Button(L10n.isEnglish ? "Login & product settings" : "登录与产品设置") { showProducts() }
                            .buttonStyle(.borderless)
                    }.padding(20)
                }
                }
                if ["codex", "claude", "cursor"].contains(products.selected) {
                    Divider()
                    DisclosureGroup(L10n.isEnglish ? "Local consumption" : "本地消耗", isExpanded: $showsCost) {
                        VStack(alignment: .leading, spacing: 8) {
                            Button(L10n.isEnglish ? "Load consumption" : "读取消耗") { Task { await loadCost() } }.disabled(costLoading)
                            if costLoading { ProgressView().controlSize(.small) }
                            if let cost = costs[products.selected] { LocalCostCard(cost: cost) }
                            if let costError { Text(costError).font(.caption).foregroundStyle(.secondary) }
                        }.padding(.top, 8)
                    }.padding(16)
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
            .task(id: products.selected) {
                if products.selected != "codex" || codexAccounts == nil { await usage.refresh(provider: products.selected) }
            }
    }
    private func loadCost() async {
        guard !costLoading else { return }
        let provider = products.selected
        costLoading = true; costError = nil
        defer { costLoading = false }
        if let result = await ProviderCLI.fetchCost(provider: provider) { costs[provider] = result }
        else { costError = L10n.isEnglish ? "Local consumption could not be read." : "暂时无法读取本地消耗。" }
    }
}

struct ProviderUsageCard: View {
    let usage: ProviderUsage
    var compact = false
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 16) {
            HStack {
                ProviderBrandIcon(provider: usage.id).frame(width: 20, height: 20).foregroundStyle(.primary)
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
            if let updated = usage.updatedAt { Text(updated, format: .dateTime.hour().minute()).font(.caption2).foregroundStyle(.secondary) }
        }
        .padding(compact ? 12 : 20)
        .background(compact ? Color.clear : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08)))
    }
}

private struct UsageWindowView: View {
    let window: UsageWindow
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack { Text(window.label).font(.system(size: 12, weight: .medium)); Spacer(); Text("\(Int(window.remaining.rounded()))%").font(.system(size: 20, weight: .semibold, design: .rounded)).monospacedDigit() }
            ProgressView(value: max(0, min(100, window.remaining)), total: 100).tint(window.remaining <= 10 ? .red : window.remaining <= 25 ? .orange : Color(nsColor: .systemGreen))
            if let reset = window.resetAt {
                HStack { Image(systemName: "clock"); Text(reset, format: .dateTime.hour().minute()); Spacer(); Text(reset, style: .date) }
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

struct ProviderUsage: Decodable {
    let id: String
    let name: String
    let sourceAccount: String?
    let identity: Identity?
    let windows: [UsageWindow]
    let credits: Credits?
    let cost: UsageCost?
    let providerError: ProviderError?
    let details: [UsageDetailSection]?
    let updatedAt: Date?
    var account: String? { sourceAccount ?? identity?.accountEmail }
    var errorMessage: String? {
        guard providerError != nil else { return nil }
        return L10n.isEnglish ? "Unavailable or account setup is required. Sign in with the provider and refresh." : "暂不可用或需要先完成账号设置。请登录该提供商后刷新。"
    }
    static func displayName(_ id: String) -> String { ["claude":"Claude", "cursor":"Cursor", "gemini":"Gemini", "openrouter":"OpenRouter", "grok":"Grok", "kimi":"Kimi Code", "qwen-cloud":"Qwen Cloud", "zai":"GLM", "deepseek":"DeepSeek"][id] ?? id.capitalized }
    struct Identity: Decodable { let accountEmail: String?; let plan: String? }
    struct Credits: Decodable { let remaining: Double; let unit: String }
    struct UsageCost: Decodable { let todayUSD: Double?; let last30DaysUSD: Double? }
    struct ProviderError: Decodable { let message: String?; let code: Int?; let kind: String? }
    struct UsageDetailSection: Decodable { let title: String?; let rows: [UsageDetailRow]? }
    struct UsageDetailRow: Decodable { let label: String?; let value: String?; let secondaryValue: String? }
    private enum CodingKeys: String, CodingKey {
        case id, name, identity, windows, credits, cost, updatedAt, details, sourceAccount
        case providerError = "error"
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? Self.displayName(id)
        sourceAccount = try c.decodeIfPresent(String.self, forKey: .sourceAccount)
        identity = try c.decodeIfPresent(Identity.self, forKey: .identity)
        windows = try c.decodeIfPresent([UsageWindow].self, forKey: .windows) ?? []
        credits = try c.decodeIfPresent(Credits.self, forKey: .credits)
        cost = try c.decodeIfPresent(UsageCost.self, forKey: .cost)
        providerError = try c.decodeIfPresent(ProviderError.self, forKey: .providerError)
        details = try c.decodeIfPresent([UsageDetailSection].self, forKey: .details)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }
}

struct UsageWindow: Decodable {
    let label: String
    let remainingPercent: Double
    let resetAt: Date?
    let durationMinutes: Double?
    var remaining: Double { remainingPercent }
    private enum CodingKeys: String, CodingKey { case label, remainingPercent, resetAt, durationMinutes }
}

struct ProviderCLI {
    struct Result { var rows: [ProviderUsage]; var toolMissing = false }
    static func fetch(provider: String) async -> Result {
        await Task.detached(priority: .utility) {
            let value = run(provider: provider)
            return Result(rows: value.0, toolMissing: value.1)
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
        if let account = source["account"] as? String { normalized["sourceAccount"] = account }
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
            if let minutes, minutes > 0 { mapped["durationMinutes"] = minutes }
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

    static func decodeRows(_ payload: Data, provider: String) -> [ProviderUsage] {
        guard let raw = try? JSONSerialization.jsonObject(with: payload) else { return [] }
        let items = raw as? [[String: Any]] ?? (raw as? [String: Any]).map { [$0] } ?? []
        return items.compactMap { item in
            guard let data = try? JSONSerialization.data(withJSONObject: item) else { return nil }
            return decodeUsage(data, provider: provider)
        }
    }
    private static func run(provider: String) -> ([ProviderUsage], Bool) {
        guard executable != nil else { return ([], true) }
        if let all = execute(arguments: ["usage", "--provider", provider, "--all-accounts", "--format", "json", "--web-timeout", "12"]) {
            let rows = decodeRows(all, provider: provider)
            if rows.contains(where: { $0.errorMessage == nil && (!$0.windows.isEmpty || $0.details?.isEmpty == false || $0.credits != nil) }) { return (rows, false) }
        }
        guard let payload = execute(arguments: ["usage", "--provider", provider, "--format", "json", "--web-timeout", "12"]) else { return ([], false) }
        return (decodeRows(payload, provider: provider), false)
    }
    private static var executable: String? {
        ["/opt/homebrew/bin/codexbar", "/usr/local/bin/codexbar"].first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    }
    private static func execute(arguments: [String]) -> Data? {
        guard let path = executable else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
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

struct LocalCost: Decodable {
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
        }.padding(20).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }
}
