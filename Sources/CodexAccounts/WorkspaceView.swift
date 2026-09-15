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
        VStack(spacing: 0) {
            HStack(spacing: 20) {
                HStack(spacing: 8) {
                    AppBrandIcon().frame(width: 25, height: 25)
                    Text("TokenDeck").font(.headline)
                }
                Spacer()
                Picker("", selection: $navigation.page) {
                    ForEach(WorkspacePage.allCases, id: \.self) { page in
                        Text(page.title).tag(page)
                    }
                }.pickerStyle(.segmented).labelsHidden().frame(width: 370)
            }.padding(.horizontal, 20).padding(.vertical, 14)
            Divider()
            Group {
                switch navigation.page {
                case .usage: ProviderDashboard(showProducts: { navigation.page = .products })
                case .accounts: AccountsView(store: store)
                case .products: ProductSettingsView()
                case .preferences: PreferencesView()
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 720, minHeight: 680)
        .tint(Color(red: 0.10, green: 0.52, blue: 0.41))
    }
}
