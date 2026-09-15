import SwiftUI
import AppKit
import SwitcherCore

@main struct CodexAccountsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var store = AccountStore(demo: CommandLine.arguments.contains("--demo") || CommandLine.arguments.contains("--self-check"))
    var body: some Scene {
        workspaceWindow
        MenuBarExtra {
            MenuContent(store: store)
        } label: {
            MenuQuotaLabel(store: store)
        }.menuBarExtraStyle(.window)
    }
    private var workspaceWindow: some Scene {
        Window("TokenDeck", id: "workspace") {
            WorkspaceView(store: store)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in store.refreshActive() }
        }
        .defaultSize(width: 760, height: 740)
        .windowResizability(.contentMinSize)
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
        if let peer = peers.first { peer.activate(options: []); NSApp.terminate(nil); return }
        if !CommandLine.arguments.contains("--demo") {
            AppPreferences.shared.start()
            // Launch quietly; explicit menu actions are the only window-opening path.
            DispatchQueue.main.async {
                for window in NSApp.windows where window.title == "TokenDeck" {
                    window.isRestorable = false
                    window.orderOut(nil)
                }
            }
        }
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
    @ObservedObject private var products = ProductPreferences.shared
    @ObservedObject private var usage = ProviderUsageStore.shared
    @ObservedObject var store: AccountStore
    @Environment(\.openWindow) private var openWindow
    private let tint = Color.accentColor
    private var isCodex: Bool { products.selected == "codex" }
    private var activeProfile: Profile? {
        store.orderedProfiles.first { $0.snapshot?.identity == store.activeIdentity } ?? store.orderedProfiles.first
    }
    private var productName: String {
        ProductPreferences.catalog.first { $0.id == products.selected }?.name ?? products.selected
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                AppBrandIcon().frame(width: 23, height: 23)
                Text("TokenDeck").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button { open("products") } label: { Image(systemName: "slider.horizontal.3") }
                    .help(L10n.isEnglish ? "Choose products" : "选择产品")
                Button { refresh(force: true) } label: {
                    Image(systemName: "arrow.clockwise")
                }.disabled(isCodex ? store.busy : usage.isLoading(products.selected))
            }.buttonStyle(.borderless).padding(12)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(products.enabled, id: \.self) { id in
                        Button { products.selected = id } label: {
                            HStack(spacing: 4) {
                                ProviderBrandIcon(provider: id).frame(width: 12, height: 12)
                                Text(ProductPreferences.catalog.first { $0.id == id }?.name ?? id)
                            }
                                .font(.system(size: 11, weight: products.selected == id ? .semibold : .medium))
                                .padding(.horizontal, 9).padding(.vertical, 6)
                                .foregroundStyle(products.selected == id ? tint : Color.secondary)
                                .background(products.selected == id ? tint.opacity(0.12) : Color.primary.opacity(0.035), in: Capsule())
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, 10)
            }.padding(.bottom, 9)
            Divider()
            HStack {
                Text(productName).font(.system(size: 12, weight: .semibold))
                Spacer()
                if isCodex {
                    Menu {
                        ForEach(store.orderedProfiles) { profile in
                            Button {
                                if profile.snapshot?.identity != store.activeIdentity { store.confirmSwitch(profile) }
                            } label: {
                                Label(profile.name + (profile.snapshot?.identity == store.activeIdentity ? (L10n.isEnglish ? " · Current" : " · 当前使用") : ""), systemImage: profile.snapshot?.identity == store.activeIdentity ? "checkmark.circle.fill" : "arrow.triangle.swap")
                            }.disabled(store.busy)
                        }
                        Divider()
                        Button(L10n.isEnglish ? "Manage accounts…" : "管理账号…") { open("accounts") }
                    } label: {
                        accountControl(title: L10n.isEnglish ? "Switch account" : "切换账号", account: activeProfile?.name)
                    }.menuStyle(.borderlessButton)
                } else {
                    Menu {
                        ForEach(Array((usage.rows[products.selected] ?? []).enumerated()), id: \.offset) { index, row in
                            Button(row.account ?? "\(L10n.isEnglish ? "Account" : "账号") \(index + 1)") {
                                usage.selectAccount(provider: products.selected, index: index)
                            }
                        }
                        Divider()
                        Button(L10n.isEnglish ? "Login & accounts…" : "登录与账号…") { open("products") }
                    } label: {
                        accountControl(title: L10n.isEnglish ? "View account" : "查看账号", account: usage.selectedUsage(provider: products.selected)?.account)
                    }.menuStyle(.borderlessButton)
                }
            }.font(.system(size: 11)).padding(.horizontal, 12).padding(.vertical, 9)
            ScrollView {
                VStack(spacing: 10) {
                    if isCodex {
                        if let profile = activeProfile {
                            AccountUsageCard(profile: profile, store: store,
                                onSwitch: { store.confirmSwitch(profile) },
                                onRename: { open("accounts") }, onRemove: { open("accounts") }, showsManagement: false, compact: true)
                        } else {
                            emptyState
                        }
                    } else if let row = usage.selectedUsage(provider: products.selected) {
                        ProviderUsageCard(usage: row, compact: true)
                    } else if usage.isLoading(products.selected) {
                        ProgressView().padding(40)
                    } else {
                        emptyState
                    }
                }.background(AutoHidingScrollbars()).padding(.horizontal, 12).padding(.bottom, 9)
            }.frame(height: 260)
            Divider()
            HStack {
                Button(L10n.isEnglish ? "Usage & spend" : "额度与消耗") { open("providers") }
                Spacer()
                Button { open("preferences") } label: { Image(systemName: "gearshape") }
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }.disabled(store.busy)
            }.font(.system(size: 12)).buttonStyle(.borderless).padding(12)
        }
        .frame(width: 330)
        .modifier(MenuGlassSurface())
        .tint(tint)
        .task(id: products.selected) { refresh(force: false) }
    }
    private func accountControl(title: String, account: String?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.swap").font(.system(size: 12, weight: .medium))
            VStack(alignment: .trailing, spacing: 2) {
                Text(title).font(.system(size: 10, weight: .semibold))
                if let account {
                    Text(account).font(.system(size: 10)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
        }.frame(maxWidth: 180, alignment: .trailing)
            .help(title)
            .accessibilityLabel(title + (account.map { ": " + $0 } ?? ""))
    }
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.plus").font(.system(size: 26)).foregroundStyle(tint)
            Text(L10n.isEnglish ? "Connect your account to see usage" : "连接账号后查看额度").font(.callout)
            Button(L10n.isEnglish ? "Login & settings" : "登录与设置") { open(isCodex ? "accounts" : "products") }
        }.frame(maxWidth: .infinity).padding(.vertical, 40)
    }
    private func refresh(force: Bool) {
        if isCodex {
            store.refreshActive()
            if !store.busy && store.loaded && (force || store.profiles.contains(where: {
                guard let date = store.quotaDates[$0.id] else { return true }
                return Date().timeIntervalSince(date) > 60
            })) { store.refreshQuotas() }
        } else {
            let provider = products.selected
            Task { await usage.refresh(provider: provider, force: force) }
        }
    }
    private func open(_ id: String) {
        WorkspaceNavigation.shared.page = WorkspacePage(rawValue: id) ?? .usage
        openWindow(id: "workspace")
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension Notification.Name { static let chooseAccount = Notification.Name("chooseAccount") }
