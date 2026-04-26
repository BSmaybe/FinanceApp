import SwiftUI
import SwiftData
import UserNotifications
import VisionKit
import AVFoundation

struct DashboardView: View {
    @Binding var selectedTab: AppRootTab

    @Query private var accounts: [Account]
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query private var categories: [Category]
    @Query private var budgets: [Budget]
    @Query(sort: \Goal.createdDate, order: .reverse) private var goals: [Goal]
    @AppStorage("budgetRollover") private var rolloverEnabled = false

    @Query(filter: #Predicate<Subscription> { $0.isActive == true })
    private var activeSubscriptions: [Subscription]
    @Query private var debts: [Debt]
    @Query private var recurringTransactions: [RecurringTransaction]

    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("budgetNotificationsEnabled") private var budgetNotificationsEnabled = true
    @AppStorage("subscriptionRemindersEnabled") private var subscriptionRemindersEnabled = true
    @AppStorage("debtRemindersEnabled") private var debtRemindersEnabled = true
    @AppStorage("liveActivityEnabled") private var liveActivityEnabled = false
    @AppStorage("dash.showOverview") private var showOverview = true
    @AppStorage("dash.showVitals") private var showVitals = true
    @AppStorage("dash.showAccounts") private var showAccounts = true
    @AppStorage("dash.showQuickActions") private var showQuickActions = true
    @AppStorage("dash.showThisMonth") private var showThisMonth = true
    @AppStorage("dash.showDebts") private var showDebts = true
    @AppStorage("dash.showCommitments") private var showCommitments = true
    @AppStorage("dash.showWeeklyBudget") private var showWeeklyBudget = true
    @AppStorage("dash.showRecentActivity") private var showRecentActivity = true

    @AppStorage("feature.budgets")       private var featureBudgets = true
    @AppStorage("feature.goals")         private var featureGoals = true
    @AppStorage("feature.debts")         private var featureDebts = true
    @AppStorage("feature.subscriptions") private var featureSubscriptions = true
    @AppStorage("unlockedAchievements")  private var unlockedAchievementsData = ""
    @AppStorage("dash.showHeroCard")     private var showHeroCard = true
    @AppStorage("dash.expandedSection")  private var expandedSectionRaw = ""

    @State private var monthOffset: Int = 0
    @State private var newlyUnlockedAchievement: Achievement?

    @State private var settingBudgetForCategory: Category?
    @State private var quickAddCategory: Category?
    @State private var showingQuickAdd = false
    @State private var showingGoals = false
    @State private var showingSubscriptions = false
    @State private var showingDebts = false
    @State private var showingCommitmentsHub = false
    @State private var showingCalendar = false
    @State private var showingBudgetManager = false
    @State private var showingDashboardSettings = false
    @State private var showingCaptureScanner = false
    @State private var scannerErrorMessage: String?
    @State private var quickAddCapturePayload: PendingCapturePayload?

    // B4: Swipe hint (shown once)
    @AppStorage("dash.swipeHintShown") private var swipeHintShown = false
    @State private var showSwipeHint = false

    private struct DashboardStats {
        let netWorthByAccount: [UUID: Decimal]
        let monthlyIncome: Decimal
        let monthlyExpense: Decimal
        let spentByCategory: [UUID: Decimal]
        let prevSpentByCategory: [UUID: Decimal]
    }

    private struct BudgetRisk {
        let category: Category
        let spent: Decimal
        let limit: Decimal
        let ratio: Double
        let isOverBudget: Bool
    }

    private enum DashboardSection: String, CaseIterable {
        case accounts
        case vitals
        case primaryActions
        case coach
        case thisMonth
        case commitments
        case weeklyBudget
        case recentActivity
    }

    private var expandedSection: DashboardSection? {
        get { DashboardSection(rawValue: expandedSectionRaw) }
        set { expandedSectionRaw = newValue?.rawValue ?? "" }
    }

    private var activeRecurringTransactionsList: [RecurringTransaction] {
        recurringTransactions
            .filter(\.isActive)
            .sorted { $0.startDate < $1.startDate }
    }

    private struct FocusStripRow<Content: View>: View {
        let section: DashboardSection
        let title: String
        let summary: String
        let icon: String
        let accessibilityId: String
        @Binding var expandedSectionRaw: String
        @ViewBuilder let content: () -> Content

        private var isExpanded: Bool {
            expandedSectionRaw == section.rawValue
        }

        var body: some View {
            VStack(spacing: 0) {
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        expandedSectionRaw = isExpanded ? "" : section.rawValue
                    }
                    HapticManager.impact(.light)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: icon)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.primaryAccent)
                            .frame(width: 30, height: 30)
                            .background(AppTheme.primaryAccent.opacity(0.12))
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            Text(title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            if !isExpanded {
                                Text(summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isExpanded {
                    Divider()
                        .padding(.horizontal, 14)
                    content()
                        .padding(12)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AppTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(AppTheme.outline.opacity(0.4), lineWidth: 0.5)
                    )
            )
            .accessibilityIdentifier(accessibilityId)
        }
    }

    private var currentComponents: (year: Int, month: Int, day: Int) {
        let base = Date()
        let shifted = Calendar.current.date(byAdding: .month, value: monthOffset, to: base) ?? base
        let c = Calendar.current.dateComponents([.year, .month, .day], from: shifted)
        // For past months, use last day of that month; for current use today
        if monthOffset < 0 {
            let lastDay = Calendar.current.range(of: .day, in: .month, for: shifted)?.count ?? 28
            return (year: c.year ?? 2025, month: c.month ?? 1, day: lastDay)
        }
        return (year: c.year ?? 2025, month: c.month ?? 1, day: c.day ?? 1)
    }

    private func previousMonthComponents(from current: (year: Int, month: Int, day: Int)) -> (year: Int, month: Int) {
        var comps = DateComponents()
        comps.year = current.year
        comps.month = current.month - 1
        comps.day = 1
        if let prevDate = Calendar.current.date(from: comps) {
            let resolved = Calendar.current.dateComponents([.year, .month], from: prevDate)
            return (year: resolved.year ?? current.year, month: resolved.month ?? 12)
        }
        return (year: current.year - 1, month: 12)
    }

    private func stats(
        current: (year: Int, month: Int, day: Int),
        previousMonth: (year: Int, month: Int)
    ) -> DashboardStats {
        let cal = Calendar.current
        let now = Date()

        var balances: [UUID: Decimal] = Dictionary(
            uniqueKeysWithValues: accounts.map { ($0.id, $0.openingBalance) }
        )
        var income = Decimal.zero
        var expense = Decimal.zero
        var spentByCat: [UUID: Decimal] = [:]
        var prevSpentByCat: [UUID: Decimal] = [:]

        for txn in transactions {
            guard BalanceCalculator.isPosted(txn, asOf: now) else { continue }

            switch txn.type {
            case .income:
                balances[txn.accountId, default: .zero] += txn.amount
            case .expense:
                balances[txn.accountId, default: .zero] -= txn.amount
            case .transfer:
                balances[txn.accountId, default: .zero] -= txn.amount
                if let toId = txn.toAccountId {
                    balances[toId, default: .zero] += txn.amount
                }
            }

            let c = cal.dateComponents([.year, .month], from: txn.date)
            if c.year == current.year && c.month == current.month {
                switch txn.type {
                case .income:
                    income += txn.amount
                case .expense:
                    expense += txn.amount
                    if let cid = txn.categoryId {
                        spentByCat[cid, default: .zero] += txn.amount
                    }
                case .transfer:
                    break
                }
            }

            if c.year == previousMonth.year && c.month == previousMonth.month && txn.type == .expense {
                if let cid = txn.categoryId {
                    prevSpentByCat[cid, default: .zero] += txn.amount
                }
            }
        }

        return DashboardStats(
            netWorthByAccount: balances,
            monthlyIncome: income,
            monthlyExpense: expense,
            spentByCategory: spentByCat,
            prevSpentByCategory: prevSpentByCat
        )
    }

    private func netWorth(from stats: DashboardStats) -> Decimal {
        accounts.reduce(Decimal.zero) { $0 + stats.netWorthByAccount[$1.id, default: .zero] }
    }

    private var expenseCategories: [Category] {
        categories.filter { $0.type == .expense }
    }

    private var activeGoals: [Goal] {
        goals.filter { $0.targetAmount > 0 && $0.progress < 1 }
    }

    private var activeDebts: [Debt] {
        debts.filter { $0.remainingAmount > 0 }
    }

    private var recentTransactions: [Transaction] {
        Array(transactions.filter { BalanceCalculator.isPosted($0) }.prefix(5))
    }

    private var heroStats: HeroStats {
        GamificationEngine.compute(transactions: transactions, goals: goals, debts: debts)
    }

    private func budget(for category: Category, month: Int, year: Int) -> Budget? {
        budgets.first {
            $0.categoryId == category.id &&
            $0.month == month &&
            $0.year == year
        }
    }

    private func effectiveLimit(
        for category: Category,
        month: Int,
        year: Int,
        previousMonth: (year: Int, month: Int),
        previousSpentByCategory: [UUID: Decimal]
    ) -> Decimal {
        guard let currentBudget = budget(for: category, month: month, year: year) else { return .zero }
        let base = currentBudget.limitAmount
        guard rolloverEnabled else { return base }

        let previousBudget = budgets.first {
            $0.categoryId == category.id &&
            $0.month == previousMonth.month &&
            $0.year == previousMonth.year
        }
        guard let previousBudget else { return base }

        let previousSpent = previousSpentByCategory[category.id, default: .zero]
        let unused = max(.zero, previousBudget.limitAmount - previousSpent)
        return base + unused
    }

    private var currentWeeklyBudgetItems: [WeeklyBudgetItem] {
        WeeklyBudgetCalculator.items(
            referenceDate: Date(),
            categories: categories,
            budgets: budgets,
            transactions: transactions,
            rolloverEnabled: rolloverEnabled
        )
    }

    private var hasVisibleDashboardSections: Bool {
        [
            showOverview,
            showVitals,
            showAccounts,
            showQuickActions,
            showHeroCard,
            showThisMonth,
            showCommitments,
            showWeeklyBudget,
            showRecentActivity
        ].contains(true)
    }

    private var hasVisibleFocusStripSections: Bool {
        [
            showAccounts,
            showVitals,
            showQuickActions,
            showHeroCard,
            showThisMonth,
            showCommitments,
            showWeeklyBudget,
            showRecentActivity
        ].contains(true)
    }

    var body: some View {
        let current = currentComponents
        let previousMonth = previousMonthComponents(from: current)
        let dashboardStats = stats(current: current, previousMonth: previousMonth)
        let expenseCategoriesList = expenseCategories
        let recentTransactionsList = recentTransactions
        let categoryById = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        let netWorthValue = netWorth(from: dashboardStats)
        let freeToSpendValue = freeToSpend(
            stats: dashboardStats,
            expenseCategories: expenseCategoriesList,
            currentMonth: current.month,
            currentYear: current.year,
            previousMonth: previousMonth
        )
        let financialVitals = FinancialVitalsEngine.compute(
            accounts: accounts,
            transactions: transactions,
            categories: categories,
            budgets: budgets,
            debts: debts,
            subscriptions: activeSubscriptions,
            month: current.month,
            year: current.year
        )
        let heroInsightText = heroInsight(
            income: dashboardStats.monthlyIncome,
            expense: dashboardStats.monthlyExpense,
            spentByCategory: dashboardStats.spentByCategory,
            current: current
        )
        let budgetPressures = budgetPressureList(
            stats: dashboardStats,
            expenseCategories: expenseCategoriesList,
            current: current,
            previousMonth: previousMonth
        )
        let weeklyBudgetItems = currentWeeklyBudgetItems

        return NavigationStack {
            ZStack {
                AppTheme.canvas.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        if !showOverview {
                            dashboardControlBar
                                .accessibilityIdentifier("dashboard.controlBar")
                        }

                        if hasVisibleDashboardSections {
                            if showOverview {
                                heroReferenceSection(
                                    netWorth: netWorthValue,
                                    freeToSpend: freeToSpendValue,
                                    monthlyIncome: dashboardStats.monthlyIncome,
                                    monthlyExpense: dashboardStats.monthlyExpense,
                                    insight: heroInsightText
                                )
                                .accessibilityIdentifier("dashboard.hero.section")
                            }

                            if hasVisibleFocusStripSections {
                                focusStripSections(
                                    balances: dashboardStats.netWorthByAccount,
                                    budgetPressures: budgetPressures,
                                    weeklyBudgetItems: weeklyBudgetItems,
                                    vitals: financialVitals,
                                    recentTransactions: recentTransactionsList,
                                    categoryById: categoryById
                                )
                            } else {
                                emptyDashboardState
                                    .accessibilityIdentifier("dashboard.emptyState")
                            }
                        } else {
                            emptyDashboardState
                                .accessibilityIdentifier("dashboard.emptyState")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 32)
                }
                // Achievement unlock toast
                if let achievement = newlyUnlockedAchievement {
                    AchievementToastView(achievement: achievement) {
                        newlyUnlockedAchievement = nil
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(10)
                }
            }
            .accessibilityIdentifier("dashboard.screen")
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingDashboardSettings) {
                NavigationStack {
                    DashboardSettingsView(showsDoneButton: true)
                }
                .presentationCornerRadius(24)
                .presentationDragIndicator(.visible)
            }
            .sheet(item: $settingBudgetForCategory) { category in
                SetBudgetView(
                    category: category,
                    month: current.month,
                    year: current.year,
                    existing: budget(for: category, month: current.month, year: current.year)
                )
                .presentationCornerRadius(24)
                .presentationDragIndicator(.visible)
            }
            .sheet(item: $quickAddCategory) { category in
                QuickAddView(prefillCategoryId: category.id)
                    .presentationCornerRadius(24)
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingQuickAdd) {
                QuickAddView(capturePayload: quickAddCapturePayload)
                    .presentationCornerRadius(24)
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingCaptureScanner) {
                DashboardCaptureScannerView(
                    onCapture: { payload in
                        showingCaptureScanner = false
                        quickAddCapturePayload = payload
                        showingQuickAdd = true
                    },
                    onCancel: {
                        showingCaptureScanner = false
                    },
                    onError: { message in
                        showingCaptureScanner = false
                        scannerErrorMessage = message
                    }
                )
                .presentationCornerRadius(24)
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingBudgetManager) {
                BudgetManagerView(month: current.month, year: current.year)
                    .presentationCornerRadius(24)
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingGoals) {
                GoalsView()
                    .presentationCornerRadius(24)
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingSubscriptions) {
                SubscriptionsView()
                    .presentationCornerRadius(24)
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingDebts) {
                DebtsView()
                    .presentationCornerRadius(24)
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingCommitmentsHub) {
                CommitmentsHubView()
                    .presentationCornerRadius(24)
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingCalendar) {
                CashCalendarView()
                    .presentationCornerRadius(24)
                    .presentationDragIndicator(.visible)
            }
            .alert(String(localized: "Scanner unavailable"), isPresented: Binding(
                get: { scannerErrorMessage != nil },
                set: { newValue in
                    if !newValue { scannerErrorMessage = nil }
                }
            )) {
                Button(String(localized: "OK"), role: .cancel) { scannerErrorMessage = nil }
            } message: {
                Text(scannerErrorMessage ?? "")
            }
            .onAppear {
                // B4: show swipe hint once
                if !swipeHintShown {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        withAnimation(.easeIn(duration: 0.3)) { showSwipeHint = true }
                        swipeHintShown = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            withAnimation(.easeOut(duration: 0.4)) { showSwipeHint = false }
                        }
                    }
                }
                WidgetDataProvider.save(
                    netWorth: netWorthValue,
                    monthlyIncome: dashboardStats.monthlyIncome,
                    monthlyExpense: dashboardStats.monthlyExpense
                )
                rescheduleNotifications(
                    spentByCategory: dashboardStats.spentByCategory,
                    categoryById: categoryById
                )
                if liveActivityEnabled {
                    startLiveActivityIfNeeded(
                        expenseCategories: expenseCategoriesList,
                        current: current,
                        previousMonth: previousMonth,
                        dashStats: dashboardStats
                    )
                }
                expandedSectionRaw = autoExpandedSectionRaw(
                    budgetPressures: budgetPressures,
                    weeklyBudgetItems: weeklyBudgetItems,
                    vitals: financialVitals,
                    recentTransactions: recentTransactionsList
                )
                checkAchievements()
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                let current2 = currentComponents
                let prev2 = previousMonthComponents(from: current2)
                let s2 = stats(current: current2, previousMonth: prev2)
                let catById2 = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
                rescheduleNotifications(spentByCategory: s2.spentByCategory, categoryById: catById2)
                if liveActivityEnabled {
                    updateLiveActivity(
                        expenseCategories: expenseCategories,
                        current: current2,
                        previousMonth: prev2,
                        dashStats: s2
                    )
                }
            }
            .onChange(of: transactions.count) { _, _ in
                let current2 = currentComponents
                let prev2 = previousMonthComponents(from: current2)
                let s2 = stats(current: current2, previousMonth: prev2)
                let catById2 = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
                rescheduleNotifications(spentByCategory: s2.spentByCategory, categoryById: catById2)
                if liveActivityEnabled {
                    updateLiveActivity(
                        expenseCategories: expenseCategories,
                        current: current2,
                        previousMonth: prev2,
                        dashStats: s2
                    )
                }
                checkAchievements()
            }
            .onChange(of: showAccounts) { _, _ in
                expandedSectionRaw = normalizedExpandedSectionRaw()
            }
            .onChange(of: showVitals) { _, _ in
                expandedSectionRaw = normalizedExpandedSectionRaw()
            }
            .onChange(of: showQuickActions) { _, _ in
                expandedSectionRaw = normalizedExpandedSectionRaw()
            }
            .onChange(of: showHeroCard) { _, _ in
                expandedSectionRaw = normalizedExpandedSectionRaw()
            }
            .onChange(of: showThisMonth) { _, _ in
                expandedSectionRaw = normalizedExpandedSectionRaw()
            }
            .onChange(of: showCommitments) { _, _ in
                expandedSectionRaw = normalizedExpandedSectionRaw()
            }
            .onChange(of: showWeeklyBudget) { _, _ in
                expandedSectionRaw = normalizedExpandedSectionRaw()
            }
            .onChange(of: showRecentActivity) { _, _ in
                expandedSectionRaw = normalizedExpandedSectionRaw()
            }
        }
    }

    // MARK: - Reference Redesign Sections

    private func heroReferenceSection(
        netWorth: Decimal,
        freeToSpend: Decimal,
        monthlyIncome: Decimal,
        monthlyExpense: Decimal,
        insight: String
    ) -> some View {
        let isCurrentMonth = monthOffset == 0
        let monthLabel = currentMonthLabel(from: currentComponents)
        let monthNet = monthlyIncome - monthlyExpense
        let dateLabel = isCurrentMonth
            ? Date().formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
            : monthLabel

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(greetingText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    HStack(spacing: 8) {
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { monthOffset -= 1 }
                            HapticManager.impact(.light)
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)

                        Text(dateLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button {
                            guard monthOffset < 0 else { return }
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { monthOffset += 1 }
                            HapticManager.impact(.light)
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(isCurrentMonth ? .clear : .secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(isCurrentMonth)
                    }
                }
                Spacer()
                Button {
                    HapticManager.impact(.light)
                    showingDashboardSettings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 34, height: 34)
                        .background(AppTheme.surfaceMuted)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("dashboard.openLayoutSettings")
            }

            HeroMetricCard(
                title: String(localized: "Available funds"),
                value: CurrencyFormatter.string(from: netWorth),
                supportingTitle: String(localized: "Month net"),
                supportingValue: CurrencyFormatter.string(from: monthNet),
                note: insight,
                badgeText: monthLabel
            )

            HStack(spacing: 8) {
                focusMetricPill(
                    title: String(localized: "Free to spend"),
                    value: NumberAbbreviator.string(from: freeToSpend),
                    tint: AppTheme.primaryAccent
                )
                focusMetricPill(
                    title: String(localized: "Income"),
                    value: NumberAbbreviator.string(from: monthlyIncome),
                    tint: AppTheme.success
                )
                focusMetricPill(
                    title: String(localized: "Expense"),
                    value: NumberAbbreviator.string(from: monthlyExpense),
                    tint: AppTheme.danger
                )
            }
        }
        .gesture(
            DragGesture(minimumDistance: 30).onEnded { val in
                if val.translation.width < -30 {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { monthOffset -= 1 }
                    HapticManager.impact(.light)
                } else if val.translation.width > 30, monthOffset < 0 {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { monthOffset += 1 }
                    HapticManager.impact(.light)
                }
            }
        )
    }

    private var dashboardControlBar: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Dashboard"))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(currentMonthLabel(from: currentComponents))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                HapticManager.impact(.light)
                showingDashboardSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 34, height: 34)
                    .background(AppTheme.surfaceMuted)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("dashboard.openLayoutSettings")
        }
        .padding(.horizontal, 4)
    }

    private var visibleFocusSections: [DashboardSection] {
        var sections: [DashboardSection] = []
        if showAccounts { sections.append(.accounts) }
        if showVitals { sections.append(.vitals) }
        if showQuickActions { sections.append(.primaryActions) }
        if showHeroCard { sections.append(.coach) }
        if showThisMonth { sections.append(.thisMonth) }
        if showCommitments { sections.append(.commitments) }
        if showWeeklyBudget { sections.append(.weeklyBudget) }
        if showRecentActivity { sections.append(.recentActivity) }
        return sections
    }

    private func focusStripSections(
        balances: [UUID: Decimal],
        budgetPressures: [BudgetRisk],
        weeklyBudgetItems: [WeeklyBudgetItem],
        vitals: FinancialVitals,
        recentTransactions: [Transaction],
        categoryById: [UUID: Category]
    ) -> some View {
        VStack(spacing: 12) {
            if showAccounts {
                focusStripSection(
                    section: .accounts,
                    title: String(localized: "Accounts"),
                    summary: accounts.isEmpty ? String(localized: "No Accounts") : accountsSummary(balances: balances),
                    icon: "creditcard.and.123",
                    accessibilityId: "dashboard.accounts.section"
                ) {
                    accountsFocusContent(balances: balances)
                }
            }

            if showVitals {
                focusStripSection(
                    section: .vitals,
                    title: String(localized: "Financial Vitals"),
                    summary: vitalsSummary(vitals: vitals),
                    icon: "waveform.path.ecg",
                    accessibilityId: "dashboard.vitals.section"
                ) {
                    financialVitalsFocusContent(vitals: vitals)
                }
            }

            if showQuickActions {
                focusStripSection(
                    section: .primaryActions,
                    title: String(localized: "Primary Actions"),
                    summary: "\(String(localized: "Quick Add")) · \(String(localized: "Budgets")) · \(String(localized: "Calendar"))",
                    icon: "square.grid.2x2.fill",
                    accessibilityId: "dashboard.primaryActions.section"
                ) {
                    actionRailContent
                }
            }

            if showHeroCard {
                focusStripSection(
                    section: .coach,
                    title: String(localized: "Coach & Progress"),
                    summary: heroStats.title,
                    icon: "sparkles",
                    accessibilityId: "dashboard.hero.card"
                ) {
                    HeroProfileCardView(stats: heroStats) { cta in
                        handleCoachCTA(cta)
                    }
                }
            }

            if showThisMonth {
                focusStripSection(
                    section: .thisMonth,
                    title: String(localized: "This Month"),
                    summary: budgetsSummary(budgetPressures: budgetPressures),
                    icon: "calendar",
                    accessibilityId: "dashboard.thisMonth.section"
                ) {
                    thisMonthFocusContent(budgetPressures: budgetPressures)
                }
            }

            if showCommitments {
                focusStripSection(
                    section: .commitments,
                    title: String(localized: "Commitments"),
                    summary: upcomingSummary,
                    icon: "tray.full",
                    accessibilityId: "dashboard.commitments.section"
                ) {
                    commitmentsFocusContent
                }
            }

            if showWeeklyBudget {
                focusStripSection(
                    section: .weeklyBudget,
                    title: String(localized: "Weekly Budget"),
                    summary: weeklyBudgetSummary(items: weeklyBudgetItems),
                    icon: "calendar.badge.clock",
                    accessibilityId: "dashboard.weeklyBudget.section"
                ) {
                    weeklyBudgetFocusContent(items: weeklyBudgetItems)
                }
            }

            if showRecentActivity {
                focusStripSection(
                    section: .recentActivity,
                    title: String(localized: "Recent Activity"),
                    summary: activitySummary(recentTransactions: recentTransactions, categoryById: categoryById),
                    icon: "clock.arrow.circlepath",
                    accessibilityId: "dashboard.recentActivity.section"
                ) {
                    recentActivityContent(
                        recentTransactions: recentTransactions,
                        categoryById: categoryById
                    )
                }
            }
        }
    }

    private func focusStripSection<Content: View>(
        section: DashboardSection,
        title: String,
        summary: String,
        icon: String,
        accessibilityId: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        FocusStripRow(
            section: section,
            title: title,
            summary: summary,
            icon: icon,
            accessibilityId: accessibilityId,
            expandedSectionRaw: $expandedSectionRaw,
            content: content
        )
    }

    private func normalizedExpandedSectionRaw() -> String {
        let visible = visibleFocusSections
        guard !visible.isEmpty else {
            return ""
        }
        if let expandedSection, visible.contains(expandedSection) {
            return expandedSection.rawValue
        }
        return ""
    }

    private func autoExpandedSectionRaw(
        budgetPressures: [BudgetRisk],
        weeklyBudgetItems: [WeeklyBudgetItem],
        vitals: FinancialVitals,
        recentTransactions: [Transaction]
    ) -> String {
        let visible = visibleFocusSections
        guard !visible.isEmpty else {
            return ""
        }
        if let expandedSection, visible.contains(expandedSection) {
            return expandedSection.rawValue
        }
        return autoFocusSection(
            budgetPressures: budgetPressures,
            weeklyBudgetItems: weeklyBudgetItems,
            vitals: vitals,
            recentTransactions: recentTransactions,
            visibleSections: visible
        ).rawValue
    }

    private func autoFocusSection(
        budgetPressures: [BudgetRisk],
        weeklyBudgetItems: [WeeklyBudgetItem],
        vitals: FinancialVitals,
        recentTransactions: [Transaction],
        visibleSections: [DashboardSection]
    ) -> DashboardSection {
        let hasWeeklyBudgetRisk = weeklyBudgetItems.contains { $0.overrun > 0 || $0.ratio >= 0.8 }
        if hasWeeklyBudgetRisk, showWeeklyBudget, visibleSections.contains(.weeklyBudget) {
            return .weeklyBudget
        }
        let hasBudgetRisk = budgetPressures.contains { $0.isOverBudget || $0.ratio >= 0.8 }
        if hasBudgetRisk, showThisMonth, visibleSections.contains(.thisMonth) {
            return .thisMonth
        }
        if vitals.dueSoonCount > 0, showCommitments, visibleSections.contains(.commitments) {
            return .commitments
        }
        if showRecentActivity, visibleSections.contains(.recentActivity) {
            return .recentActivity
        }
        if recentTransactions.isEmpty, visibleSections.contains(.primaryActions) {
            return .primaryActions
        }
        return visibleSections.first ?? .accounts
    }

    private func vitalsSummary(vitals: FinancialVitals) -> String {
        let readiness = FinancialVitalMetric.readiness.stateLabel(for: vitals.readiness)
        let reserve = FinancialVitalMetric.reserve.stateLabel(for: vitals.reserve)
        let pressure = FinancialVitalMetric.pressure.stateLabel(for: vitals.pressure)
        let higher = String(localized: "Higher is better")
        let lower = String(localized: "Lower is better")
        return "\(String(localized: "Readiness")) \(readiness) (\(higher)) · \(String(localized: "Reserve")) \(reserve) (\(higher)) · \(String(localized: "Pressure")) \(pressure) (\(lower))"
    }

    private func financialVitalsSection(vitals: FinancialVitals) -> some View {
        SectionShell(
            title: String(localized: "Financial Vitals"),
            subtitle: String(localized: "Higher readiness and reserve are better. Lower pressure is better."),
            trailing: {
                Button(String(localized: "Open Analytics")) {
                    selectedTab = .analytics
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.primaryAccent)
                .buttonStyle(.plain)
            }
        ) {
            financialVitalsFocusContent(vitals: vitals)
        }
    }

    private func financialVitalsFocusContent(vitals: FinancialVitals) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                vitalsScoreCard(
                    metric: .readiness,
                    score: vitals.readiness,
                    icon: "figure.stand"
                )
                vitalsScoreCard(
                    metric: .pressure,
                    score: vitals.pressure,
                    icon: "waveform.path.ecg"
                )
                vitalsScoreCard(
                    metric: .reserve,
                    score: vitals.reserve,
                    icon: "shield.lefthalf.filled"
                )
            }

            HStack(spacing: 10) {
                vitalsDetailCard(
                    title: String(localized: "Runway"),
                    value: String(format: String(localized: "%d days"), vitals.runwayDays),
                    subtitle: String(
                        format: String(localized: "Budget stability %d%%"),
                        vitals.budgetStability
                    ),
                    icon: "calendar.badge.clock"
                )
                vitalsDetailCard(
                    title: String(localized: "Left to pay"),
                    value: CurrencyFormatter.string(from: vitals.leftToPayNext7Days),
                    subtitle: String(
                        format: String(localized: "%d items in 7 days"),
                        vitals.dueSoonCount
                    ),
                    icon: "creditcard.and.123"
                )
            }
        }
    }

    private func vitalsScoreCard(
        metric: FinancialVitalMetric,
        score: Int,
        icon: String
    ) -> some View {
        let zone = metric.zone(for: score)
        let tint = vitalsTint(for: zone)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.14))
                    .clipShape(Circle())
                Spacer()
                Text(metric.stateLabel(for: score))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(tint.opacity(0.12))
                    .clipShape(Capsule())
            }

            Text(metric.title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            Text("\(score)")
                .font(.system(size: 30, weight: .black, design: .rounded).monospacedDigit())
                .foregroundStyle(.primary)
                .contentTransition(.numericText())

            ProgressView(value: Double(score), total: 100)
                .tint(tint)

            Text(metric.directionLabel)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(AppTheme.outline.opacity(0.4), lineWidth: 0.5)
        )
    }

    private func vitalsDetailCard(
        title: String,
        value: String,
        subtitle: String,
        icon: String
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.primaryAccent)
                .frame(width: 34, height: 34)
                .background(AppTheme.primaryAccent.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppTheme.surfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func vitalsTint(for zone: FinancialVitalsZone) -> Color {
        switch zone {
        case .green:
            return AppTheme.success
        case .yellow:
            return AppTheme.warning
        case .red:
            return AppTheme.danger
        }
    }

    private var emptyDashboardState: some View {
        SectionShell(
            title: String(localized: "Everything is hidden"),
            subtitle: String(localized: "Turn sections back on or restore the full dashboard layout.")
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Text(String(localized: "Choose only the sections you want to see every day."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button(String(localized: "Dashboard Settings")) {
                        showingDashboardSettings = true
                    }
                    .buttonStyle(.bordered)
                    .tint(AppTheme.primaryAccent)

                    Button(String(localized: "Show all")) {
                        restoreDashboardSections()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.primaryAccent)
                }
            }
        }
    }

    private func restoreDashboardSections() {
        showOverview = true
        showVitals = true
        showAccounts = true
        showQuickActions = true
        showThisMonth = true
        showDebts = true
        showCommitments = true
        showWeeklyBudget = true
        showRecentActivity = true
        showHeroCard = true
    }

    private var actionRailSection: some View {
        SectionShell(
            title: String(localized: "Primary Actions"),
            subtitle: String(localized: "Move quickly through daily money tasks")
        ) {
            actionRailContent
        }
    }

    private var actionRailContent: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ActionTile(
                title: String(localized: "Quick Add"),
                subtitle: String(localized: "Capture income or expense"),
                systemImage: "plus.circle.fill",
                tint: AppTheme.primaryAccent
            ) {
                quickAddCapturePayload = nil
                showingQuickAdd = true
            }

            ActionTile(
                title: String(localized: "Budgets"),
                subtitle: String(localized: "Review limits and pressure"),
                systemImage: "gauge.with.needle.fill",
                tint: AppTheme.warning
            ) {
                showingBudgetManager = true
            }

            ActionTile(
                title: String(localized: "Calendar"),
                subtitle: String(localized: "Review actual and planned cash days"),
                systemImage: "calendar.badge.clock",
                tint: AppTheme.success
            ) {
                showingCalendar = true
            }

            ActionTile(
                title: String(localized: "Scan"),
                subtitle: String(localized: "Receipt or code capture"),
                systemImage: "qrcode.viewfinder",
                tint: AppTheme.info
            ) {
                showingCaptureScanner = true
            }
        }
    }

    private func latestTransactionReferenceSection(
        recentTransactions: [Transaction],
        categoryById: [UUID: Category]
    ) -> some View {
        SectionShell(
            title: String(localized: "Recent Activity"),
            subtitle: String(localized: "Latest posted transactions and fast access to the full journal."),
            trailing: {
                Button(String(localized: "See all")) {
                    selectedTab = .transactions
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.primaryAccent)
                .buttonStyle(.plain)
                .accessibilityIdentifier("dashboard.recentActivity.openTransactions")
            }
        ) {
            if recentTransactions.isEmpty {
                Button {
                    showingQuickAdd = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(AppTheme.success)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(String(localized: "No recent activity yet"))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(String(localized: "Tap to add your first transaction"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .background(AppTheme.surfaceMuted)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(recentTransactions.prefix(3).enumerated()), id: \.element.id) { _, txn in
                        latestTransactionReferenceRow(txn, categoryById: categoryById)
                    }
                }
            }
        }
    }

    private func latestTransactionReferenceRow(
        _ txn: Transaction,
        categoryById: [UUID: Category]
    ) -> some View {
        let category = txn.categoryId.flatMap { categoryById[$0] }
        let tint: Color = {
            switch txn.type {
            case .income: return AppTheme.success
            case .expense: return AppTheme.danger
            case .transfer: return AppTheme.info
            }
        }()
        let sign = txn.type == .income ? "+" : (txn.type == .expense ? "-" : "")
        let title: String = {
            if !txn.note.isEmpty { return txn.note }
            if let category { return category.name }
            return txn.type.localizedName
        }()
        let subtitle: String = {
            if let category {
                return category.name
            }
            return txn.type.localizedName
        }()

        return HStack(spacing: 12) {
            Image(systemName: category?.iconName ?? "dollarsign.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(tint.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text("\(sign) \(CurrencyFormatter.string(from: txn.amount))")
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(tint)
                .lineLimit(1)
        }
        .padding(14)
        .background(AppTheme.surfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func insightsReferenceSection(budgetPressures: [BudgetRisk]) -> some View {
        return SectionShell(
            title: String(localized: "This Month"),
            subtitle: String(localized: "Signals worth reviewing before the month slips."),
            trailing: {
                Button(String(localized: "See all")) {
                    selectedTab = .analytics
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.primaryAccent)
                .buttonStyle(.plain)
            }
        ) {
            thisMonthFocusContent(budgetPressures: budgetPressures)
        }
    }

    private func thisMonthFocusContent(budgetPressures: [BudgetRisk]) -> some View {
        let current = currentComponents
        let previousMonth = previousMonthComponents(from: current)
        let dashboardStats = stats(current: current, previousMonth: previousMonth)
        let expenseCategoriesList = expenseCategories
        let freeToSpendValue = freeToSpend(
            stats: dashboardStats,
            expenseCategories: expenseCategoriesList,
            currentMonth: current.month,
            currentYear: current.year,
            previousMonth: previousMonth
        )
        let allowanceValue = dailyAllowance(freeToSpend: freeToSpendValue, current: current)
        let monthNet = dashboardStats.monthlyIncome - dashboardStats.monthlyExpense
        let topRisk = budgetPressures.first
        let topRiskPercent = Int((topRisk?.ratio ?? 0) * 100)
        let monthlyBills = CommitmentsPlanner.monthlyOutflow(
            debts: activeDebts,
            subscriptions: activeSubscriptions,
            recurringTransactions: activeRecurringTransactionsList
        )

        return VStack(spacing: 12) {
            HStack(spacing: 8) {
                focusMetricPill(
                    title: String(localized: "Income"),
                    value: NumberAbbreviator.string(from: dashboardStats.monthlyIncome),
                    tint: AppTheme.success
                )
                focusMetricPill(
                    title: String(localized: "Expense"),
                    value: NumberAbbreviator.string(from: dashboardStats.monthlyExpense),
                    tint: AppTheme.danger
                )
                focusMetricPill(
                    title: String(localized: "Net"),
                    value: NumberAbbreviator.string(from: monthNet),
                    tint: monthNet >= 0 ? AppTheme.success : AppTheme.danger
                )
                focusMetricPill(
                    title: String(localized: "Daily Allowance"),
                    value: NumberAbbreviator.string(from: allowanceValue),
                    tint: AppTheme.info
                )
            }

            Button {
                showingBudgetManager = true
            } label: {
                InsightCard(
                    title: String(localized: "Budget pressure"),
                    value: topRisk == nil ? String(localized: "No budgets yet") : "\(topRiskPercent)%",
                    message: topRisk == nil
                        ? String(localized: "Create budgets to track monthly pressure")
                        : String(
                            format: String(localized: "You reached %lld%% of %@ budget"),
                            Int64(max(0, topRiskPercent)),
                            topRisk?.category.name ?? ""
                        ),
                    systemImage: topRisk?.category.iconName ?? "gauge.with.needle.fill",
                    tint: topRisk?.isOverBudget == true ? AppTheme.danger : AppTheme.warning
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("dashboard.thisMonth.openBudgets")

            Button {
                showingCommitmentsHub = true
            } label: {
                InsightCard(
                    title: String(localized: "Upcoming bills"),
                    value: CurrencyFormatter.string(from: monthlyBills),
                    message: String(
                        format: String(localized: "%lld active bills this month"),
                        Int64(activeSubscriptions.count + activeDebts.count + activeRecurringTransactionsList.filter { $0.type == .expense }.count)
                    ),
                    systemImage: "calendar.badge.clock",
                    tint: AppTheme.info
                )
            }
            .buttonStyle(.plain)

            Button {
                selectedTab = .analytics
            } label: {
                InsightCard(
                    title: String(localized: "Planning"),
                    value: "\(activeGoals.count)",
                    message: activeGoals.isEmpty
                        ? String(localized: "Create your first goal")
                        : String(
                            format: String(localized: "%lld goals in progress"),
                            Int64(activeGoals.count)
                        ),
                    systemImage: "target",
                    tint: AppTheme.success
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func focusMetricPill(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(AppTheme.surfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var commitmentsCompactSection: some View {
        return SectionShell(
            title: String(localized: "Commitments"),
            subtitle: String(localized: "Review upcoming obligations and progress.")
        ) {
            commitmentsFocusContent
        }
    }

    private var commitmentsFocusContent: some View {
        VStack(spacing: 12) {
            commitmentMiniRow
            upcomingPaymentsContent
        }
    }

    private func weeklyBudgetSummary(items: [WeeklyBudgetItem]) -> String {
        guard !items.isEmpty else { return String(localized: "No weekly budgets yet") }

        let totalOverrun = items.reduce(Decimal.zero) { $0 + $1.overrun }
        if totalOverrun > 0 {
            return String(format: String(localized: "Over by %@"), CurrencyFormatter.string(from: totalOverrun))
        }

        let totalRemaining = items.reduce(Decimal.zero) { $0 + $1.remaining }
        return String(format: String(localized: "Weekly left %@"), CurrencyFormatter.string(from: totalRemaining))
    }

    @ViewBuilder
    private func weeklyBudgetFocusContent(items: [WeeklyBudgetItem]) -> some View {
        if items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "No weekly budgets yet"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(String(localized: "Create monthly category limits to track overspend pressure."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(String(localized: "Set limits")) {
                    showingBudgetManager = true
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.primaryAccent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        } else {
            let totalLimit = items.reduce(Decimal.zero) { $0 + $1.weeklyLimit }
            let totalSpent = items.reduce(Decimal.zero) { $0 + $1.weeklySpent }
            let totalRemaining = items.reduce(Decimal.zero) { $0 + $1.remaining }
            let totalOverrun = items.reduce(Decimal.zero) { $0 + $1.overrun }
            let topItems = Array(items.prefix(4))

            VStack(spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(
                            String(
                                format: String(localized: "Spent %@ of %@"),
                                CurrencyFormatter.string(from: totalSpent),
                                CurrencyFormatter.string(from: totalLimit)
                            )
                        )
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                        Text(weekRangeText(start: items[0].weekStart, end: items[0].weekEnd))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 12)

                    Text(
                        totalOverrun > 0
                            ? String(format: String(localized: "Over by %@"), CurrencyFormatter.string(from: totalOverrun))
                            : String(format: String(localized: "Weekly left %@"), CurrencyFormatter.string(from: totalRemaining))
                    )
                    .font(.caption.weight(.bold))
                    .foregroundStyle(totalOverrun > 0 ? AppTheme.danger : AppTheme.success)
                    .multilineTextAlignment(.trailing)
                }

                VStack(spacing: 10) {
                    ForEach(topItems) { item in
                        weeklyBudgetRow(item)
                    }
                }

                Button(String(localized: "Open Analytics")) {
                    selectedTab = .analytics
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.primaryAccent)
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private func weeklyBudgetRow(_ item: WeeklyBudgetItem) -> some View {
        let categoryColor = Color(hex: item.colorHex)
        let statusColor = weeklyBudgetStatusColor(for: item)
        let progress = min(max(item.ratio, 0), 1)

        return Button {
            guard let category = categories.first(where: { $0.id == item.categoryId }) else { return }
            quickAddCategory = category
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.iconName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(categoryColor)
                    .frame(width: 34, height: 34)
                    .background(categoryColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.categoryName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        Text("\(CurrencyFormatter.string(from: item.weeklySpent)) / \(CurrencyFormatter.string(from: item.weeklyLimit))")
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    ProgressView(value: progress)
                        .tint(statusColor)

                    HStack(spacing: 8) {
                        Text(
                            item.overrun > 0
                                ? String(format: String(localized: "Over by %@"), CurrencyFormatter.string(from: item.overrun))
                                : String(format: String(localized: "Left %@"), CurrencyFormatter.string(from: item.remaining))
                        )
                        .font(.caption)
                        .foregroundStyle(statusColor)
                        .lineLimit(1)

                        Spacer(minLength: 8)

                        Text(item.overrun > 0 ? String(localized: "Over") : "\(Int((item.ratio * 100).rounded()))%")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(statusColor)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(statusColor.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(12)
            .background(AppTheme.surfaceMuted)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func weeklyBudgetStatusColor(for item: WeeklyBudgetItem) -> Color {
        if item.overrun > 0 {
            return AppTheme.danger
        }
        if item.ratio >= 0.8 {
            return AppTheme.warning
        }
        return AppTheme.success
    }

    private func weekRangeText(start: Date, end: Date) -> String {
        let formatter = DateIntervalFormatter()
        formatter.locale = Locale.current
        formatter.dateTemplate = Calendar.current.isDate(start, equalTo: end, toGranularity: .year) ? "MMM d" : "MMM d, yyyy"
        return formatter.string(from: start, to: end)
    }

    private var commitmentMiniRow: some View {
        let subscriptionTotal = activeSubscriptions.reduce(Decimal.zero) { $0 + $1.amount }
        let debtTotal = activeDebts.reduce(Decimal.zero) { $0 + $1.remainingAmount }
        let recurringTotal = activeRecurringTransactionsList
            .filter { $0.type == .expense }
            .reduce(Decimal.zero) { total, recurring in
                total + CommitmentsPlanner.monthlyEquivalent(amount: recurring.amount, frequency: recurring.frequency)
            }

        return HStack(spacing: 10) {
            if featureSubscriptions {
                commitmentMiniCard(
                    title: String(localized: "Subscriptions"),
                    value: CurrencyFormatter.string(from: subscriptionTotal),
                    subtitle: "\(activeSubscriptions.count)",
                    icon: "repeat",
                    tint: AppTheme.sectionAccent
                ) {
                    showingSubscriptions = true
                }
            }

            if featureDebts && showDebts {
                commitmentMiniCard(
                    title: String(localized: "Debts"),
                    value: CurrencyFormatter.string(from: debtTotal),
                    subtitle: "\(activeDebts.count)",
                    icon: "creditcard",
                    tint: AppTheme.warning
                ) {
                    showingDebts = true
                }
            }

            if !activeRecurringTransactionsList.isEmpty {
                commitmentMiniCard(
                    title: String(localized: "Recurring"),
                    value: CurrencyFormatter.string(from: recurringTotal),
                    subtitle: "\(activeRecurringTransactionsList.count)",
                    icon: "arrow.clockwise",
                    tint: AppTheme.info
                ) {
                    showingCommitmentsHub = true
                }
            }
        }
    }

    private func commitmentMiniCard(
        title: String,
        value: String,
        subtitle: String,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(tint.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Text(value)
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(AppTheme.outline.opacity(0.5), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func heroTrendValues(income: Decimal, expense: Decimal) -> [Double] {
        let window = 14
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -(window - 1), to: todayStart) else {
            return [0, 0.1, 0.2, 0.15, 0.3, 0.4, 0.9]
        }

        var deltaByDay: [Date: Decimal] = [:]
        for txn in transactions {
            guard BalanceCalculator.isPosted(txn) else { continue }
            let day = calendar.startOfDay(for: txn.date)
            guard day >= start && day <= todayStart else { continue }
            switch txn.type {
            case .income:
                deltaByDay[day, default: .zero] += txn.amount
            case .expense:
                deltaByDay[day, default: .zero] -= txn.amount
            case .transfer:
                break
            }
        }

        var points: [Double] = []
        var running = 0.0
        for offset in 0..<window {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            running += NSDecimalNumber(decimal: deltaByDay[day, default: .zero]).doubleValue
            points.append(running)
        }

        if points.allSatisfy({ abs($0) < .ulpOfOne }) {
            let fallback = NSDecimalNumber(decimal: income - expense).doubleValue
            return [0.2, 0.24, 0.22, 0.27, 0.29, 0.45, 0.63, 0.78, 0.84, 0.8, 0.93, 1.05, 1.12, 1.18 + fallback / 1_000]
        }
        return points
    }

    // MARK: - Hero (floating, no card — gradient is the background)

    private var greetingText: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 6..<12:  return String(localized: "Good morning 👋")
        case 12..<17: return String(localized: "Good afternoon 👋")
        case 17..<22: return String(localized: "Good evening 👋")
        default:      return String(localized: "Good night 🌙")
        }
    }

    // B1: Smart financial insight for hero strip
    private func heroInsight(
        income: Decimal,
        expense: Decimal,
        spentByCategory: [UUID: Decimal],
        current: (year: Int, month: Int, day: Int)
    ) -> String {
        let cal = Calendar.current
        // Priority 1: today's spending
        let todayExpense = transactions
            .filter { cal.isDateInToday($0.date) && $0.type == .expense }
            .reduce(Decimal.zero) { $0 + $1.amount }
        if todayExpense > 0 {
            return String(format: String(localized: "Today −%@"), CurrencyFormatter.string(from: todayExpense))
        }
        // Priority 2: upcoming subscriptions within 7 days
        let now = Date()
        let in7 = cal.date(byAdding: .day, value: 7, to: now) ?? now
        let upcomingCount = activeSubscriptions.filter { $0.nextBillingDate >= now && $0.nextBillingDate <= in7 }.count
        if upcomingCount > 0 {
            return String(format: String(localized: "%lld payments this week"), Int64(upcomingCount))
        }
        // Priority 3: budget health this month
        if featureBudgets && monthOffset == 0 {
            let thisMonthBudgets = budgets.filter { $0.month == current.month && $0.year == current.year }
            if !thisMonthBudgets.isEmpty {
                let totalLimit = thisMonthBudgets.reduce(Decimal.zero) { $0 + $1.limitAmount }
                let totalSpent = spentByCategory.values.reduce(Decimal.zero, +)
                if totalLimit > 0 {
                    let pct = Int(((totalSpent / totalLimit * 100) as NSDecimalNumber).doubleValue.rounded())
                    let healthy = max(0, 100 - pct)
                    return String(format: String(localized: "Budget %lld%% healthy"), Int64(healthy))
                }
            }
        }
        // Priority 4: savings rate if income exists
        if income > 0 && expense < income {
            let savedPct = Int((((income - expense) / income * 100) as NSDecimalNumber).doubleValue.rounded())
            return String(format: String(localized: "Saved %lld%% this month"), Int64(savedPct))
        }
        return String(localized: "No transactions today · add one!")
    }

    // B3: Empty state when user has no accounts yet
    private var emptyAccountsCard: some View {
        SectionShell(
            title: String(localized: "Accounts"),
            subtitle: String(localized: "Where the money lives")
        ) {
            VStack(spacing: 12) {
                Image(systemName: "creditcard.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(AppTheme.info)
                Text(String(localized: "Add your first account"))
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(String(localized: "Add your first account to start seeing balances, runway and reserve."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button(String(localized: "Open Accounts")) {
                    selectedTab = .accounts
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.primaryAccent)
                .controlSize(.regular)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }

    private func heroFloatingSection(
        netWorth: Decimal,
        income: Decimal,
        expense: Decimal,
        savingsRate: Decimal,
        insight: String
    ) -> some View {
        let isCurrentMonth = monthOffset == 0
        let monthLabel = currentMonthLabel(from: currentComponents)
        let savingsPct = Int((savingsRate * 100 as NSDecimalNumber).doubleValue.rounded())

        return VStack(alignment: .leading, spacing: 0) {
            // Top row: date + settings
            HStack {
                Text(Date().formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(AppTheme.heroCardLabel.opacity(0.55))
                Spacer()
                Button {
                    HapticManager.impact(.light)
                    showingDashboardSettings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.heroCardLabel)
                        .frame(width: 30, height: 30)
                        .background(.white.opacity(0.12))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("dashboard.openLayoutSettings")
            }

            Spacer().frame(height: 8)

            // Net worth
            Text(String(localized: "Net Worth"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppTheme.heroCardLabel.opacity(0.6))
                .textCase(.uppercase)
                .tracking(0.6)
            Text(NumberAbbreviator.string(from: netWorth))
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.heroCardTitle)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .padding(.top, 1)

            // B2: Monthly change indicator
            let monthlyChange = income - expense
            if monthlyChange != 0 {
                let isPositive = monthlyChange > 0
                HStack(spacing: 3) {
                    Image(systemName: isPositive ? "arrow.up" : "arrow.down")
                        .font(.system(size: 9, weight: .bold))
                    Text("\(CurrencyFormatter.string(from: monthlyChange > 0 ? monthlyChange : -monthlyChange)) \(String(localized: "this month"))")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(isPositive ? AppTheme.success.opacity(0.85) : AppTheme.danger.opacity(0.85))
                .padding(.top, 1)
            }

            // B1: Smart financial insight instead of random quote
            Text(insight)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.heroCardLabel.opacity(0.65))
                .lineLimit(1)
                .padding(.top, 4)

            Spacer().frame(height: 10)

            // Month nav + income/expense/savings
            HStack(spacing: 6) {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { monthOffset -= 1 }
                    HapticManager.impact(.light)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(AppTheme.heroCardLabel)
                        .frame(width: 22, height: 22)
                        .background(.white.opacity(0.12))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Text(monthLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.heroCardLabel)

                // B4: one-time swipe hint
                if showSwipeHint {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 8, weight: .bold))
                        Text(String(localized: "swipe"))
                            .font(.system(size: 9))
                    }
                    .foregroundStyle(AppTheme.heroCardLabel.opacity(0.45))
                    .transition(.opacity)
                }

                Button {
                    guard monthOffset < 0 else { return }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { monthOffset += 1 }
                    HapticManager.impact(.light)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(isCurrentMonth ? .clear : AppTheme.heroCardLabel)
                        .frame(width: 22, height: 22)
                        .background(isCurrentMonth ? .clear : .white.opacity(0.12))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(isCurrentMonth)

                Spacer()

                heroChip(icon: "arrow.down", value: NumberAbbreviator.string(from: income), color: AppTheme.success)
                heroChip(icon: "arrow.up",   value: NumberAbbreviator.string(from: expense), color: AppTheme.danger)
                if income > 0 {
                    heroChip(icon: "chart.pie", value: "\(savingsPct)%", color: .white.opacity(0.9))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 16)
        .gesture(
            DragGesture(minimumDistance: 30).onEnded { val in
                if val.translation.width < -30 {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { monthOffset -= 1 }
                    HapticManager.impact(.light)
                } else if val.translation.width > 30, monthOffset < 0 {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { monthOffset += 1 }
                    HapticManager.impact(.light)
                }
            }
        )
    }

    // MARK: - Accounts Scroll

    private func accountsSummary(balances: [UUID: Decimal]) -> String {
        let total = accounts.reduce(Decimal.zero) { $0 + balances[$1.id, default: .zero] }
        return "\(accounts.count) · \(NumberAbbreviator.string(from: total))"
    }

    private func budgetsSummary(budgetPressures: [BudgetRisk]) -> String {
        let over = budgetPressures.filter { $0.isOverBudget }.count
        let near = budgetPressures.filter { !$0.isOverBudget && $0.ratio >= 0.8 }.count
        if over > 0 {
            return String(format: String(localized: "%lld over budget"), Int64(over))
        }
        if near > 0 {
            return String(format: String(localized: "%lld near limit"), Int64(near))
        }
        return budgetPressures.isEmpty ? String(localized: "No budgets") : String(localized: "All on track")
    }

    private var upcomingSummary: String {
        let items = buildUpcomingItems()
        guard let first = items.first else {
            return String(localized: "No upcoming payments")
        }
        return "\(first.name) · \(first.subtitle)"
    }

    private func activitySummary(recentTransactions: [Transaction], categoryById: [UUID: Category]) -> String {
        guard let last = recentTransactions.first else {
            return String(localized: "No recent activity")
        }
        let cat = last.categoryId.flatMap { categoryById[$0] }
        let title = !last.note.isEmpty ? last.note : (cat?.name ?? last.type.localizedName)
        let sign = last.type == .income ? "+" : (last.type == .expense ? "−" : "")
        return "\(sign)\(CurrencyFormatter.string(from: last.amount)) \(title)"
    }

    @ViewBuilder
    private func accountsFocusContent(balances: [UUID: Decimal]) -> some View {
        if accounts.isEmpty {
            VStack(spacing: 10) {
                Text(String(localized: "Add your first account"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(String(localized: "Add your first account to start seeing balances, runway and reserve."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button(String(localized: "Open Accounts")) {
                    selectedTab = .accounts
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.primaryAccent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        } else {
            VStack(spacing: 10) {
                accountsScrollContent(balances: balances)
                Button(String(localized: "Open Accounts")) {
                    selectedTab = .accounts
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.primaryAccent)
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private func accountsScrollSection(balances: [UUID: Decimal]) -> some View {
        SectionShell(
            title: String(localized: "Accounts"),
            subtitle: String(localized: "See balances by account and jump into structure management."),
            trailing: {
                Button(String(localized: "See all")) {
                    selectedTab = .accounts
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.primaryAccent)
                .buttonStyle(.plain)
            }
        ) {
            accountsFocusContent(balances: balances)
        }
    }

    private func accountsScrollContent(balances: [UUID: Decimal]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(accounts) { account in
                    let balance = balances[account.id, default: .zero]
                    Button {
                        HapticManager.impact(.light)
                        selectedTab = .accounts
                    } label: {
                        accountMiniCard(account: account, balance: balance)
                    }
                    .buttonStyle(PressableButtonStyle(scale: 0.93))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
        .padding(.horizontal, -16)
    }

    private func accountMiniCard(account: Account, balance: Decimal) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: accountTypeIcon(for: account.type))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            Text(account.name)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
            Spacer().frame(height: 2)
            Text(NumberAbbreviator.string(from: balance))
                .font(.footnote.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(10)
        .frame(width: 100, height: 64)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(accountTypeGradient(for: account.type))
        )
    }

    private func accountTypeIcon(for type: AccountType) -> String {
        switch type {
        case .cash:     return "banknote.fill"
        case .checking: return "building.columns.fill"
        case .card:     return "creditcard.fill"
        case .savings:  return "arrow.up.right.circle.fill"
        case .deposit:  return "lock.fill"
        case .crypto:   return "bitcoinsign.circle.fill"
        }
    }

    private func accountTypeGradient(for type: AccountType) -> LinearGradient {
        switch type {
        case .cash:
            return LinearGradient(colors: [Color(hex: "#22C55E"), Color(hex: "#15803D")], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .checking:
            return LinearGradient(colors: [Color(hex: "#3B82F6"), Color(hex: "#1D4ED8")], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .card:
            return LinearGradient(colors: [Color(hex: "#8B5CF6"), Color(hex: "#6D28D9")], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .savings:
            return LinearGradient(colors: [Color(hex: "#06B6D4"), Color(hex: "#0369A1")], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .deposit:
            return LinearGradient(colors: [Color(hex: "#F59E0B"), Color(hex: "#B45309")], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .crypto:
            return LinearGradient(colors: [Color(hex: "#F97316"), Color(hex: "#C2410C")], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private func heroChip(icon: String, value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(color)
            Text(value)
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundStyle(AppTheme.heroCardTitle)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.white.opacity(0.12))
        .clipShape(Capsule())
    }

    // MARK: - Stat Strip

    private func statStripSection(
        income: Decimal,
        expense: Decimal,
        net: Decimal
    ) -> some View {
        let savingsRate: Int = {
            guard income > 0 else { return 0 }
            let rate = NSDecimalNumber(decimal: net / income).doubleValue
            return max(0, Int((rate * 100).rounded()))
        }()

        return HStack(spacing: 0) {
            statStripItem(
                label: String(localized: "Income"),
                value: NumberAbbreviator.string(from: income),
                valueColor: AppTheme.success
            )
            statStripDivider
            statStripItem(
                label: String(localized: "Expense"),
                value: NumberAbbreviator.string(from: expense),
                valueColor: AppTheme.danger
            )
            statStripDivider
            statStripItem(
                label: String(localized: "Savings Rate"),
                value: "\(savingsRate)%",
                valueColor: net >= 0 ? AppTheme.primaryAccent : AppTheme.warning
            )
        }
        .frame(maxWidth: .infinity)
        .frame(height: 70)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AppTheme.outline.opacity(0.5), lineWidth: 1)
                )
        )
    }

    private func statStripItem(label: String, value: String, valueColor: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var statStripDivider: some View {
        Rectangle()
            .fill(AppTheme.outline.opacity(0.4))
            .frame(width: 1, height: 36)
    }

    // MARK: - Feature Shortcuts Row

    private var featureShortcutsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                if featureGoals {
                    shortcutChip(icon: "target", label: String(localized: "Goals")) { showingGoals = true }
                }
                shortcutChip(icon: "tray.full.fill", label: String(localized: "Commitments")) { showingCommitmentsHub = true }
                shortcutChip(icon: "calendar.badge.clock", label: String(localized: "Calendar")) { showingCalendar = true }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
    }

    private func shortcutChip(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                Text(label)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(AppTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(AppTheme.outline.opacity(0.4), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - FAB Add Transaction

    private var fabAddTransactionButton: some View {
        Button {
            showingQuickAdd = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                Text(String(localized: "Add Transaction"))
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppTheme.fabGradient)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Budget Rings

    private func budgetRingsSection(
        budgetPressures: [BudgetRisk],
        freeToSpend: Decimal,
        current: (year: Int, month: Int, day: Int)
    ) -> some View {
        let topRisks = Array(budgetPressures.prefix(4))

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(String(localized: "Budget Rings"))
                    .font(.headline.weight(.semibold))
                Spacer()
                Button(String(localized: "All Budgets")) { showingBudgetManager = true }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryAccent)
                    .buttonStyle(.plain)
            }

            if topRisks.isEmpty {
                emptyBudgetState
            } else {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(topRisks, id: \.category.id) { risk in
                        budgetRingCard(for: risk)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AppTheme.outline.opacity(0.4), lineWidth: 0.5)
                )
        )
    }

    private var emptyBudgetState: some View {
        HStack(spacing: 12) {
            Image(systemName: "gauge.with.needle")
                .font(.title2)
                .foregroundStyle(AppTheme.info)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "No active budgets"))
                    .font(.subheadline.weight(.semibold))
                Text(String(localized: "Create monthly category limits to track overspend pressure."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(12)
        .background(AppTheme.surfaceMuted.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func budgetRingCard(for risk: BudgetRisk) -> some View {
        let progress = min(max(risk.ratio, 0), 1)
        let ringColor: Color = {
            if risk.isOverBudget { return AppTheme.danger }
            if risk.ratio >= 0.8 { return AppTheme.warning }
            return AppTheme.success
        }()

        return Button {
            quickAddCategory = risk.category
        } label: {
            VStack(spacing: 8) {
                // Ring with icon
                ZStack {
                    Circle()
                        .stroke(ringColor.opacity(0.15), lineWidth: 6)
                        .frame(width: 64, height: 64)

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(ringColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .frame(width: 64, height: 64)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.6), value: progress)

                    Image(systemName: risk.category.iconName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color(hex: risk.category.colorHex))
                }

                // Percentage badge
                Text(risk.isOverBudget ? String(localized: "Over") : "\(Int(progress * 100))%")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(ringColor)

                // Category name
                Text(risk.category.name)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                // Spent / limit
                Text("\(NumberAbbreviator.string(from: risk.spent)) / \(NumberAbbreviator.string(from: risk.limit))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppTheme.surfaceMuted.opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(ringColor.opacity(risk.isOverBudget ? 0.4 : 0.15), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("dashboard.budgetRing.\(risk.category.id.uuidString)")
    }

    // MARK: - Debts Summary

    private var debtsSummarySection: some View {
        let totalRemaining = activeDebts.reduce(Decimal.zero) { $0 + $1.remainingAmount }
        let totalMonthly   = activeDebts.reduce(Decimal.zero) { $0 + $1.minimumPayment }

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(String(localized: "Debts"))
                    .font(.headline.weight(.semibold))
                Spacer()
                Button(String(localized: "View All")) { showingDebts = true }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryAccent)
                    .buttonStyle(.plain)
            }

            HStack(spacing: 0) {
                debtStatCell(
                    label: String(localized: "Total Remaining"),
                    value: CurrencyFormatter.string(from: totalRemaining),
                    tint: AppTheme.danger
                )
                Divider().frame(height: 36)
                debtStatCell(
                    label: String(localized: "Monthly Payment"),
                    value: CurrencyFormatter.string(from: totalMonthly),
                    tint: AppTheme.warning
                )
                Divider().frame(height: 36)
                debtStatCell(
                    label: String(localized: "Active"),
                    value: "\(activeDebts.count)",
                    tint: AppTheme.info
                )
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AppTheme.outline.opacity(0.4), lineWidth: 0.5)
                )
        )
    }

    private func debtStatCell(label: String, value: String, tint: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Upcoming Payments

    private var upcomingPaymentsContent: some View {
        upcomingPaymentsSection
    }

    private var upcomingPaymentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(String(localized: "Upcoming Payments"))
                    .font(.headline.weight(.semibold))
                Spacer()
                Button(String(localized: "View All")) { showingCommitmentsHub = true }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryAccent)
                    .buttonStyle(.plain)
            }

            let upcomingItems = buildUpcomingItems()

            if upcomingItems.isEmpty {
                Text(String(localized: "No upcoming payments"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(upcomingItems) { item in
                            upcomingPaymentCard(item: item)
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AppTheme.outline.opacity(0.4), lineWidth: 0.5)
                )
        )
    }

    private struct UpcomingItem: Identifiable {
        let id: String
        let name: String
        let amount: Decimal
        let date: Date
        let icon: String
        let tint: Color
        let subtitle: String
    }

    private func buildUpcomingItems() -> [UpcomingItem] {
        CommitmentsPlanner.upcomingItems(
            debts: activeDebts,
            subscriptions: activeSubscriptions,
            recurringTransactions: activeRecurringTransactionsList,
            limit: 6,
            includeRecurringIncome: false
        )
        .filter { $0.isExpense }
        .map { item in
            UpcomingItem(
                id: item.id,
                name: item.title,
                amount: item.amount,
                date: item.date,
                icon: upcomingIcon(for: item),
                tint: upcomingTint(for: item),
                subtitle: item.date.formatted(date: .abbreviated, time: .omitted)
            )
        }
    }

    private func upcomingIcon(for item: CommitmentScheduleItem) -> String {
        switch item.source {
        case .debt:
            return "creditcard.fill"
        case .subscription:
            return "repeat.circle.fill"
        case .recurring:
            return "arrow.clockwise.circle.fill"
        }
    }

    private func upcomingTint(for item: CommitmentScheduleItem) -> Color {
        switch item.source {
        case .debt:
            return AppTheme.warning
        case .subscription:
            return AppTheme.primaryAccent
        case .recurring:
            return AppTheme.danger
        }
    }

    private func upcomingPaymentCard(item: UpcomingItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: item.icon)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(item.tint)
                    .frame(width: 34, height: 34)
                    .background(item.tint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                Spacer()
            }

            Text(item.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Text(CurrencyFormatter.string(from: item.amount))
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(item.tint)

            Text(item.subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 160, height: 120)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.surfaceMuted.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(item.tint.opacity(0.2), lineWidth: 1)
                )
        )
    }

    // MARK: - Recent Activity

    private func recentActivityContent(
        recentTransactions: [Transaction],
        categoryById: [UUID: Category]
    ) -> some View {
        recentActivitySection(
            recentTransactions: recentTransactions,
            categoryById: categoryById
        )
    }

    private func recentActivitySection(
        recentTransactions: [Transaction],
        categoryById: [UUID: Category]
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(String(localized: "Recent Activity"))
                    .font(.headline.weight(.semibold))
                Spacer()
                Button(String(localized: "View All")) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = .transactions
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.primaryAccent)
                .buttonStyle(.plain)
                .accessibilityIdentifier("dashboard.recentActivity.openTransactions")
            }

            if recentTransactions.isEmpty && transactions.isEmpty && accounts.isEmpty {
                VStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { _ in
                        SkeletonTransactionRow()
                    }
                }
            } else if recentTransactions.isEmpty {
                Text(String(localized: "No recent activity"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                VStack(spacing: 2) {
                    ForEach(recentTransactions.prefix(5)) { txn in
                        recentTransactionRow(txn, categoryById: categoryById)
                        if txn.id != recentTransactions.prefix(5).last?.id {
                            Divider()
                                .padding(.leading, 58)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AppTheme.outline.opacity(0.4), lineWidth: 0.5)
                )
        )
    }

    private func recentTransactionRow(_ txn: Transaction, categoryById: [UUID: Category]) -> some View {
        let cat = txn.categoryId.flatMap { categoryById[$0] }
        let tint: Color = {
            switch txn.type {
            case .income: return AppTheme.success
            case .expense: return AppTheme.danger
            case .transfer: return AppTheme.info
            }
        }()
        let title: String = {
            if !txn.note.isEmpty { return txn.note }
            if let cat { return cat.name }
            return txn.type.localizedName
        }()
        let sign = txn.type == .income ? "+" : (txn.type == .expense ? "-" : "")
        let dateText = txn.date.formatted(date: .abbreviated, time: .omitted)

        return HStack(spacing: 12) {
            Group {
                if let cat {
                    Image(systemName: cat.iconName)
                        .foregroundStyle(Color(hex: cat.colorHex))
                        .background(Color(hex: cat.colorHex).opacity(0.14))
                } else {
                    Image(systemName: txn.type == .transfer ? "arrow.left.arrow.right" : "circle.fill")
                        .foregroundStyle(tint)
                        .background(tint.opacity(0.12))
                }
            }
            .font(.caption.weight(.semibold))
            .frame(width: 34, height: 34)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(dateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text("\(sign)\(CurrencyFormatter.string(from: txn.amount))")
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(tint)
        }
        .padding(.vertical, 10)
    }

    // MARK: - Helpers

    private func budgetPressureList(
        stats s: DashboardStats,
        expenseCategories: [Category],
        current: (year: Int, month: Int, day: Int),
        previousMonth: (year: Int, month: Int)
    ) -> [BudgetRisk] {
        expenseCategories.compactMap { category in
            let limit = effectiveLimit(
                for: category,
                month: current.month,
                year: current.year,
                previousMonth: previousMonth,
                previousSpentByCategory: s.prevSpentByCategory
            )
            guard limit > 0 else { return nil }
            let spent = s.spentByCategory[category.id, default: .zero]
            let ratio = NSDecimalNumber(decimal: spent / limit).doubleValue
            return BudgetRisk(
                category: category,
                spent: spent,
                limit: limit,
                ratio: ratio,
                isOverBudget: spent > limit
            )
        }
        .sorted { lhs, rhs in
            if lhs.isOverBudget != rhs.isOverBudget {
                return lhs.isOverBudget && !rhs.isOverBudget
            }
            if lhs.ratio != rhs.ratio {
                return lhs.ratio > rhs.ratio
            }
            return lhs.spent > rhs.spent
        }
    }

    private func currentMonthLabel(from current: (year: Int, month: Int, day: Int)) -> String {
        var comps = DateComponents()
        comps.year = current.year
        comps.month = current.month
        comps.day = 1
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: Calendar.current.date(from: comps) ?? Date())
    }

    private func dailyAllowance(
        freeToSpend: Decimal,
        current: (year: Int, month: Int, day: Int)
    ) -> Decimal {
        var comps = DateComponents()
        comps.year = current.year
        comps.month = current.month
        comps.day = 1
        let monthDate = Calendar.current.date(from: comps) ?? Date()
        let daysInMonth = Calendar.current.range(of: .day, in: .month, for: monthDate)?.count ?? 30
        let daysLeft = max(1, daysInMonth - current.day + 1)
        return freeToSpend / Decimal(daysLeft)
    }

    private func freeToSpend(
        stats s: DashboardStats,
        expenseCategories: [Category],
        currentMonth: Int,
        currentYear: Int,
        previousMonth: (year: Int, month: Int)
    ) -> Decimal {
        let totalLimit = expenseCategories.reduce(Decimal.zero) {
            $0 + effectiveLimit(
                for: $1,
                month: currentMonth,
                year: currentYear,
                previousMonth: previousMonth,
                previousSpentByCategory: s.prevSpentByCategory
            )
        }
        let totalSpent = expenseCategories.reduce(Decimal.zero) { $0 + s.spentByCategory[$1.id, default: .zero] }
        guard totalLimit > 0 else { return s.monthlyIncome - s.monthlyExpense }
        return totalLimit - totalSpent
    }

    private func liveActivityCurrencySymbol() -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale.current
        return formatter.currencySymbol ?? "$"
    }

    private func updateLiveActivity(
        expenseCategories: [Category],
        current: (year: Int, month: Int, day: Int),
        previousMonth: (year: Int, month: Int),
        dashStats: DashboardStats
    ) {
#if canImport(ActivityKit)
        if #available(iOS 16.2, *) {
            let cal = Calendar.current
            let todayExpense = transactions.filter {
                cal.isDateInToday($0.date) && $0.type == .expense
            }.reduce(Decimal.zero) { $0 + $1.amount }

            let totalMonthlyLimit = expenseCategories.reduce(Decimal.zero) {
                $0 + effectiveLimit(
                    for: $1,
                    month: current.month,
                    year: current.year,
                    previousMonth: previousMonth,
                    previousSpentByCategory: dashStats.prevSpentByCategory
                )
            }
            let daysInMonth = cal.range(of: .day, in: .month, for: Date())?.count ?? 30
            let dailyBudget = totalMonthlyLimit > 0 ? totalMonthlyLimit / Decimal(daysInMonth) : .zero

            LiveActivityManager.update(
                spentToday: NSDecimalNumber(decimal: todayExpense).doubleValue,
                dailyBudget: NSDecimalNumber(decimal: dailyBudget).doubleValue,
                currencySymbol: liveActivityCurrencySymbol()
            )
        }
#endif
    }

    private func startLiveActivityIfNeeded(
        expenseCategories: [Category],
        current: (year: Int, month: Int, day: Int),
        previousMonth: (year: Int, month: Int),
        dashStats: DashboardStats
    ) {
#if canImport(ActivityKit)
        if #available(iOS 16.2, *) {
            let cal = Calendar.current
            let todayExpense = transactions.filter {
                cal.isDateInToday($0.date) && $0.type == .expense
            }.reduce(Decimal.zero) { $0 + $1.amount }

            let totalMonthlyLimit = expenseCategories.reduce(Decimal.zero) {
                $0 + effectiveLimit(
                    for: $1,
                    month: current.month,
                    year: current.year,
                    previousMonth: previousMonth,
                    previousSpentByCategory: dashStats.prevSpentByCategory
                )
            }
            let daysInMonth = cal.range(of: .day, in: .month, for: Date())?.count ?? 30
            let dailyBudget = totalMonthlyLimit > 0 ? totalMonthlyLimit / Decimal(daysInMonth) : .zero

            LiveActivityManager.start(
                spentToday: NSDecimalNumber(decimal: todayExpense).doubleValue,
                dailyBudget: NSDecimalNumber(decimal: dailyBudget).doubleValue,
                currencySymbol: liveActivityCurrencySymbol()
            )
        }
#endif
    }

    private func checkAchievements() {
        let stats = heroStats
        let currentUnlocked = AchievementStore.checkUnlocked(
            transactions: transactions,
            goals: goals,
            debts: debts,
            budgets: budgets,
            accounts: accounts,
            heroStats: stats
        )
        let stored = Set(
            unlockedAchievementsData
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        )
        let newOnes = currentUnlocked.subtracting(stored)
        guard !newOnes.isEmpty else { return }
        unlockedAchievementsData = currentUnlocked.sorted().joined(separator: ",")
        if let first = newOnes.compactMap({ id in AchievementStore.all.first { $0.id == id } }).first {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                newlyUnlockedAchievement = first
            }
        }
    }

    private func rescheduleNotifications(spentByCategory: [UUID: Decimal], categoryById: [UUID: Category]) {
        Task {
            NotificationService.rescheduleAll(
                subscriptions: subscriptionRemindersEnabled ? activeSubscriptions : [],
                debts: debtRemindersEnabled ? debts : [],
                budgets: budgetNotificationsEnabled ? budgets : [],
                spentByCategory: spentByCategory,
                categoryById: categoryById
            )
        }
    }

    private func handleCoachCTA(_ cta: CoachAdviceCTA) {
        HapticManager.impact(.light)
        switch cta {
        case .budgets:
            showingBudgetManager = true
        case .subscriptions:
            showingCommitmentsHub = true
        case .debts:
            showingCommitmentsHub = true
        case .goals:
            showingGoals = true
        case .transactions:
            selectedTab = .transactions
        case .analytics:
            selectedTab = .analytics
        case .none:
            break
        }
    }
}

private enum DashboardScanMode: String, CaseIterable, Identifiable {
    case receipt
    case barcode

    var id: String { rawValue }

    var title: String {
        switch self {
        case .receipt:
            return String(localized: "Receipt")
        case .barcode:
            return String(localized: "Barcode")
        }
    }
}

private struct DashboardCaptureScannerView: View {
    let onCapture: (PendingCapturePayload) -> Void
    let onCancel: () -> Void
    let onError: (String) -> Void

    @Environment(\.openURL) private var openURL
    @State private var mode: DashboardScanMode = .barcode
    @State private var cameraAuthorized = false
    @State private var cameraPermissionResolved = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Picker(String(localized: "Scan mode"), selection: $mode) {
                    ForEach(DashboardScanMode.allCases) { m in
                        Text(m.title).tag(m)
                    }
                }
                .pickerStyle(.segmented)

                Group {
                    if !DataScannerViewController.isSupported {
                        scannerMessageView(
                            title: String(localized: "Scanning is unavailable on this device."),
                            subtitle: String(localized: "Try using this feature on a device with camera scanning support.")
                        )
                    } else if !cameraPermissionResolved {
                        scannerMessageView(
                            title: String(localized: "Requesting camera access..."),
                            subtitle: String(localized: "Please allow camera usage to scan receipts and barcodes.")
                        )
                    } else if !cameraAuthorized {
                        scannerDeniedView
                    } else if !DataScannerViewController.isAvailable {
                        scannerMessageView(
                            title: String(localized: "Scanner is currently unavailable."),
                            subtitle: String(localized: "Close other apps using camera and try again.")
                        )
                    } else {
                        DashboardDataScannerRepresentable(
                            mode: mode,
                            onCapture: onCapture,
                            onError: onError
                        )
                        .id(mode.id)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(AppTheme.outline.opacity(0.45), lineWidth: 1)
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Text(mode == .barcode
                     ? String(localized: "Align QR/barcode inside the frame to continue.")
                     : String(localized: "Point camera at receipt line with total amount."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .background(AppTheme.canvas.ignoresSafeArea())
            .navigationTitle(String(localized: "Scan Receipt or Barcode"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { onCancel() }
                }
            }
            .onAppear {
                resolveCameraPermission()
            }
        }
    }

    private var scannerDeniedView: some View {
        VStack(spacing: 10) {
            Image(systemName: "camera.fill")
                .font(.system(size: 28))
                .foregroundStyle(AppTheme.warning)
            Text(String(localized: "Camera access is required to scan receipts and barcodes."))
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(String(localized: "Enable camera access in Settings and try again."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(String(localized: "Open Settings")) {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                openURL(url)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.primaryAccent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(18)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func scannerMessageView(title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(18)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func resolveCameraPermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            cameraAuthorized = true
            cameraPermissionResolved = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    cameraAuthorized = granted
                    cameraPermissionResolved = true
                }
            }
        case .denied, .restricted:
            cameraAuthorized = false
            cameraPermissionResolved = true
        @unknown default:
            cameraAuthorized = false
            cameraPermissionResolved = true
        }
    }
}

private struct DashboardDataScannerRepresentable: UIViewControllerRepresentable {
    let mode: DashboardScanMode
    let onCapture: (PendingCapturePayload) -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(mode: mode, onCapture: onCapture, onError: onError)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let recognizedDataTypes: Set<DataScannerViewController.RecognizedDataType> = {
            switch mode {
            case .receipt:
                return [.text()]
            case .barcode:
                return [
                    .barcode(symbologies: [.qr, .ean8, .ean13, .upce, .code39, .code128, .itf14, .pdf417, .aztec, .dataMatrix])
                ]
            }
        }()

        let scanner = DataScannerViewController(
            recognizedDataTypes: recognizedDataTypes,
            qualityLevel: .balanced,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator

        do {
            try scanner.startScanning()
        } catch {
            context.coordinator.emitErrorIfNeeded(String(localized: "Unable to start scanner."))
        }
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let mode: DashboardScanMode
        private let onCapture: (PendingCapturePayload) -> Void
        private let onError: (String) -> Void
        private var didEmitResult = false
        private var receiptFragments: [String] = []

        init(
            mode: DashboardScanMode,
            onCapture: @escaping (PendingCapturePayload) -> Void,
            onError: @escaping (String) -> Void
        ) {
            self.mode = mode
            self.onCapture = onCapture
            self.onError = onError
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            process(item)
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            for item in addedItems {
                if process(item) {
                    return
                }
            }
        }

        func emitErrorIfNeeded(_ message: String) {
            guard !didEmitResult else { return }
            didEmitResult = true
            DispatchQueue.main.async {
                self.onError(message)
            }
        }

        @discardableResult
        private func process(_ item: RecognizedItem) -> Bool {
            guard !didEmitResult else { return true }

            let payload: PendingCapturePayload?
            switch item {
            case .barcode(let barcode):
                guard mode == .barcode else { return false }
                payload = DashboardScanPayloadBuilder.payload(fromBarcode: barcode.payloadStringValue)
            case .text(let text):
                guard mode == .receipt else { return false }
                let fragment = text.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !fragment.isEmpty else { return false }
                if !receiptFragments.contains(fragment) {
                    receiptFragments.append(fragment)
                    if receiptFragments.count > 40 {
                        receiptFragments.removeFirst(receiptFragments.count - 40)
                    }
                }
                payload = DashboardScanPayloadBuilder.payload(fromReceiptText: receiptFragments.joined(separator: "\n"))
            @unknown default:
                payload = nil
            }

            guard let payload else { return false }
            if mode == .receipt, payload.amount == nil {
                // Keep scanning until we detect a line with an amount.
                return false
            }
            didEmitResult = true
            DispatchQueue.main.async {
                self.onCapture(payload)
            }
            return true
        }
    }
}

private enum DashboardScanPayloadBuilder {
    static func payload(fromBarcode rawValue: String?) -> PendingCapturePayload? {
        guard let rawValue else { return nil }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        let amount = extractAmountFromBarcode(value)
        let merchant = extractMerchantFromBarcode(value)
        let currency = detectCurrencyCode(in: value)

        return PendingCapturePayload(
            amount: amount,
            merchant: merchant,
            currency: currency,
            source: "barcode_scan"
        )
    }

    static func payload(fromReceiptText rawText: String) -> PendingCapturePayload? {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let amount = extractAmount(from: text)
        let merchant = extractMerchant(from: text)
        let currency = detectCurrencyCode(in: text)

        return PendingCapturePayload(
            amount: amount,
            merchant: merchant,
            currency: currency,
            source: "receipt_scan"
        )
    }

    private static func detectCurrencyCode(in text: String) -> String? {
        let uppercase = text.uppercased()
        if uppercase.contains("KZT") || text.contains("₸") || uppercase.contains("ТГ") { return "KZT" }
        if uppercase.contains("USD") || text.contains("$") { return "USD" }
        if uppercase.contains("RUB") || text.contains("₽") { return "RUB" }
        if uppercase.contains("EUR") || text.contains("€") { return "EUR" }
        return nil
    }

    private static func extractMerchant(from text: String) -> String {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if let firstTextLine = lines.first(where: {
            let letters = $0.unicodeScalars.filter(CharacterSet.letters.contains).count
            return letters >= 2
        }) {
            return String(firstTextLine.prefix(80))
        }
        return String(text.prefix(80))
    }

    private static func extractAmount(from text: String) -> Decimal? {
        let pattern = "(?:\\d{1,3}(?:[\\s.,]\\d{3})+|\\d+)(?:[.,]\\d{1,2})?"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: range)

        var bestCandidate: Decimal?
        for match in matches {
            guard let tokenRange = Range(match.range, in: text) else { continue }
            let token = String(text[tokenRange])
            guard let parsed = parseAmountToken(token) else { continue }
            let value = NSDecimalNumber(decimal: parsed).doubleValue
            guard value >= 1, value <= 100_000_000 else { continue }
            if let existing = bestCandidate {
                if parsed > existing { bestCandidate = parsed }
            } else {
                bestCandidate = parsed
            }
        }
        return bestCandidate
    }

    private static func parseAmountToken(_ token: String) -> Decimal? {
        let compact = token.replacingOccurrences(of: " ", with: "")
        let digitsOnly = compact.filter(\.isNumber)
        guard !digitsOnly.isEmpty else { return nil }

        if let lastSeparator = compact.lastIndex(where: { $0 == "," || $0 == "." }) {
            let fractionalDigits = compact.distance(from: compact.index(after: lastSeparator), to: compact.endIndex)
            if fractionalDigits > 0, fractionalDigits <= 2, digitsOnly.count > fractionalDigits {
                let splitIndex = digitsOnly.count - fractionalDigits
                let intPart = digitsOnly.prefix(splitIndex)
                let fractionPart = digitsOnly.suffix(fractionalDigits)
                return Decimal(string: "\(String(intPart)).\(String(fractionPart))")
            }
        }

        return Decimal(string: String(digitsOnly))
    }

    private static func extractAmountFromBarcode(_ value: String) -> Decimal? {
        if let components = URLComponents(string: value) {
            let amountKeys = ["sum", "s", "amount", "total", "price"]
            if let queryItems = components.queryItems {
                for key in amountKeys {
                    if let raw = queryItems.first(where: { $0.name.lowercased() == key })?.value,
                       let parsed = parseAmountToken(raw) {
                        return parsed
                    }
                }
            }
        }

        let patterns = [
            "(?:^|[?&;])(?:sum|s|amount|total|price)=([0-9]+(?:[\\.,][0-9]{1,2})?)",
            "(?:^|\\s)(?:sum|amount|total)[:=]\\s*([0-9]+(?:[\\.,][0-9]{1,2})?)"
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(value.startIndex..<value.endIndex, in: value)
            if let match = regex.firstMatch(in: value, options: [], range: range),
               match.numberOfRanges >= 2,
               let tokenRange = Range(match.range(at: 1), in: value),
               let parsed = parseAmountToken(String(value[tokenRange])) {
                return parsed
            }
        }

        return extractAmount(from: value)
    }

    private static func extractMerchantFromBarcode(_ value: String) -> String? {
        if let components = URLComponents(string: value) {
            let merchantKeys = ["merchant", "shop", "store", "name", "seller"]
            if let queryItems = components.queryItems {
                for key in merchantKeys {
                    if let raw = queryItems.first(where: { $0.name.lowercased() == key })?.value {
                        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !cleaned.isEmpty {
                            return String(cleaned.prefix(80))
                        }
                    }
                }
            }

            if let host = components.host {
                let cleanedHost = host.replacingOccurrences(of: "www.", with: "")
                if !cleanedHost.isEmpty {
                    return String(cleanedHost.prefix(80))
                }
            }
        }

        if value.count <= 80 {
            return value
        }
        return nil
    }
}
