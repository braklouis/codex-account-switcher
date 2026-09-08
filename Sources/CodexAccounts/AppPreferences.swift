import AppKit
import SwiftUI
import ServiceManagement
import UserNotifications
import SwitcherCore

@MainActor final class AppPreferences: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = AppPreferences()
    @Published var language = UserDefaults.standard.string(forKey: "appLanguage") ?? "zh-Hans" {
        didSet { UserDefaults.standard.set(language, forKey: "appLanguage") }
    }
    @Published var menuOnly: Bool {
        didSet { UserDefaults.standard.set(menuOnly, forKey: "menuOnly"); applyAppearance() }
    }
    @Published var reminders: Bool {
        didSet { UserDefaults.standard.set(reminders, forKey: "quotaReminders") }
    }
    @Published var menuQuotaStyle: String {
        didSet { UserDefaults.standard.set(menuQuotaStyle, forKey: "menuQuotaStyle") }
    }
    @Published var loginStatus = "尚未读取"
    @Published var loginEnabled = false
    @Published var notificationStatus = "尚未读取"
    @Published var message: String?
    private var history: [String: AlertThresholds] = [:]
    override init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: ["menuOnly": true, "quotaReminders": true])
        menuOnly = defaults.bool(forKey: "menuOnly")
        reminders = defaults.bool(forKey: "quotaReminders")
        menuQuotaStyle = defaults.string(forKey: "menuQuotaStyle") ?? "both"
        if let data = defaults.data(forKey: "quotaAlertHistory"),
           let value = try? JSONDecoder().decode([String: AlertThresholds].self, from: data) { history = value }
        super.init()
    }
    func start() {
        applyAppearance()
        UNUserNotificationCenter.current().delegate = self
        if !UserDefaults.standard.bool(forKey: "loginSetupAttempted") {
            UserDefaults.standard.set(true, forKey: "loginSetupAttempted")
            setLogin(true)
        }
        Task { await updateNotificationPermission(request: reminders) }
        refreshLoginStatus()
    }
    func applyAppearance() { NSApp.setActivationPolicy(menuOnly ? .accessory : .regular) }
    func refreshLoginStatus() {
        switch SMAppService.mainApp.status {
        case .enabled: loginEnabled = true; loginStatus = "已启用"
        case .requiresApproval: loginEnabled = true; loginStatus = "等待系统批准，请在登录项中允许"
        case .notRegistered: loginEnabled = false; loginStatus = "未启用"
        case .notFound: loginEnabled = false; loginStatus = "找不到应用，请放入应用程序目录后重试"
        @unknown default: loginEnabled = false; loginStatus = "状态未知"
        }
    }
    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch { message = "登录启动设置未完成：\(error.localizedDescription)" }
        refreshLoginStatus()
    }
    func updateNotificationPermission(request: Bool = false) async {
        let center = UNUserNotificationCenter.current()
        var settings = await center.notificationSettings()
        if request && settings.authorizationStatus == .notDetermined {
            do { _ = try await center.requestAuthorization(options: [.alert, .sound]) }
            catch { message = "无法申请通知权限，请在系统设置中允许。" }
            settings = await center.notificationSettings()
        }
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: notificationStatus = "已允许"
        case .denied: notificationStatus = "已被系统关闭，请在通知设置中允许"
        case .notDetermined: notificationStatus = "尚未允许"
        @unknown default: notificationStatus = "状态未知"
        }
    }
    func check(profile: Profile, quota: QuotaResponse) async {
        guard reminders else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        for (bucketID, bucket) in quota.buckets {
            for (slot, optionalWindow) in [("primary", bucket.primary), ("secondary", bucket.secondary)] {
                guard let window = optionalWindow, window.resetsAt == nil || window.resetsAt! > Date().timeIntervalSince1970 else { continue }
                let key = "\(profile.id.uuidString)|\(bucketID)|\(slot)|\(window.windowDurationMins ?? -1)"
                var state = history[key] ?? AlertThresholds()
                let threshold = state.evaluate(remaining: window.remaining, resetsAt: window.resetsAt)
                if let threshold {
                    let content = UNMutableNotificationContent()
                    content.title = L10n.isEnglish ? "Codex quota below \(threshold)%" : "Codex 额度低于 \(threshold)%"
                    let name = profile.name.components(separatedBy: "@").first ?? profile.name
                    content.body = L10n.isEnglish ? "\(name) · \(bucket.limitName ?? bucketID) · \(L10n.text(window.title)), \(Int(window.remaining))% remaining." : "\(name) · \(bucket.limitName ?? bucketID) · \(window.title)，剩余 \(Int(window.remaining))%。"
                    content.sound = .default
                    do {
                        try await center.add(UNNotificationRequest(identifier: key + "|\(window.resetsAt ?? 0)|\(threshold)", content: content, trigger: nil))
                    } catch { continue } // Retry next poll if the notification could not be scheduled.
                }
                history[key] = state
            }
        }
        if let data = try? JSONEncoder().encode(history) { UserDefaults.standard.set(data, forKey: "quotaAlertHistory") }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}

