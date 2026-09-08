import SwiftUI
import AppKit
import SwitcherCore

@main struct CodexAccountsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var store = AccountStore(demo: CommandLine.arguments.contains("--demo") || CommandLine.arguments.contains("--self-check"))
    var body: some Scene {
        Window("Codex Accounts", id: "accounts") {
            AccountsView(store: store)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in store.refreshActive() }
        }
        .defaultSize(width: 700, height: 780)
        .windowResizability(.contentMinSize)
        Window(L10n.text("设置"), id: "preferences") { PreferencesView() }.windowResizability(.contentSize)
        MenuBarExtra {
            MenuContent(store: store)
        } label: {
            MenuQuotaLabel(store: store)
        }.menuBarExtraStyle(.window)
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--self-check") {
            Task { await selfCheck() }
            return
        }
        guard let id = Bundle.main.bundleIdentifier else { return }
        let peers = NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if let peer = peers.first { peer.activate(options: [.activateAllWindows]); NSApp.terminate(nil); return }
        if !CommandLine.arguments.contains("--demo") { AppPreferences.shared.start() }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    private func selfCheck() async {
        do {
            let vault = KeychainVault(service: "local.codexaccounts.selfcheck." + UUID().uuidString)
            defer { try? vault.deleteTestVault() }
            let profile = Profile(name: "Synthetic test", auth: Data("synthetic-no-credentials".utf8))
            try vault.save([profile])
            guard try vault.load().first?.auth == profile.auth else { throw SwitcherError("Keychain round-trip failed") }
            try vault.save([])
            guard try vault.load().isEmpty else { throw SwitcherError("Keychain update failed") }
            print("PASS: isolated Keychain add / read / update")
            guard let cli = CodexBridge().cliURL else { throw SwitcherError("Codex not found") }
            let rpc = try RPCSession(cli: cli)
            defer { rpc.stop() }
            try await rpc.start()
            let result = try await rpc.request("account/read", ["refreshToken": false])
            guard result["account"] is NSNull else { throw SwitcherError("Isolated server unexpectedly has an account") }
            print("PASS: bundled app-server initialization / account read / home isolation")
            rpc.stop()
            try await Task.sleep(nanoseconds: 4_000_000_000)
            guard !FileManager.default.fileExists(atPath: rpc.directory.path) else { throw SwitcherError("Temporary home cleanup failed") }
            print("PASS: helper exit and temporary home cleanup")
            fflush(stdout)
            NSApp.terminate(nil)
        } catch {
            print("FAIL: \((error as? SwitcherError)?.message ?? "Integration check failed")")
            fflush(stdout)
            exit(1)
        }
    }
}

struct MenuContent: View {
    @ObservedObject private var language = AppPreferences.shared
    @ObservedObject var store: AccountStore
    @Environment(\.openWindow) private var openWindow
    @State private var switchTarget: Profile?
    private let tint = Color(red: 0.10, green: 0.52, blue: 0.41)

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                AppBrandIcon().frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Codex Accounts").font(.system(size: 14, weight: .semibold))
                    Text(L10n.text("各账号剩余额度")).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                if store.busy { ProgressView().controlSize(.small) }
                Button { store.refreshQuotas() } label: {
                    Image(systemName: "arrow.clockwise").frame(width: 26, height: 26)
                }.buttonStyle(.borderless).help(L10n.text("刷新额度")).accessibilityLabel(L10n.text("刷新额度"))
                    .disabled(store.busy || store.profiles.isEmpty)
            }.padding(16)
            Divider()
            ScrollView {
                VStack(spacing: 12) {
                    if store.profiles.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "person.crop.circle.badge.plus").font(.title)
                            Text(store.loaded ? L10n.text("先添加一个账号") : L10n.text("请解锁账号库"))
                            Button(L10n.text("打开账号管理"), action: manage)
                        }.padding(28)
                    }
                    ForEach(store.orderedProfiles) { profile in
                        AccountUsageCard(profile: profile, store: store,
                            onSwitch: { switchTarget = profile },
                            onRename: manage, onRemove: manage, showsManagement: false)
                    }
                }.padding(12)
            }.frame(height: store.profiles.isEmpty ? 160 : 480)
            Divider()
            HStack {
                Button(L10n.text("管理账号…"), action: manage)
                Button(L10n.text("设置…")) { openWindow(id: "preferences"); NSApp.activate(ignoringOtherApps: true) }
                Spacer()
                Button(L10n.text("退出")) { NSApp.terminate(nil) }.disabled(store.busy)
            }.font(.system(size: 12)).buttonStyle(.borderless).padding(16)
        }
        .frame(width: 400)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(tint)
        .onAppear {
            store.refreshActive()
            // Read on open if missing or older than a minute; both windows share one store.
            if !store.busy && store.loaded && store.profiles.contains(where: {
                guard let date = store.quotaDates[$0.id] else { return true }
                return Date().timeIntervalSince(date) > 60
            }) { store.refreshQuotas() }
        }
        .alert(L10n.text("切换并重新打开 Codex？"), isPresented: Binding(
            get: { switchTarget != nil }, set: { if !$0 { switchTarget = nil } }), presenting: switchTarget) { target in
            Button(L10n.text("取消"), role: .cancel) { switchTarget = nil }
            Button(L10n.text("切换并重启")) {
                store.switchTo(target)
                switchTarget = nil
            }
            .disabled(store.busy)
        } message: { target in
            Text(L10n.isEnglish ? "Switch to \(target.name). Finish active Codex tasks and CLI sessions first. Codex will close and reopen; local history stays shared." : "将切换到「\(target.name)」。请先结束正在运行的 Codex 任务和命令行会话，桌面应用会关闭并重新打开。")
        }
    }
    private func manage() {
        openWindow(id: "accounts")
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension Notification.Name { static let chooseAccount = Notification.Name("chooseAccount") }
