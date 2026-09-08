import SwiftUI
import SwitcherCore

struct AccountsView: View {
    @ObservedObject private var language = AppPreferences.shared
    @ObservedObject var store: AccountStore
    @Environment(\.openWindow) private var openWindow
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
                    Text(L10n.text("你的账号，一目了然")).font(.system(size: 28, weight: .semibold))
                    Text(L10n.text("查看可用额度，为下一项任务选好账号。"))
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer()
                AppBrandIcon().frame(width: 68, height: 68)
            }.padding(28)
            HStack(spacing: 10) {
                Circle().fill(store.activeEmail == nil ? .gray : accent).frame(width: 7, height: 7)
                Text(L10n.text("当前登录")).foregroundStyle(.secondary)
                Text(store.activeEmail ?? L10n.text("尚未登录 / 登录不可读")).lineLimit(1).textSelection(.enabled)
                Spacer()
                if store.demo { Text(L10n.text("演示")).foregroundStyle(.orange) }
            }.font(.system(size: 12)).padding(.horizontal, 28).padding(.bottom, 20)
            Divider()
            HStack {
                Text(L10n.text("已保存账号")).font(.headline)
                Text("\(store.profiles.count)").foregroundStyle(.secondary)
                Spacer()
                Button { store.refreshQuotas() } label: { Label(L10n.text("刷新额度"), systemImage: "arrow.clockwise") }
                    .disabled(store.busy || store.profiles.isEmpty)
            }.padding(.horizontal, 28).padding(.vertical, 18)
            ScrollView {
                LazyVStack(spacing: 12) {
                    if !store.loaded {
                        ContentUnavailableView {
                            Label(L10n.text("账号库尚未解锁"), systemImage: "lock.shield")
                        } description: { Text(L10n.text("允许钥匙串访问后重试，原账号数据会保留。")) }
                        actions: { Button(L10n.text("重新读取")) { store.reload() } }
                    } else if store.profiles.isEmpty {
                        ContentUnavailableView {
                            Label(L10n.text("先保存你的第一个账号"), systemImage: "person.crop.circle.badge.plus")
                        } description: { Text(L10n.text("保存当前 Codex 登录，或通过浏览器添加另一个会员账号。")) }
                    }
                    ForEach(store.orderedProfiles) { profile in accountCard(profile) }
                }.padding(.horizontal, 28).padding(.bottom, 20)
            }
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button { store.addAccount() } label: { Label(L10n.text("登录新账号"), systemImage: "plus") }
                        .buttonStyle(.borderedProminent).tint(accent)
                    Button(L10n.text("保存当前账号")) { store.importCurrent() }
                    Button(L10n.text("设置…")) { openWindow(id: "preferences") }
                    Spacer()
                    if store.busy { ProgressView().controlSize(.small) }
                }.disabled(store.busy || !store.loaded)
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: store.demo ? "eye" : "lock.shield")
                    Text(L10n.text(store.status)).fixedSize(horizontal: false, vertical: true)
                    if store.busy && store.status.contains("浏览器") {
                        Button(L10n.text("取消")) { store.cancelLogin() }.buttonStyle(.link)
                    }
                }.font(.system(size: 11)).foregroundStyle(.secondary)
            }.padding(24)
        }
        .frame(minWidth: 640, minHeight: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .onReceive(NotificationCenter.default.publisher(for: .chooseAccount)) { note in
            if let id = note.object as? UUID { switchTarget = store.profiles.first { $0.id == id } }
        }
        .alert(L10n.text("切换并重新打开 Codex？"), isPresented: Binding(get: { switchTarget != nil }, set: { if !$0 { switchTarget = nil } }), presenting: switchTarget) { target in
            Button(L10n.text("取消"), role: .cancel) { switchTarget = nil }
            Button(L10n.text("切换并重启")) { store.switchTo(target); switchTarget = nil }
                .disabled(store.busy)
        } message: { target in
            Text(L10n.isEnglish ? "Switch to \(target.name). Finish active Codex tasks and CLI sessions first. Codex will close and reopen; local history stays shared." : "将切换到「\(target.name)」。请先结束正在运行的 Codex 任务和命令行会话。切换会关闭并重新打开桌面应用；本地任务历史继续共用。")
        }
        .alert(L10n.text("移除保存的账号？"), isPresented: Binding(get: { removeTarget != nil }, set: { if !$0 { removeTarget = nil } })) {
            Button(L10n.text("取消"), role: .cancel) { removeTarget = nil }
            Button(L10n.text("移除"), role: .destructive) { if let target = removeTarget { store.remove(target) }; removeTarget = nil }
        } message: { Text(L10n.text("仅从本工具移除，当前 Codex 登录不会退出。以后可重新添加。")) }
        .alert(L10n.text("账号名称"), isPresented: Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })) {
            TextField(L10n.text("例如：主力账号"), text: $name)
            Button(L10n.text("取消"), role: .cancel) { renameTarget = nil }
            Button(L10n.text("保存")) { if let target = renameTarget { store.rename(target, to: name) }; renameTarget = nil }
        }
        .alert(L10n.text("操作未完成"), isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button(L10n.text("好")) { store.error = nil }
        } message: { Text(L10n.text(store.error ?? "")) }
    }

    private func accountCard(_ profile: Profile) -> some View {
        AccountUsageCard(profile: profile, store: store,
            onSwitch: { switchTarget = profile },
            onRename: { name = profile.name; renameTarget = profile },
            onRemove: { removeTarget = profile })
    }
}
