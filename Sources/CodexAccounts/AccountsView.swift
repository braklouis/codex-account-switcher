import SwiftUI
import SwitcherCore

struct AccountsView: View {
    @ObservedObject var store: AccountStore
    @State private var switchTarget: Profile?
    @State private var removeTarget: Profile?
    @State private var renameTarget: Profile?
    @State private var name = ""
    private let accent = Color(red: 0.12, green: 0.49, blue: 0.40)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("CODEX ACCOUNTS").font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(2).foregroundStyle(accent)
                    Text("账号随时切换").font(.system(size: 28, weight: .semibold))
                    Text("查看可用额度，为下一项任务选好账号。")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "person.2.badge.key.fill").font(.system(size: 30)).foregroundStyle(accent)
                    .frame(width: 62, height: 62).background(accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 18))
            }.padding(28)
            HStack(spacing: 10) {
                Circle().fill(store.activeEmail == nil ? .gray : accent).frame(width: 7, height: 7)
                Text("当前登录").foregroundStyle(.secondary)
                Text(store.activeEmail ?? "尚未登录 / 登录不可读").lineLimit(1).textSelection(.enabled)
                Spacer()
                if store.demo { Text("演示").foregroundStyle(.orange) }
            }.font(.system(size: 12)).padding(.horizontal, 28).padding(.bottom, 20)
            Divider()
            HStack {
                Text("已保存账号").font(.headline)
                Text("\(store.profiles.count)").foregroundStyle(.secondary)
                Spacer()
                Button { store.refreshQuotas() } label: { Label("刷新额度", systemImage: "arrow.clockwise") }
                    .disabled(store.busy || store.profiles.isEmpty)
            }.padding(.horizontal, 28).padding(.vertical, 18)
            ScrollView {
                LazyVStack(spacing: 12) {
                    if !store.loaded {
                        ContentUnavailableView {
                            Label("账号库尚未解锁", systemImage: "lock.shield")
                        } description: { Text("允许钥匙串访问后重试，原账号数据会保留。") }
                        actions: { Button("重新读取") { store.reload() } }
                    } else if store.profiles.isEmpty {
                        ContentUnavailableView {
                            Label("先保存你的第一个账号", systemImage: "person.crop.circle.badge.plus")
                        } description: { Text("保存当前 Codex 登录，或通过浏览器添加另一个会员账号。") }
                    }
                    ForEach(store.profiles) { profile in accountCard(profile) }
                }.padding(.horizontal, 28).padding(.bottom, 20)
            }
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button { store.addAccount() } label: { Label("登录新账号", systemImage: "plus") }
                        .buttonStyle(.borderedProminent).tint(accent)
                    Button("保存当前账号") { store.importCurrent() }
                    Spacer()
                    if store.busy { ProgressView().controlSize(.small) }
                }.disabled(store.busy || !store.loaded)
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: store.demo ? "eye" : "lock.shield")
                    Text(store.status).fixedSize(horizontal: false, vertical: true)
                    if store.busy && store.status.contains("浏览器") {
                        Button("取消") { store.cancelLogin() }.buttonStyle(.link)
                    }
                }.font(.system(size: 11)).foregroundStyle(.secondary)
            }.padding(24)
        }
        .frame(minWidth: 600, minHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .onReceive(NotificationCenter.default.publisher(for: .chooseAccount)) { note in
            if let id = note.object as? UUID { switchTarget = store.profiles.first { $0.id == id } }
        }
        .alert("切换并重新打开 Codex？", isPresented: Binding(get: { switchTarget != nil }, set: { if !$0 { switchTarget = nil } })) {
            Button("取消", role: .cancel) { switchTarget = nil }
            Button("切换并重启") { if let target = switchTarget { store.switchTo(target) }; switchTarget = nil }
        } message: {
            Text("将切换到「\(switchTarget?.name ?? "")」。请先结束正在运行的 Codex 任务和命令行会话。切换会关闭并重新打开桌面应用；本地任务历史继续共用。")
        }
        .alert("移除保存的账号？", isPresented: Binding(get: { removeTarget != nil }, set: { if !$0 { removeTarget = nil } })) {
            Button("取消", role: .cancel) { removeTarget = nil }
            Button("移除", role: .destructive) { if let target = removeTarget { store.remove(target) }; removeTarget = nil }
        } message: { Text("仅从本工具移除，当前 Codex 登录不会退出。以后可重新添加。") }
        .alert("账号名称", isPresented: Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })) {
            TextField("例如：主力账号", text: $name)
            Button("取消", role: .cancel) { renameTarget = nil }
            Button("保存") { if let target = renameTarget { store.rename(target, to: name) }; renameTarget = nil }
        }
        .alert("操作未完成", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("好") { store.error = nil }
        } message: { Text(store.error ?? "") }
    }

    private func accountCard(_ profile: Profile) -> some View {
        let active = profile.snapshot?.identity == store.activeIdentity
        return VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 12) {
                Text(String(profile.name.prefix(1)).uppercased()).font(.system(size: 19, weight: .medium))
                    .frame(width: 42, height: 42).background(accent.opacity(active ? 0.15 : 0.06), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(profile.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        Text((profile.snapshot?.plan ?? "unknown").uppercased()).font(.system(size: 9, weight: .bold))
                            .foregroundStyle(accent).padding(.horizontal, 6).padding(.vertical, 3).background(accent.opacity(0.08), in: Capsule())
                    }
                    Text(profile.snapshot?.email ?? "需要重新登录").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if active { Label("使用中", systemImage: "checkmark.circle.fill").font(.system(size: 11, weight: .medium)).foregroundStyle(accent) }
                else { Button("切换") { switchTarget = profile }.disabled(store.busy) }
                Menu {
                    Button("重命名") { name = profile.name; renameTarget = profile }
                    Button("移除账号", role: .destructive) { removeTarget = profile }
                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 20).disabled(store.busy)
            }
            if let quota = store.quotas[profile.id], !quota.buckets.isEmpty {
                ForEach(quota.buckets, id: \.0) { key, bucket in
                    VStack(alignment: .leading, spacing: 8) {
                        if quota.buckets.count > 1 { Text(bucket.limitName ?? key).font(.caption).foregroundStyle(.secondary) }
                        HStack(spacing: 22) {
                            if let primary = bucket.primary { quotaView(primary) }
                            if let secondary = bucket.secondary { quotaView(secondary) }
                            if bucket.primary == nil && bucket.secondary == nil { Text("此额度未提供时间窗口").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }.opacity(store.quotaErrors[profile.id] == nil ? 1 : 0.5)
                if let date = store.quotaDates[profile.id] {
                    Text("\(store.quotaErrors[profile.id] == nil ? "更新于" : "上次成功读取") \(date.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                }
            } else {
                Text("点击“刷新额度”查看剩余用量").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if let error = store.quotaErrors[profile.id] { Text(error).font(.system(size: 11)).foregroundStyle(.orange) }
        }.padding(18)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(active ? accent.opacity(0.45) : Color.primary.opacity(0.07), lineWidth: 1))
    }
    private func quotaView(_ window: QuotaWindow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(window.title).foregroundStyle(.secondary)
                Spacer()
                Text("剩余 \(Int(window.remaining))%").monospacedDigit()
            }.font(.system(size: 11))
            ProgressView(value: window.remaining, total: 100).tint(window.remaining < 20 ? .orange : accent)
            if let reset = window.resetsAt {
                Text("重置 \(Date(timeIntervalSince1970: reset).formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        }.frame(maxWidth: .infinity)
    }
}
