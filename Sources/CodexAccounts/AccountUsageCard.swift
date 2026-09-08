import SwiftUI
import SwitcherCore

struct AppBrandIcon: View {
    var body: some View {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            Image(nsImage: image).resizable().scaledToFit()
        } else {
            Image(systemName: "arrow.triangle.swap").resizable().scaledToFit().padding(16)
                .foregroundStyle(.white).background(Color.teal, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

struct AccountUsageCard: View {
    let profile: Profile
    @ObservedObject var store: AccountStore
    let onSwitch: () -> Void
    let onRename: () -> Void
    let onRemove: () -> Void
    var showsManagement = true
    @State private var expanded = false
    private let green = Color(red: 0.10, green: 0.52, blue: 0.41)
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
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: active ? "person.crop.circle.badge.checkmark" : "person.crop.circle")
                    .font(.system(size: 25, weight: .light)).foregroundStyle(green)
                    .frame(width: 46, height: 46).background(green.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 15, weight: .semibold)).lineLimit(1).help(profile.name)
                    Text(profile.snapshot?.email ?? "需要重新登录").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                Text((profile.snapshot?.plan ?? "unknown").uppercased())
                    .font(.system(size: 9, weight: .bold, design: .rounded)).tracking(0.7)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(.primary.opacity(0.05), in: Capsule())
                if showsManagement {
                Menu {
                    Button("重命名", action: onRename)
                    Button("移除账号", role: .destructive, action: onRemove)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("更多账号操作")
                    .accessibilityLabel("更多账号操作")
                    .disabled(store.busy)
                }
            }
            if let first = buckets.first {
                VStack(alignment: .leading, spacing: 16) {
                    bucketView(first.0, first.1)
                    if buckets.count > 1 {
                        DisclosureGroup(isExpanded: $expanded) {
                            VStack(spacing: 16) {
                                ForEach(Array(buckets.dropFirst()), id: \.0) { key, bucket in
                                    Divider()
                                    bucketView(key, bucket)
                                }
                            }.padding(.top, 12)
                        } label: {
                            Text("其他额度 · \(buckets.count - 1)").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                        }.tint(green)
                    }
                }.opacity(store.quotaErrors[profile.id] == nil ? 1 : 0.5)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "chart.bar.xaxis")
                    Text("尚未读取额度").font(.system(size: 12))
                    Spacer()
                    Text("点击上方刷新").font(.system(size: 11))
                }.foregroundStyle(.secondary).padding(.vertical, 12)
            }
            if let error = store.quotaErrors[profile.id] {
                Label(error, systemImage: "exclamationmark.circle").font(.system(size: 11)).foregroundStyle(.orange)
            }
            HStack {
                if active {
                    Label("当前使用", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(green)
                } else {
                    Button(action: onSwitch) { Label("切换到此账号", systemImage: "arrow.left.arrow.right") }
                        .font(.system(size: 11, weight: .medium)).buttonStyle(.borderless).tint(green).disabled(store.busy)
                }
                Spacer()
                if let date = store.quotaDates[profile.id] {
                    TimelineView(.periodic(from: .now, by: 60)) { timeline in
                        Text(updateLabel(date, now: timeline.date)).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
            }.padding(.top, 2)
        }.padding(20)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(active ? green.opacity(0.45) : Color.primary.opacity(0.08), lineWidth: 1))
            .shadow(color: .black.opacity(0.025), radius: 8, y: 3)
    }
    private func updateLabel(_ date: Date, now: Date) -> String {
        let mins = max(0, Int(now.timeIntervalSince(date) / 60))
        let prefix = store.quotaErrors[profile.id] == nil ? "更新" : "上次成功读取"
        return mins == 0 ? "刚刚\(prefix)" : "\(mins) 分钟前\(prefix)"
    }
    private func bucketView(_ key: String, _ bucket: QuotaBucket) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text(key == "codex" ? "CODEX" : (bucket.limitName ?? key).uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1).foregroundStyle(.secondary)
                Spacer()
                Text("剩余额度").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            if let window = bucket.primary { QuotaMeter(window: window, tint: green) }
            if let window = bucket.secondary { QuotaMeter(window: window, tint: green) }
            if bucket.primary == nil && bucket.secondary == nil {
                Text("服务未提供时间窗口").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct QuotaMeter: View {
    let window: QuotaWindow
    let tint: Color
    private var color: Color { window.remaining <= 10 ? .red : window.remaining <= 25 ? .orange : tint }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.title).font(.system(size: 12, weight: .medium))
                Spacer()
                Text("\(Int(window.remaining))").font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit()
                Text("%").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.055))
                    Capsule().fill(LinearGradient(colors: [color.opacity(0.75), color], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geometry.size.width * window.remaining / 100)
                }
            }.frame(height: 7)
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
    private func resetLabel(_ timestamp: Double, now: Date) -> String {
        let mins = Int(ceil((timestamp - now.timeIntervalSince1970) / 60))
        if mins <= 0 { return "已到重置时间 · 请刷新" }
        if mins >= 1440 { return "\(mins / 1440) 天 \(mins % 1440 / 60) 小时后重置" }
        if mins >= 60 { return "\(mins / 60) 小时 \(mins % 60) 分钟后重置" }
        return "\(mins) 分钟后重置"
    }
}
