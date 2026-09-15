import AppKit
import SwiftUI

struct ProductDefinition: Identifiable, Hashable {
    let id: String
    let name: String
    let symbol: String
    let loginHintZH: String
    let loginHintEN: String
    let docsURL: URL
}

@MainActor
final class ProductPreferences: ObservableObject {
    static let shared = ProductPreferences()
    private let defaults: UserDefaults

    static let catalog: [ProductDefinition] = [
        ProductDefinition(
            id: "codex", name: "Codex", symbol: "sparkles",
            loginHintZH: "使用 CodexBar 已有的 Codex 登录（OAuth / Codex CLI 会话）。",
            loginHintEN: "Uses the existing CodexBar Codex login (OAuth or Codex CLI session).",
            docsURL: URL(string: "https://github.com/steipete/CodexBar/blob/main/docs/codex.md")!
        ),
        ProductDefinition(
            id: "grok", name: "Grok", symbol: "bolt.horizontal.circle",
            loginHintZH: "使用 Grok CLI 的登录会话；CodexBar 也支持已配置的 SuperGrok OAuth 或浏览器会话。",
            loginHintEN: "Uses the Grok CLI login; CodexBar also supports configured SuperGrok OAuth or a browser session.",
            docsURL: URL(string: "https://github.com/steipete/CodexBar/blob/main/docs/grok.md")!
        ),
        ProductDefinition(
            id: "kimi", name: "Kimi Code", symbol: "moon.stars",
            loginHintZH: "使用 Kimi Code CLI、API key，或 CodexBar 可读取的浏览器会话；这不是 Kimi Open Platform。",
            loginHintEN: "Uses Kimi Code CLI, an API key, or a browser session readable by CodexBar; this is separate from Kimi Open Platform.",
            docsURL: URL(string: "https://github.com/steipete/CodexBar/blob/main/docs/kimi.md")!
        ),
        ProductDefinition(
            id: "openrouter", name: "OpenRouter", symbol: "square.stack.3d.up",
            loginHintZH: "在 CodexBar 中配置 OpenRouter API key；这里不会读取或保存密钥。",
            loginHintEN: "Configure an OpenRouter API key in CodexBar; this app never reads or stores the key.",
            docsURL: URL(string: "https://github.com/steipete/CodexBar/blob/main/docs/openrouter.md")!
        ),
        ProductDefinition(
            id: "claude", name: "Claude", symbol: "bubble.left.and.bubble.right",
            loginHintZH: "使用 Claude web 会话、Claude CLI，或 CodexBar 支持的 OAuth 来源。",
            loginHintEN: "Uses a Claude web session, Claude CLI, or an OAuth source supported by CodexBar.",
            docsURL: URL(string: "https://github.com/steipete/CodexBar/blob/main/docs/claude.md")!
        ),
        ProductDefinition(
            id: "cursor", name: "Cursor", symbol: "cursorarrow.rays",
            loginHintZH: "使用 Cursor 本地登录状态和 CodexBar 支持的 cursor.com 会话；切换登录在 Cursor/CodexBar 中完成。",
            loginHintEN: "Uses Cursor's local login state and the cursor.com session supported by CodexBar; change accounts in Cursor/CodexBar.",
            docsURL: URL(string: "https://github.com/steipete/CodexBar/blob/main/docs/cursor.md")!
        ),
        ProductDefinition(
            id: "gemini", name: "Gemini", symbol: "diamond",
            loginHintZH: "使用 CodexBar 支持的 Gemini CLI 或 Google 会话配置。",
            loginHintEN: "Uses the Gemini CLI or Google session configuration supported by CodexBar.",
            docsURL: URL(string: "https://github.com/steipete/CodexBar/blob/main/docs/gemini.md")!
        ),
        ProductDefinition(
            id: "qwen-cloud", name: "Qwen Cloud", symbol: "cloud",
            loginHintZH: "Qwen Cloud 目前使用浏览器会话；请先在 Qwen Cloud 控制台登录，再由 CodexBar 自动读取。",
            loginHintEN: "Qwen Cloud currently uses a browser session; sign in to its console first, then let CodexBar read it.",
            docsURL: URL(string: "https://github.com/steipete/CodexBar/blob/main/docs/qwen-cloud.md")!
        ),
        ProductDefinition(
            id: "zai", name: "GLM", symbol: "globe.asia.australia",
            loginHintZH: "GLM（z.ai / BigModel）使用 CodexBar 中配置的 API token；不使用浏览器 Cookie。",
            loginHintEN: "GLM (z.ai / BigModel) uses an API token configured in CodexBar; it does not use browser cookies.",
            docsURL: URL(string: "https://github.com/steipete/CodexBar/blob/main/docs/zai.md")!
        ),
        ProductDefinition(
            id: "deepseek", name: "DeepSeek", symbol: "brain.head.profile",
            loginHintZH: "DeepSeek 可使用 API key；详细用量还需要 CodexBar 可读取的 DeepSeek Platform 会话。",
            loginHintEN: "DeepSeek can use an API key; detailed usage additionally needs a DeepSeek Platform session readable by CodexBar.",
            docsURL: URL(string: "https://github.com/steipete/CodexBar/blob/main/docs/deepseek.md")!
        )
    ]

