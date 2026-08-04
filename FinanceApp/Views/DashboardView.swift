import SwiftUI
import SwiftData
import UserNotifications

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

    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("budgetNotificationsEnabled") private var budgetNotificationsEnabled = true
    @AppStorage("subscriptionRemindersEnabled") private var subscriptionRemindersEnabled = true
    @AppStorage("debtRemindersEnabled") private var debtRemindersEnabled = true
    @AppStorage("liveActivityEnabled") private var liveActivityEnabled = false
    @AppStorage("dash.showQuickActions") private var showQuickActions = true
    @AppStorage("dash.showThisMonth") private var showThisMonth = true
    @AppStorage("dash.showDebts") private var showDebts = true
    @AppStorage("dash.showCommitments") private var showCommitments = true
    @AppStorage("dash.showRecentActivity") private var showRecentActivity = true

    @AppStorage("feature.budgets")       private var featureBudgets = true
    @AppStorage("feature.goals")         private var featureGoals = true
    @AppStorage("feature.debts")         private var featureDebts = true
    @AppStorage("feature.subscriptions") private var featureSubscriptions = true

    @AppStorage("heroName")  private var heroName  = ""
    @AppStorage("heroEmoji") private var heroEmoji = "👋"

    @State private var monthOffset: Int = 0

    @State private var settingBudgetForCategory: Category?
    @State private var quickAddCategory: Category?
    @State private var showingQuickAdd = false
    @State private var showingGoals = false
    @State private var showingSubscriptions = false
    @State private var showingDebtsSheet = false
    @State private var showingForecast = false
    @State private var showingBudgetManager = false
    @State private var showingDashboardSettings = false

    // MARK: - Data structs

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

    private struct UpcomingItem: Identifiable {
        let id: UUID
        let name: String
        let amount: Decimal
        let date: Date
        let icon: String
        let tint: Color
        let subtitle: String
    }

    // MARK: - Computed data

    private var currentComponents: (year: Int, month: Int, day: Int) {
        let base = Date()
        let shifted = Calendar.current.date(byAdding: .month, value: monthOffset, to: base) ?? base
        let c = Calendar.current.dateComponents([.year, .month, .day], from: shifted)
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

    private func netWorth(from s: DashboardStats) -> Decimal {
        accounts.reduce(Decimal.zero) { $0 + s.netWorthByAccount[$1.id, default: .zero] }
    }

    private var expenseCategories: [Category] {
        categories.filter { $0.type == .expense }
    }

    private var activeDebts: [Debt] {
        debts.filter { $0.remainingAmount > 0 }
    }

    private var recentTransactions: [Transaction] {
        Array(transactions.filter { BalanceCalculator.isPosted($0) }.prefix(5))
    }

    private var netWorthSparkline: [Double] {
        let cal = Calendar.current
        let now = Date()
        return (-5...0).compactMap { offset -> Double? in
            guard let date = cal.date(byAdding: .month, value: offset, to: now) else { return nil }
            let comps = cal.dateComponents([.year, .month], from: date)
            let monthTxns = transactions.filter {
                let c = cal.dateComponents([.year, .month], from: $0.date)
                return c.year == comps.year && c.month == comps.month && BalanceCalculator.isPosted($0)
            }
            let inc = monthTxns.filter { $0.type == .income }.reduce(Decimal.zero) { $0 + $1.amount }
            let exp = monthTxns.filter { $0.type == .expense }.reduce(Decimal.zero) { $0 + $1.amount }
            return NSDecimalNumber(decimal: inc - exp).doubleValue
        }
    }

    private func budget(for category: Category, month: Int, year: Int) -> Budget? {
        budgets.first {
            $0.categoryId == category.id && $0.month == month && $0.year == year
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

    // MARK: - Body

    var body: some View {
        let current = currentComponents
        let previousMonth = previousMonthComponents(from: current)
        let dashboardStats = stats(current: current, previousMonth: previousMonth)
        let recentTxns = recentTransactions
        let categoryById = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        let netWorthValue = netWorth(from: dashboardStats)
        let budgetPressures = featureBudgets ? budgetPressureList(
            stats: dashboardStats,
            expenseCategories: expenseCategories,
            current: current,
            previousMonth: previousMonth
        ) : []
        let upcomingItems = buildUpcomingItems()

        return NavigationStack {
            ScrollView {
                LazyVStack(spacing: 20) {
                    greetingSection(current: current)

                    heroCard(
                        nw: netWorthValue,
                        income: dashboardStats.monthlyIncome,
                        expense: dashboardStats.monthlyExpense,
                        current: current
                    )
                    .accessibilityIdentifier("dashboard.hero.section")

                    quickActionsRow
                        .accessibilityIdentifier("dashboard.primaryActions.section")

                    latestTransactionsBlock(recentTxns, categoryById: categoryById)
                        .accessibilityIdentifier("dashboard.recentActivity.section")

                    insightsBlock(
                        pressures: budgetPressures,
                        upcoming: upcomingItems,
                        income: dashboardStats.monthlyIncome,
                        expense: dashboardStats.monthlyExpense
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 90)
            }
            .background(AppTheme.canvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .accessibilityIdentifier("dashboard.screen")
            .sheet(isPresented: $showingDashboardSettings) {
                NavigationStack { DashboardSettingsView(showsDoneButton: true) }
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
                QuickAddView()
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
            .sheet(isPresented: $showingDebtsSheet) {
                DebtsView()
                    .presentationCornerRadius(24)
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingForecast) {
                CashFlowForecastView()
                    .presentationCornerRadius(24)
                    .presentationDragIndicator(.visible)
            }
            .onAppear {
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
                        expenseCategories: expenseCategories,
                        current: current,
                        previousMonth: previousMonth,
                        dashStats: dashboardStats
                    )
                }
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
            }
        }
    }

    // MARK: - Greeting

    private func greetingSection(current: (year: Int, month: Int, day: Int)) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                let name = heroName.isEmpty ? String(localized: "there") : heroName
                Text("\(heroEmoji) \(String(format: String(localized: "Hi %@"), name))")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                Text(Date().formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                HapticManager.impact(.light)
                showingDashboardSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.body.weight(.medium))
                    .foregroundStyle(AppTheme.primaryAccent)
                    .frame(width: 38, height: 38)
                    .background(AppTheme.primaryAccent.opacity(0.12))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("dashboard.openLayoutSettings")
        }
    }

    // MARK: - Hero Card

    private func heroCard(
        nw: Decimal,
        income: Decimal,
        expense: Decimal,
        current: (year: Int, month: Int, day: Int)
    ) -> some View {
        let monthLabel = currentMonthLabel(from: current)
        let isCurrentMonth = monthOffset == 0
        let monthlyChange = income - expense
        let sparkPoints = netWorthSparkline

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { monthOffset -= 1 }
                    HapticManager.impact(.light)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 26, height: 26)
                        .background(.white.opacity(0.15))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Text(monthLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))

                Button {
                    guard monthOffset < 0 else { return }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { monthOffset += 1 }
                    HapticManager.impact(.light)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(isCurrentMonth ? .clear : .white.opacity(0.75))
                        .frame(width: 26, height: 26)
                        .background(isCurrentMonth ? .clear : .white.opacity(0.15))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(isCurrentMonth)

                Spacer()

                if monthlyChange != 0 {
                    let isPos = monthlyChange > 0
                    HStack(spacing: 3) {
                        Image(systemName: isPos ? "arrow.up" : "arrow.down")
                            .font(.system(size: 9, weight: .bold))
                        Text(CurrencyFormatter.string(from: monthlyChange > 0 ? monthlyChange : -monthlyChange))
                            .font(.caption2.weight(.bold).monospacedDigit())
                    }
                    .foregroundStyle(isPos ? Color(hex: "#4ADE80") : Color(hex: "#FC8181"))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.15))
                    .clipShape(Capsule())
                }
            }

            Spacer().frame(height: 18)

            Text(String(localized: "Net Worth"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.65))
                .textCase(.uppercase)
                .tracking(0.8)

            Text(NumberAbbreviator.string(from: nw))
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.45)
                .lineLimit(1)
                .padding(.top, 2)

            Spacer().frame(height: 14)

            if !sparkPoints.isEmpty {
                SparklineView(values: sparkPoints, tint: .white.opacity(0.8))
                    .frame(height: 38)
                    .padding(.bottom, 14)
            }

            HStack(spacing: 10) {
                heroChip(
                    icon: "arrow.down.circle.fill",
                    value: NumberAbbreviator.string(from: income),
                    label: String(localized: "Income"),
                    color: Color(hex: "#4ADE80")
                )
                heroChip(
                    icon: "arrow.up.circle.fill",
                    value: NumberAbbreviator.string(from: expense),
                    label: String(localized: "Expenses"),
                    color: Color(hex: "#FC8181")
                )
                Spacer()
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(AppTheme.fabGradient)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
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

    private func heroChip(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(color)
                Text(value)
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(.white)
            }
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.white.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Quick Actions

    private var quickActionsRow: some View {
        HStack(spacing: 0) {
            quickActionButton(icon: "plus",                      label: String(localized: "Payment"))  { showingQuickAdd = true }
            quickActionButton(icon: "list.bullet",               label: String(localized: "History"))  { selectedTab = .transactions }
            quickActionButton(icon: "creditcard",                label: String(localized: "Accounts")) { selectedTab = .accounts }
            quickActionButton(icon: "chart.line.uptrend.xyaxis", label: String(localized: "Forecast")) { showingForecast = true }
        }
        .padding(.vertical, 14)
        .background(AppTheme.primaryAccent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppTheme.primaryAccent.opacity(0.18), lineWidth: 1)
        )
    }

    private func quickActionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            HapticManager.impact(.light)
            action()
        } label: {
            VStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(AppTheme.primaryAccent)
                    .clipShape(Circle())
                Text(label)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Latest Transactions

    private func latestTransactionsBlock(
        _ recentTxns: [Transaction],
        categoryById: [UUID: Category]
    ) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(String(localized: "Latest Transactions"))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedTab = .transactions }
                } label: {
                    Text(String(localized: "See all"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.primaryAccent)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("dashboard.recentActivity.openTransactions")
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 4)

            if recentTxns.isEmpty && transactions.isEmpty && accounts.isEmpty {
                emptyAccountsCard
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            } else if recentTxns.isEmpty {
                Text(String(localized: "No recent activity"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                let top3 = Array(recentTxns.prefix(3))
                VStack(spacing: 0) {
                    ForEach(top3) { txn in
                        recentTransactionRow(txn, categoryById: categoryById)
                            .padding(.horizontal, 16)
                        if txn.id != top3.last?.id {
                            Divider().padding(.leading, 74)
                        }
                    }
                }
                .padding(.bottom, 12)
            }
        }
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppTheme.outline.opacity(0.4), lineWidth: 0.5)
        )
    }

    // MARK: - Insights

    private func insightsBlock(
        pressures: [BudgetRisk],
        upcoming: [UpcomingItem],
        income: Decimal,
        expense: Decimal
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Insights"))
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    if featureBudgets, let topRisk = pressures.first {
                        insightBudgetCard(risk: topRisk)
                    }

                    if featureSubscriptions || featureDebts, let next = upcoming.first {
                        insightUpcomingCard(item: next)
                    }

                    if income > 0 {
                        let rate = max(.zero, (income - expense) / income)
                        insightSavingsCard(rate: rate, expense: expense, income: income)
                    }

                    if featureGoals {
                        insightShortcutCard(icon: "target",        label: String(localized: "Goals"),         tint: AppTheme.primaryAccent) { showingGoals = true }
                    }
                    if featureDebts && !activeDebts.isEmpty {
                        insightShortcutCard(icon: "creditcard.fill", label: String(localized: "Debts"),       tint: AppTheme.danger)        { showingDebtsSheet = true }
                    }
                    if featureSubscriptions && !activeSubscriptions.isEmpty {
                        insightShortcutCard(icon: "repeat",          label: String(localized: "Subscriptions"), tint: AppTheme.info)         { showingSubscriptions = true }
                    }
                    if featureBudgets && pressures.count > 1 {
                        insightShortcutCard(icon: "gauge.with.needle", label: String(localized: "All Budgets"), tint: AppTheme.warning)      { showingBudgetManager = true }
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
            }
        }
    }

    private func insightBudgetCard(risk: BudgetRisk) -> some View {
        let color: Color = risk.isOverBudget ? AppTheme.danger : AppTheme.warning
        let pct = min(Int(risk.ratio * 100), 999)
        return Button {
            HapticManager.impact(.light)
            settingBudgetForCategory = risk.category
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: risk.category.iconName)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(color)
                        .frame(width: 34, height: 34)
                        .background(color.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Spacer()
                    Text("\(pct)%")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(color)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(color.opacity(0.12))
                        .clipShape(Capsule())
                }
                Text(risk.category.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(risk.isOverBudget
                     ? String(localized: "Over budget!")
                     : "\(CurrencyFormatter.string(from: risk.spent)) / \(CurrencyFormatter.string(from: risk.limit))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous).fill(color.opacity(0.15))
                        RoundedRectangle(cornerRadius: 3, style: .continuous).fill(color)
                            .frame(width: geo.size.width * min(CGFloat(risk.ratio), 1.0))
                    }
                }
                .frame(height: 6)
            }
            .padding(14)
            .frame(width: 180, height: 136)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(color.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func insightUpcomingCard(item: UpcomingItem) -> some View {
        Button {
            HapticManager.impact(.light)
            showingSubscriptions = true
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: item.icon)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(item.tint)
                        .frame(width: 34, height: 34)
                        .background(item.tint.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Spacer()
                }
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(CurrencyFormatter.string(from: item.amount))
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(item.tint)
            }
            .padding(14)
            .frame(width: 160, height: 136)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(item.tint.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func insightSavingsCard(rate: Decimal, expense: Decimal, income: Decimal) -> some View {
        let savingsPct = Int((NSDecimalNumber(decimal: rate * 100).doubleValue).rounded())
        let isPositive = expense <= income
        let tint: Color = isPositive ? AppTheme.success : AppTheme.danger

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: isPositive ? "chart.pie.fill" : "exclamationmark.circle.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                Spacer()
                Text(isPositive ? "+\(savingsPct)%" : "-\(savingsPct)%")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(tint.opacity(0.12))
                    .clipShape(Capsule())
            }
            Text(String(localized: "Savings"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text(isPositive
                 ? String(format: String(localized: "Saved %lld%% of income"), Int64(savingsPct))
                 : String(localized: "Over income this month"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(width: 160, height: 136)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(tint.opacity(0.2), lineWidth: 1)
        )
    }

    private func insightShortcutCard(
        icon: String,
        label: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            HapticManager.impact(.light)
            action()
        } label: {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 46, height: 46)
                    .background(tint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(width: 100, height: 100)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(tint.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty state

    private var emptyAccountsCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "creditcard.fill")
                .font(.system(size: 32))
                .foregroundStyle(AppTheme.info)
            Text(String(localized: "Add your first account"))
                .font(.headline)
                .foregroundStyle(.primary)
            Text(String(localized: "Your net worth and balances will appear here"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(String(localized: "Get Started")) {
                selectedTab = .accounts
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.primaryAccent)
            .controlSize(.regular)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(AppTheme.surfaceMuted.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Transaction row

    private func recentTransactionRow(_ txn: Transaction, categoryById: [UUID: Category]) -> some View {
        let cat = txn.categoryId.flatMap { categoryById[$0] }
        let tint: Color = {
            switch txn.type {
            case .income:   return AppTheme.success
            case .expense:  return AppTheme.danger
            case .transfer: return AppTheme.info
            }
        }()
        let title: String = {
            if !txn.note.isEmpty { return txn.note }
            if let cat { return cat.name }
            return txn.type.localizedName
        }()
        let sign = txn.type == .income ? "+" : (txn.type == .expense ? "-" : "")

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
                Text(txn.date.formatted(date: .abbreviated, time: .omitted))
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

    // MARK: - Business logic

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
            return BudgetRisk(category: category, spent: spent, limit: limit, ratio: ratio, isOverBudget: spent > limit)
        }
        .sorted { lhs, rhs in
            if lhs.isOverBudget != rhs.isOverBudget { return lhs.isOverBudget && !rhs.isOverBudget }
            if lhs.ratio != rhs.ratio { return lhs.ratio > rhs.ratio }
            return lhs.spent > rhs.spent
        }
    }

    private func buildUpcomingItems() -> [UpcomingItem] {
        var items: [UpcomingItem] = []
        let cal = Calendar.current
        let now = Date()

        for sub in activeSubscriptions.sorted(by: { $0.nextBillingDate < $1.nextBillingDate }).prefix(3) {
            items.append(UpcomingItem(
                id: sub.id, name: sub.name, amount: sub.amount, date: sub.nextBillingDate,
                icon: "repeat.circle.fill", tint: AppTheme.primaryAccent,
                subtitle: sub.nextBillingDate.formatted(date: .abbreviated, time: .omitted)
            ))
        }

        for debt in activeDebts.sorted(by: { $0.dueDay < $1.dueDay }).prefix(3) {
            var comps = cal.dateComponents([.year, .month], from: now)
            comps.day = debt.dueDay
            let dueDate = cal.date(from: comps) ?? now
            items.append(UpcomingItem(
                id: debt.id, name: debt.name, amount: debt.minimumPayment, date: dueDate,
                icon: "creditcard.fill", tint: AppTheme.warning,
                subtitle: dueDate.formatted(date: .abbreviated, time: .omitted)
            ))
        }

        return items.sorted { $0.date < $1.date }
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
                $0 + effectiveLimit(for: $1, month: current.month, year: current.year,
                                    previousMonth: previousMonth,
                                    previousSpentByCategory: dashStats.prevSpentByCategory)
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
                $0 + effectiveLimit(for: $1, month: current.month, year: current.year,
                                    previousMonth: previousMonth,
                                    previousSpentByCategory: dashStats.prevSpentByCategory)
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
}
