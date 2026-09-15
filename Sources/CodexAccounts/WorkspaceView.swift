import SwiftUI

enum WorkspacePage: String, CaseIterable {
    case usage = "providers", products, preferences
    var symbol: String {
        switch self {
        case .usage: return "chart.bar.fill"
        case .products: return "square.grid.2x2.fill"
        case .preferences: return "gearshape.fill"
        }
    }
    var title: String {
        switch self {
        case .usage: return L10n.isEnglish ? "Overview" : "概览"
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
        NavigationSplitView {
            List {
                ForEach(WorkspacePage.allCases, id: \.self) { page in
                    Button { navigation.page = page } label: {
                        HStack(spacing: 9) {
                            Image(systemName: page.symbol)
                                .symbolRenderingMode(.monochrome)
                                .foregroundStyle(navigation.page == page ? Color(nsColor: .windowBackgroundColor) : Color.primary)
                                .frame(width: 18)
                            Text(page.title)
                        }
                            .font(.body.weight(navigation.page == page ? .semibold : .regular))
                            .foregroundStyle(navigation.page == page ? Color(nsColor: .windowBackgroundColor) : Color.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(RoundedRectangle(cornerRadius: 8).fill(navigation.page == page ? Color.primary : Color.clear).padding(.horizontal, 6))
                    .accessibilityAddTraits(navigation.page == page ? .isSelected : [])
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("TokenDeck")
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            Group {
                switch navigation.page {
                case .usage:
                    ProviderDashboard(showProducts: { navigation.page = .products }, codexAccounts: AnyView(AccountsView(store: store)))
                case .products: ProductSettingsView()
                case .preferences: PreferencesView()
                }
            }
            .navigationTitle(navigation.page.title)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .tint(.primary)
        .accentColor(Color.primary)
        .frame(minWidth: 740, minHeight: 600)
    }
}
