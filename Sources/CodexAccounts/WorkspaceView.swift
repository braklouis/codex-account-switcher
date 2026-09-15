import SwiftUI

enum WorkspacePage: String, CaseIterable {
    case usage = "providers", accounts, products, preferences
    var title: String {
        switch self {
        case .usage: return L10n.isEnglish ? "Usage" : "额度"
        case .accounts: return L10n.isEnglish ? "Accounts" : "账号"
        case .products: return L10n.isEnglish ? "Products" : "产品"
        case .preferences: return L10n.isEnglish ? "Settings" : "设置"
        }
    }
}

@MainActor final class WorkspaceNavigation: ObservableObject {
    static let shared = WorkspaceNavigation()
    @Published var page: WorkspacePage = .usage
}

struct WorkspaceView: View {
    @ObservedObject var store: AccountStore
    @ObservedObject private var navigation = WorkspaceNavigation.shared
    @ObservedObject private var language = AppPreferences.shared

    var body: some View {
        TabView(selection: $navigation.page) {
            ProviderDashboard(showProducts: { navigation.page = .products })
                .tabItem { Label(WorkspacePage.usage.title, systemImage: "chart.bar") }.tag(WorkspacePage.usage)
            AccountsView(store: store)
                .tabItem { Label(WorkspacePage.accounts.title, systemImage: "person.crop.circle") }.tag(WorkspacePage.accounts)
            ProductSettingsView()
                .tabItem { Label(WorkspacePage.products.title, systemImage: "square.grid.2x2") }.tag(WorkspacePage.products)
            PreferencesView()
                .tabItem { Label(WorkspacePage.preferences.title, systemImage: "gearshape") }.tag(WorkspacePage.preferences)
        }
        .padding(12)
        .frame(minWidth: 680, minHeight: 600)
    }
}
