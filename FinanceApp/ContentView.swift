import SwiftUI

struct ContentView: View {
    @ObservedObject private var themeStore = ThemeStore.shared
    @State private var selectedTab: AppRootTab = .dashboard
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showOnboarding = false
    @State private var tabBarOffset: CGFloat = 60
    @State private var tabBarOpacity: Double = 0

    @AppStorage("feature.transactions") private var featureTransactions = true
    @AppStorage("feature.analytics")    private var featureAnalytics = true

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView(selectedTab: $selectedTab)
                .tag(AppRootTab.dashboard)
                .tabItem {
                    Label(String(localized: "Dashboard"), systemImage: "house")
                }

            if featureTransactions {
                TransactionsView()
                    .tag(AppRootTab.transactions)
                    .tabItem {
                        Label(String(localized: "Transactions"), systemImage: "list.bullet.rectangle")
                    }
            }

            if featureAnalytics {
                ChartsView(selectedTab: $selectedTab)
                    .tag(AppRootTab.analytics)
                    .tabItem {
                        Label(String(localized: "Analytics"), systemImage: "chart.bar.fill")
                    }
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
        .id(themeStore.selectedTheme)
        .offset(y: tabBarOffset)
        .opacity(tabBarOpacity)
        .fullScreenCover(isPresented: $showOnboarding, onDismiss: revealApp) {
            OnboardingView(isPresented: $showOnboarding)
        }
        .onAppear {
            if !hasCompletedOnboarding {
                showOnboarding = true
            } else {
                revealApp()
            }
        }
        .onChange(of: showOnboarding) { _, visible in
            if !visible { hasCompletedOnboarding = true }
        }
        .onChange(of: featureTransactions) { _, on in
            if !on && selectedTab == .transactions { selectedTab = .dashboard }
        }
        .onChange(of: featureAnalytics) { _, on in
            if !on && selectedTab == .analytics { selectedTab = .dashboard }
        }
    }

    private func revealApp() {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.78).delay(0.05)) {
            tabBarOffset = 0
            tabBarOpacity = 1
        }
    }
}
