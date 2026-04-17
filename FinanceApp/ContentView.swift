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

    init() {
        UITabBar.appearance().isHidden = true
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                DashboardView(selectedTab: $selectedTab)
                    .tag(AppRootTab.dashboard)

                if featureTransactions {
                    TransactionsView()
                        .tag(AppRootTab.transactions)
                }

                if featureAnalytics {
                    ChartsView(selectedTab: $selectedTab)
                        .tag(AppRootTab.analytics)
                }

                AccountsView()
                    .tag(AppRootTab.accounts)

                SettingsView()
                    .tag(AppRootTab.settings)
            }
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 80)
            }

            FloatingTabBar(
                selected: $selectedTab,
                showTransactions: featureTransactions,
                showAnalytics: featureAnalytics
            )
            .padding(.horizontal, 32)
            .padding(.bottom, 8)
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

// MARK: - Floating Tab Bar

private struct FloatingTabBar: View {
    @Binding var selected: AppRootTab
    let showTransactions: Bool
    let showAnalytics: Bool

    private struct TabItem: Identifiable {
        let id: AppRootTab
        let icon: String
    }

    private var items: [TabItem] {
        var result: [TabItem] = [.init(id: .dashboard, icon: "house.fill")]
        if showTransactions { result.append(.init(id: .transactions, icon: "list.bullet.rectangle.fill")) }
        if showAnalytics    { result.append(.init(id: .analytics, icon: "chart.bar.fill")) }
        result.append(.init(id: .accounts, icon: "creditcard.fill"))
        result.append(.init(id: .settings, icon: "gearshape.fill"))
        return result
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(items) { item in
                let isSelected = selected == item.id
                Button {
                    HapticManager.impact(.light)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selected = item.id
                    }
                } label: {
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(isSelected ? AppTheme.primaryAccent : Color.clear)
                                .frame(width: 38, height: 38)
                            Image(systemName: item.icon)
                                .font(.system(size: 18, weight: isSelected ? .bold : .medium))
                                .foregroundStyle(isSelected ? Color.white : .primary.opacity(0.54))
                        }

                        Capsule()
                            .fill(isSelected ? AppTheme.sectionAccent : Color.clear)
                            .frame(width: isSelected ? 18 : 6, height: 4)
                    }
                    .contentShape(Rectangle())
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .animation(.spring(response: 0.28, dampingFraction: 0.68), value: selected)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tabLabel(for: item.id))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(AppTheme.elevatedSurface.opacity(ThemeStore.shared.palette.isDark ? 0.92 : 0.96))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(AppTheme.outline.opacity(0.72), lineWidth: 1)
                )
                .shadow(color: AppTheme.shadowStrong, radius: 18, x: 0, y: 8)
        )
    }

    private func tabLabel(for tab: AppRootTab) -> String {
        switch tab {
        case .dashboard:
            return String(localized: "Dashboard")
        case .transactions:
            return String(localized: "Transactions")
        case .analytics:
            return String(localized: "Analytics")
        case .accounts:
            return String(localized: "Accounts")
        case .settings:
            return String(localized: "Settings")
        }
    }
}
