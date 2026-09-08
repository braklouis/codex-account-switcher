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
        MenuBarExtra("Codex Accounts", systemImage: "arrow.left.arrow.right.circle") {
            MenuContent(store: store)
        }
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
        if let peer = peers.first { peer.activate(options: [.activateAllWindows]); NSApp.terminate(nil) }
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
    @ObservedObject var store: AccountStore
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text(store.activeEmail ?? "尚未读取当前账号")
        Divider()
        ForEach(store.profiles) { profile in
            Button {
                openWindow(id: "accounts")
                NSApp.activate(ignoringOtherApps: true)
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    NotificationCenter.default.post(name: .chooseAccount, object: profile.id)
                }
            } label: {
                Label(profile.name, systemImage: profile.snapshot?.identity == store.activeIdentity ? "checkmark.circle.fill" : "person.crop.circle")
            }.disabled(store.busy)
        }
        Divider()
        Button("管理账号…") { openWindow(id: "accounts"); NSApp.activate(ignoringOtherApps: true) }
        Button("刷新额度") { store.refreshQuotas() }.disabled(store.busy || store.profiles.isEmpty)
        Divider()
        Button("退出 Codex Accounts") { NSApp.terminate(nil) }.disabled(store.busy)
    }
}

extension Notification.Name { static let chooseAccount = Notification.Name("chooseAccount") }
