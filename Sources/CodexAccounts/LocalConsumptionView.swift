import SwiftUI
import Charts

struct LocalCost: Decodable {
    let provider: String
    let error: ProviderUsage.ProviderError?
    let last30DaysTokens: Int64?
    let last30DaysCostUSD: Double?
    let provenance: String?
    let totals: Totals?
    let daily: [Day]?
    let projects: [Project]?
    struct Totals: Decodable {
        let inputTokens: Int64?
        let outputTokens: Int64?
        let cacheReadTokens: Int64?
    }
    struct Model: Decodable {
        let modelName: String
        let cost: Double?
        let totalTokens: Int64?
    }
    struct Day: Decodable, Identifiable {
        let date: String
        let totalTokens: Int64?
        let totalCost: Double?
        let modelBreakdowns: [Model]?
        var id: String { date }
    }
    struct Project: Decodable {
        let name: String
        let path: String?
        let totalTokens: Int64?
        let totalCost: Double?
        let modelBreakdowns: [Model]?
    }
    var sortedDays: [Day] { (daily ?? []).sorted { $0.date < $1.date } }
    var today: Day? {
        let format = DateFormatter(); format.dateFormat = "yyyy-MM-dd"
        format.locale = Locale(identifier: "en_US_POSIX")
        return daily?.first { $0.date == format.string(from: Date()) }
    }
}

@MainActor final class LocalConsumptionStore: ObservableObject {
    static let shared = LocalConsumptionStore()
    @Published var values: [String: LocalCost] = [:]
    @Published var loading: Set<String> = []
    @Published var errors: Set<String> = []
    private var refreshed: [String: Date] = [:]
    func refresh(_ provider: String, force: Bool = false) async {
        guard !loading.contains(provider) else { return }
        guard force || Date().timeIntervalSince(refreshed[provider] ?? .distantPast) > 300 else { return }
        loading.insert(provider)
        defer { loading.remove(provider); refreshed[provider] = Date() }
        if let value = await ProviderCLI.fetchCost(provider: provider) {
            values[provider] = value; errors.remove(provider)
        } else { errors.insert(provider) }
    }
}

struct LocalConsumptionView: View {
    let provider: String
    @ObservedObject private var store = LocalConsumptionStore.shared
    @State private var expanded = false
    var body: some View {
        DisclosureGroup(L10n.isEnglish ? "Tokens & estimated cost" : "Token 与估算费用", isExpanded: $expanded) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let cost = store.values[provider] { LocalCostCard(cost: cost) }
                    if store.loading.contains(provider) { ProgressView().controlSize(.small) }
                    if store.errors.contains(provider) {
                        Text(L10n.isEnglish ? "Could not read consumption. Try again." : "暂时无法读取消耗，请重试。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Button(L10n.isEnglish ? "Refresh consumption" : "刷新消耗") {
                        Task { await store.refresh(provider, force: true) }
                    }.disabled(store.loading.contains(provider))
                }.padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 320)
        }
        .task(id: "\(provider)|\(expanded)") {
            if expanded { await store.refresh(provider) }
        }
    }
}

struct LocalCostCard: View {
    let cost: LocalCost
    @State private var metric = "tokens"
    @State private var selectedDay: String?
    private func tokens(_ value: Int64?) -> String { value.map { $0.formatted(.number.notation(.compactName)) } ?? "—" }
    private func dollars(_ value: Double?) -> String { value.map { $0.formatted(.currency(code: "USD")) } ?? "—" }
    private var selected: LocalCost.Day? {
        cost.sortedDays.first { $0.date == selectedDay } ?? cost.sortedDays.last
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                summary(L10n.isEnglish ? "Today" : "今日", tokens: cost.today?.totalTokens, amount: cost.today?.totalCost)
                Spacer()
                summary(L10n.isEnglish ? "30 days" : "近 30 天", tokens: cost.last30DaysTokens, amount: cost.last30DaysCostUSD)
            }
            if !cost.sortedDays.isEmpty {
                Picker(L10n.isEnglish ? "Chart" : "图表", selection: $metric) {
                    Text("Tokens").tag("tokens")
                    Text(L10n.isEnglish ? "Cost" : "费用").tag("cost")
                }.pickerStyle(.segmented).labelsHidden()
                Chart(cost.sortedDays) { day in
                    if let value = metric == "tokens" ? day.totalTokens.map(Double.init) : day.totalCost {
                        BarMark(x: .value("Day", day.date), y: .value(metric, value))
                            .foregroundStyle(Color.primary.opacity(selected?.date == day.date ? 1 : 0.45))
                    }
                }
                .chartXSelection(value: $selectedDay)
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let number = value.as(Double.self) {
                                Text(number.formatted(.number.notation(.compactName)))
                            }
                        }
                    }
                }
                .frame(height: 110)
                Picker(L10n.isEnglish ? "Day" : "日期", selection: Binding(get: { selected?.date ?? "" }, set: { selectedDay = $0 })) {
                    ForEach(cost.sortedDays) { day in Text(day.date).tag(day.date) }
                }
                if let selected {
                    Text("\(tokens(selected.totalTokens)) tokens · \(dollars(selected.totalCost))").font(.caption).foregroundStyle(.secondary)
                    ForEach(Array((selected.modelBreakdowns ?? []).enumerated()), id: \.offset) { _, model in
                        detailRow(model.modelName, tokens: model.totalTokens, amount: model.cost)
                    }
                }
            }
            if let projects = cost.projects, !projects.isEmpty {
                DisclosureGroup(L10n.isEnglish ? "Projects" : "项目") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(projects.enumerated()), id: \.offset) { _, project in
                            detailRow(project.name, tokens: project.totalTokens, amount: project.totalCost)
                                .help(project.path ?? project.name)
                        }
                    }.padding(.top, 8)
                }
            }
            DisclosureGroup(L10n.isEnglish ? "Token breakdown" : "Token 明细") {
                VStack(spacing: 6) {
                    detailRow(L10n.isEnglish ? "Input (includes cache)" : "输入（含缓存）", tokens: cost.totals?.inputTokens, amount: nil)
                    detailRow(L10n.isEnglish ? "Cache reads" : "缓存读取", tokens: cost.totals?.cacheReadTokens, amount: nil)
                    detailRow(L10n.isEnglish ? "Output" : "输出", tokens: cost.totals?.outputTokens, amount: nil)
                }.padding(.top, 8)
            }
            Text(L10n.isEnglish ? "Estimated from usage, not a subscription bill. Local history may be incomplete and shared across accounts. — means unavailable." : "按用量估算，不是订阅账单。本地历史可能不完整且跨账号共享；— 表示无数据。")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
    private func summary(_ title: String, tokens value: Int64?, amount: Double?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(dollars(amount)).font(.headline)
            Text(tokens(value) + " tokens").font(.caption)
        }
    }
    private func detailRow(_ name: String, tokens value: Int64?, amount: Double?) -> some View {
        HStack {
            Text(name).lineLimit(1)
            Spacer()
            Text(tokens(value)).monospacedDigit()
            if let amount { Text(dollars(amount)).monospacedDigit() }
        }.font(.caption)
    }
}