struct PreferencesView: View {
    @ObservedObject private var preferences = AppPreferences.shared
    var body: some View {
        Form {
            Section("Language / 语言") {
                Picker("Language / 语言", selection: $preferences.language) {
                    Text("简体中文").tag("zh-Hans")
                    Text("English").tag("en")
                }.pickerStyle(.segmented)
            }
            Section(L10n.text("外观")) {
                Toggle(L10n.text("仅在菜单栏显示，隐藏 Dock 图标"), isOn: $preferences.menuOnly)
                Text(L10n.text("关闭账号窗口后，工具仍会在菜单栏运行。")).font(.caption).foregroundStyle(.secondary)
            }
            Section(L10n.text("菜单栏额度")) {
                Picker(L10n.text("显示形式"), selection: $preferences.menuQuotaStyle) {
                    Text(L10n.text("百分比")).tag("numbers")
                    Text(L10n.text("进度条")).tag("bars")
                    Text(L10n.text("百分比＋进度条")).tag("both")
                }.pickerStyle(.segmented)
                Text(L10n.text("上行粉色显示短期额度，下行蓝色显示每周额度；仅显示当前账号的 Codex 主额度。未提供或读取失败时显示 —。"))
                    .font(.caption).foregroundStyle(.secondary)
                MenuQuotaPreview(style: preferences.menuQuotaStyle)
            }
            Section(L10n.text("启动")) {
                Toggle(L10n.text("登录 Mac 时自动启动"), isOn: Binding(get: { preferences.loginEnabled }, set: { preferences.setLogin($0) }))
                Text(L10n.text(preferences.loginStatus)).font(.caption).foregroundStyle(.secondary)
                Button(L10n.text("打开系统登录项设置")) { SMAppService.openSystemSettingsLoginItems() }
            }
            Section(L10n.text("额度提醒")) {
                Toggle(L10n.text("低额度时发送通知"), isOn: $preferences.reminders)
                    .onChange(of: preferences.reminders) { _, enabled in
                        Task { await preferences.updateNotificationPermission(request: enabled) }
                    }
                Text(L10n.text("剩余低于 75%、50%、25% 时提醒；每个账号、额度窗口和周期只提醒一次。首次读取已低于阈值时，合并为一条最低档提醒。"))
                    .font(.caption).foregroundStyle(.secondary)
                Text(L10n.text("每 5 分钟后台检查一次，休眠期间暂停。过期登录需重新登录才能继续读取。")).font(.caption).foregroundStyle(.secondary)
                Text((L10n.isEnglish ? "Notifications: " : "系统通知：") + L10n.text(preferences.notificationStatus)).font(.caption)
                Button(L10n.text("允许通知 / 查看设置")) {
                    Task {
                        await preferences.updateNotificationPermission(request: true)
                        if preferences.notificationStatus.contains("关闭") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                        }
                    }
                }
            }
            if let message = preferences.message { Text(L10n.text(message)).font(.caption).foregroundStyle(.orange) }
        }.formStyle(.grouped).frame(width: 490, height: 700)
            .onAppear { preferences.refreshLoginStatus(); Task { await preferences.updateNotificationPermission() } }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                preferences.refreshLoginStatus(); Task { await preferences.updateNotificationPermission() }
            }
    }
}
