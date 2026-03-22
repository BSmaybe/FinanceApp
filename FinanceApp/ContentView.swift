import SwiftUI

struct ContentView: View {
    @ObservedObject private var themeStore = ThemeStore.shared

    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label(String(localized: "Dashboard"), systemImage: "house")
                }

            TransactionsView()
                .tabItem {
                    Label(String(localized: "Transactions"), systemImage: "list.bullet.rectangle")
                }

            ChartsView()
                .tabItem {
                    Label(String(localized: "Analytics"), systemImage: "chart.bar.fill")
                }

            AccountsView()
                .tabItem {
                    Label(String(localized: "Accounts"), systemImage: "creditcard")
                }

            SettingsView()
                .tabItem {
                    Label(String(localized: "Settings"), systemImage: "gear")
                }
        }
        .tint(AppTheme.primaryAccent)
        .preferredColorScheme(themeStore.palette.isDark ? .dark : .light)
        .id(themeStore.selectedTheme) // rebuilds view tree on theme change
    }
}