    @Published var selected: String {
        didSet {
            guard enabled.contains(selected) else {
                selected = enabled.first ?? Self.catalog[0].id
                return
            }
            defaults.set(selected, forKey: Self.selectedKey)
        }
    }

    @Published var enabled: [String] {
        didSet {
            let normalized = Self.normalizedEnabled(enabled)
            if normalized != enabled { enabled = normalized; return }
            defaults.set(enabled, forKey: Self.enabledKey)
            if !enabled.contains(selected) { selected = enabled[0] }
        }
    }

    private static let selectedKey = "providerSelectedProduct"
    private static let enabledKey = "providerEnabledProducts"
    private static let defaultEnabled = ["codex", "grok", "kimi", "openrouter"]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedEnabled = defaults.stringArray(forKey: Self.enabledKey) ?? Self.defaultEnabled
        let normalized = Self.normalizedEnabled(storedEnabled)
        let storedSelected = defaults.string(forKey: Self.selectedKey) ?? Self.defaultEnabled[0]
        enabled = normalized
        selected = normalized.contains(storedSelected) ? storedSelected : normalized[0]
    }

    func setEnabled(id: String, enabled isEnabled: Bool) {
        guard Self.catalog.contains(where: { $0.id == id }) else { return }
        if isEnabled {
            if !enabled.contains(id) { enabled.append(id) }
        } else {
            guard enabled.count > 1 else { return }
            enabled.removeAll { $0 == id }
            if selected == id { selected = enabled[0] }
        }
    }

    func definition(for id: String) -> ProductDefinition? { Self.catalog.first { $0.id == id } }

    private static func normalizedEnabled(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        let valid = ids.filter { id in
            catalog.contains { $0.id == id } && seen.insert(id).inserted
        }
        return valid.isEmpty ? defaultEnabled : valid
    }
}

struct ProductSettingsView: View {
    @ObservedObject private var preferences = ProductPreferences.shared
    @State private var codexBarMissing = false

    var body: some View {
        Form {
            Section {
                Text(L10n.isEnglish ? "Choose the products shown in TokenDeck." : "选择要在 TokenDeck 中显示的产品。")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Picker(
                    L10n.isEnglish ? "Selected product" : "当前产品",
                    selection: $preferences.selected
                ) {
                    ForEach(preferences.enabled, id: \.self) { id in
                        if let product = preferences.definition(for: id) {
                            Text(product.name).tag(product.id)
                        }
                    }
                }
            } header: {
                Text(L10n.isEnglish ? "AI products" : "AI 产品")
            }

            Section {
                ForEach(ProductPreferences.catalog) { product in
                    Toggle(isOn: Binding(
                        get: { preferences.enabled.contains(product.id) },
                        set: { preferences.setEnabled(id: product.id, enabled: $0) }
                    )) {
                        Label {
                            Text(product.name)
                        } icon: {
                            ProviderBrandIcon(provider: product.id)
                                .frame(width: 18, height: 18)
                        }
                    }
                    .disabled(preferences.enabled.contains(product.id) && preferences.enabled.count == 1)
                }
            } header: {
                Text(L10n.isEnglish ? "Enabled products" : "启用的产品")
            } footer: {
                Text(L10n.isEnglish ? "At least one product must stay enabled." : "至少要保留一个启用的产品。")
            }

            selectedDetails

            if codexBarMissing {
                Section {
                    Label(
                        L10n.isEnglish ? "CodexBar was not found in /Applications." : "在 /Applications 中找不到 CodexBar。",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var selectedDetails: some View {
        if let product = preferences.definition(for: preferences.selected) {
            Section {
                Text(L10n.isEnglish ? product.loginHintEN : product.loginHintZH)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    let appURL = URL(fileURLWithPath: "/Applications/CodexBar.app")
                    codexBarMissing = !FileManager.default.fileExists(atPath: appURL.path)
                    NSWorkspace.shared.open(appURL)
                } label: {
                    Label(L10n.isEnglish ? "Open CodexBar" : "打开 CodexBar", systemImage: "arrow.up.forward.app")
                }

                Text(L10n.isEnglish ? "In CodexBar: Settings → Providers → \(product.name). Existing logins are reused; TokenDeck does not copy your secrets." : "在 CodexBar 中进入：设置 → 提供商 → \(product.name)。已有登录可直接复用，TokenDeck 不复制密钥。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                HStack {
                    Label(L10n.isEnglish ? "Login for \(product.name)" : "\(product.name) 登录配置", systemImage: "person.crop.circle.badge.checkmark")
                    Spacer()
                    Link(destination: product.docsURL) {
                        Label("CodexBar docs", systemImage: "book.pages")
                    }
                }
            }
        }
    }
}
