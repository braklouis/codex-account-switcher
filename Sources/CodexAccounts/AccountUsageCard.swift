import SwiftUI
import SwitcherCore

struct AppBrandIcon: View {
    // The icon set supplies size-specific Retina representations, avoiding a
    // full-size texture being sampled down to a tiny menu image on every redraw.
    private static let image: NSImage? = {
        let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
            ?? Bundle.main.url(forResource: "AppIcon", withExtension: "png")
        return url.flatMap { NSImage(contentsOf: $0) }
    }()

    var body: some View {
        if let image = Self.image {
            Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
        } else {
            Image(systemName: "arrow.triangle.swap").resizable().scaledToFit().padding(16)
                .foregroundStyle(.white).background(Color.primary, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

struct AccountUsageCard: View {
    @ObservedObject private var language = AppPreferences.shared
    let profile: Profile
    @ObservedObject var store: AccountStore
    let onSwitch: () -> Void
    let onRename: () -> Void
    let onRemove: () -> Void
    var showsManagement = true
    var compact = false
    var flat = false
    @State private var expanded = false
    private let green = Color.primary
    private var active: Bool { profile.snapshot?.identity == store.activeIdentity }
    private var title: String {
        if profile.name == profile.snapshot?.email {
            return profile.name.components(separatedBy: "@").first ?? profile.name
        }
        return profile.name
    }
    private var buckets: [(String, QuotaBucket)] {
        (store.quotas[profile.id]?.buckets ?? []).sorted {
            if ($0.0 == "codex") != ($1.0 == "codex") { return $0.0 == "codex" }
            return $0.0 < $1.0
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 12 : 18) {
            HStack(spacing: compact ? 8 : 12) {
                Image(systemName: active ? "person.crop.circle.badge.checkmark" : "person.crop.circle")
                    .font(.system(size: compact ? 18 : 25, weight: .light)).foregroundStyle(green)
                    .frame(width: compact ? 30 : 46, height: compact ? 30 : 46).background(green.opacity(flat ? 0 : 0.08), in: RoundedRectangle(cornerRadius: compact ? 10 : 14))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: compact ? 12 : 15, weight: .semibold)).lineLimit(1).help(profile.name)
                    Text(profile.snapshot?.email ?? L10n.text("需要重新登录")).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                Text((profile.snapshot?.plan ?? "unknown").uppercased())
                    .font(.system(size: 9, weight: .bold, design: .rounded)).tracking(0.7)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(.primary.opacity(0.05), in: Capsule())
                if showsManagement {
                Menu {
                    Button(L10n.text("重命名"), action: onRename)
                    Button(L10n.text("移除账号"), role: .destructive, action: onRemove)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help(L10n.text("更多账号操作"))
                    .accessibilityLabel(L10n.text("更多账号操作"))
                    .disabled(store.busy)
                }
            }
            if let first = buckets.first {
                VStack(alignment: .leading, spacing: compact ? 10 : 16) {
                    bucketView(first.0, first.1)
                    if buckets.count > 1 {
                        DisclosureGroup(isExpanded: $expanded) {
                            VStack(spacing: compact ? 10 : 16) {
                                ForEach(Array(buckets.dropFirst()), id: \.0) { key, bucket in
                                    Divider()
                                    bucketView(key, bucket)
                                }
                            }.padding(.top, 12)
                        } label: {
                            Text(L10n.isEnglish ? "Other quotas · \(buckets.count - 1)" : "其他额度 · \(buckets.count - 1)").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                        }.tint(green)
                    }
                }.opacity(store.quotaErrors[profile.id] == nil ? 1 : 0.5)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "chart.bar.xaxis")
                    Text(L10n.text("尚未读取额度")).font(.system(size: 12))
                    Spacer()
                    Text(L10n.text("点击上方刷新")).font(.system(size: 11))
                }.foregroundStyle(.secondary).padding(.vertical, 12)
            }
            if let error = store.quotaErrors[profile.id] {
                Label(L10n.text(error), systemImage: "exclamationmark.circle").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            HStack {
                if active {
                    Label(L10n.text("当前使用"), systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(green)
                } else {
                    Button(action: onSwitch) { Label(L10n.text("切换到此账号"), systemImage: "arrow.left.arrow.right") }
                        .font(.system(size: 11, weight: .medium)).buttonStyle(.borderless).tint(green).disabled(store.busy)
                }
                Spacer()
                if let date = store.quotaDates[profile.id] {
                    TimelineView(.periodic(from: .now, by: 60)) { timeline in
                        Text(updateLabel(date, now: timeline.date)).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
            }.padding(.top, 2)
        }.padding(flat ? 4 : (compact ? 12 : 20))
            .background(compact ? Color.clear : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(flat ? Color.clear : (active ? green.opacity(0.45) : Color.primary.opacity(0.08)), lineWidth: 1))

    }
    private func updateLabel(_ date: Date, now: Date) -> String {
        let mins = max(0, Int(now.timeIntervalSince(date) / 60))
        if L10n.isEnglish { return mins == 0 ? "Updated just now" : "Updated \(mins)m ago" }
        let prefix = store.quotaErrors[profile.id] == nil ? "更新" : "上次成功读取"
        return mins == 0 ? "刚刚\(prefix)" : "\(mins) 分钟前\(prefix)"
    }
    private func bucketView(_ key: String, _ bucket: QuotaBucket) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            if !flat || key != "codex" {
            HStack {
                Text(key == "codex" ? "CODEX" : (bucket.limitName ?? key).uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1).foregroundStyle(.secondary)
                Spacer()
                Text(L10n.text("剩余额度")).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            }
            if let window = bucket.primary { QuotaMeter(window: window, tint: green, compact: compact, dense: flat) }
            if let window = bucket.secondary { QuotaMeter(window: window, tint: green, compact: compact, dense: flat) }
            if bucket.primary == nil && bucket.secondary == nil {
                Text(L10n.text("服务未提供时间窗口")).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct QuotaMeter: View {
    @ObservedObject private var language = AppPreferences.shared
    let window: QuotaWindow
    let tint: Color
    var compact = false
    var dense = false
    private var color: Color { tint }
    @ViewBuilder var body: some View {
        if dense {
            HStack(spacing: 10) {
                Text(L10n.text(window.title)).font(.caption).frame(width: 62, alignment: .leading)
                ProgressView(value: max(0, min(100, window.remaining)), total: 100).tint(color).frame(maxWidth: 120)
                Text("\(Int(window.remaining))%").font(.callout.monospacedDigit()).frame(width: 38, alignment: .trailing)
                Spacer(minLength: 0)
                if let reset = window.resetsAt {
                    Text(Date(timeIntervalSince1970: reset), format: .dateTime.month(.twoDigits).day(.twoDigits).hour().minute())
                        .font(.caption).foregroundStyle(.secondary)
                        .help(L10n.isEnglish ? "Reset time" : "重置时间")
                }
            }
        } else {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.text(window.title)).font(.system(size: 12, weight: .medium))
                Spacer()
                Text("\(Int(window.remaining))").font(.system(size: compact ? 18 : 22, weight: .semibold, design: .rounded)).monospacedDigit()
                Text("%").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            }
            ProgressView(value: max(0, min(100, window.remaining)), total: 100)
                .tint(color)
                .accessibilityLabel("\(window.title)剩余 \(Int(window.remaining))%")
            if let reset = window.resetsAt {
                TimelineView(.periodic(from: .now, by: 60)) { timeline in
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                        Text(resetLabel(reset, now: timeline.date))
                        Spacer()
                        Text(Date(timeIntervalSince1970: reset), format: .dateTime.month(.twoDigits).day(.twoDigits).hour().minute())
                    }.font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
        }
    }
    }
    private func resetLabel(_ timestamp: Double, now: Date) -> String {
        let mins = Int(ceil((timestamp - now.timeIntervalSince1970) / 60))
        if L10n.isEnglish { return mins <= 0 ? "Reset time reached · Refresh" : "Resets in \(mins / 1440)d \(mins % 1440 / 60)h \(mins % 60)m" }
        if mins <= 0 { return L10n.text("已到重置时间 · 请刷新") }
        if mins >= 1440 { return "\(mins / 1440) 天 \(mins % 1440 / 60) 小时后重置" }
        if mins >= 60 { return "\(mins / 60) 小时 \(mins % 60) 分钟后重置" }
        return "\(mins) 分钟后重置"
    }
}
