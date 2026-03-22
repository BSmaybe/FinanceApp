import SwiftUI

struct ContentView: View {
    @ObservedObject private var themeStore = ThemeStore.shared
    @State private var selectedTab: AppRootTab = .dashboard

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView(selectedTab: $selectedTab)
                .tag(AppRootTab.dashboard)
                .tabItem {
                    Label(String(localized: "Dashboard"), systemImage: "house")
                }

            TransactionsView()
                .tag(AppRootTab.transactions)
                .tabItem {
                    Label(String(localized: "Transactions"), systemImage: "list.bullet.rectangle")
                }

            ChartsView(selectedTab: $selectedTab)
                .tag(AppRootTab.analytics)
                .tabItem {
                    Label(String(localized: "Analytics"), systemImage: "chart.bar.fill")
                }

            AccountsView()
                .tag(AppRootTab.accounts)
                .tabItem {
                    Label(String(localized: "Accounts"), systemImage: "creditcard")
                }

            SettingsView()
                .tag(AppRootTab.settings)
                .tabItem {
                    Label(String(localized: "Settings"), systemImage: "gear")
                }
        }
        .tint(AppTheme.primaryAccent)
        .preferredColorScheme(themeStore.palette.isDark ? .dark : .light)
        .id(themeStore.selectedTheme) // rebuilds view tree on theme change
    }
}
