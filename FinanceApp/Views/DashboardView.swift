import SwiftUI
import SwiftData
import UserNotifications

private enum DashboardAnchor: Hashable {
    case monthlyHealth
    case commitments
    case recentActivity
}

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
    @Query private var allSubscriptions: [Subscription]
    @Query private var debts: [Debt]
    @Query(filter: #Predicate<RecurringTransaction> { $0.isActive == true })
    private var recurringTransactions: [RecurringTransaction]

    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("budgetNotificationsEnabled") private var budgetNotificationsEnabled = true
    @AppStorage("subscriptionRemindersEnabled") private var subscriptionRemindersEnabled = true
    @AppStorage("debtRemindersEnabled") private var debtRemindersEnabled = true
    @AppStorage("liveActivityEnabled") private var liveActivityEnabled = false

    @State private var settingBudgetForCategory: Category?
    @State private var quickAddCategory: Category?
    @State private var showingQuickAdd = false
    @State private var showingGoals = false
    @State private var showingSubscriptions = false
    @State private var showingDebts = false
    @State private var showingRecurring = false
    @State private var showingForecast = false
    @State private var showingBudgetManager = false

    private struct DashboardStats {
        let netWorthByAccount: [UUID: Decimal]
        let monthlyIncome: Decimal
        let monthlyExpense: Decimal
        let spentByCategory: [UUID: Decimal]
        let prevSpentByCategory: [UUID: Decimal]
    }

    private var currentComponents: (year: Int, month: Int, day: Int) {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
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

        var balances: [UUID: Decimal] = [:]
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
        Array(transactions.filter { BalanceCalculator.isPosted($0) }.prefix(6))
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
        let dailyAllowanceValue = dailyAllowance(
            stats: dashboardStats,
            expenseCategories: expenseCategoriesList,
            current: current,
            previousMonth: previousMonth
        )
        let monthlyNetValue = dashboardStats.monthlyIncome - dashboardStats.monthlyExpense

        return NavigationStack {
            ScrollViewReader { proxy in
                ZStack {
                    AppTheme.canvas
                        .ignoresSafeArea()

                    ScrollView {
                        LazyVStack(spacing: 18) {
                            heroSnapshotSection(
                                netWorth: netWorthValue,
                                freeToSpend: freeToSpendValue,
                                monthlyNet: monthlyNetValue,
                                dailyAllowance: dailyAllowanceValue
                            )

                            quickActionsSection {
                                showingBudgetManager = true
                            }

                            monthlyHealthSection(
                                stats: dashboardStats,
                                expenseCategories: expenseCategoriesList,
                                current: current,
                                previousMonth: previousMonth,
                                dailyAllowance: dailyAllowanceValue
                            )
                            .id(DashboardAnchor.monthlyHealth)

                            commitmentsSection
                                .id(DashboardAnchor.commitments)

                            recentActivitySection(
                                recentTransactions: recentTransactionsList,
                                categoryById: categoryById
                            )
                            .id(DashboardAnchor.recentActivity)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 88)
                    }
                }
                .accessibilityIdentifier("dashboard.screen")
                .navigationTitle(String(localized: "Dashboard"))
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarBackground(AppTheme.surface, for: .navigationBar)
                .sheet(item: $settingBudgetForCategory) { category in
                    SetBudgetView(
                        category: category,
                        month: current.month,
                        year: current.year,
                        existing: budget(for: category, month: current.month, year: current.year)
                    )
                }
                .sheet(item: $quickAddCategory) { category in
                    QuickAddView(prefillCategoryId: category.id)
                }
                .sheet(isPresented: $showingQuickAdd) {
                    QuickAddView()
                }
                .sheet(isPresented: $showingBudgetManager) {
                    BudgetManagerView(month: current.month, year: current.year)
                }
                .sheet(isPresented: $showingGoals) {
                    GoalsView()
                }
                .sheet(isPresented: $showingSubscriptions) {
                    SubscriptionsView()
                }
                .sheet(isPresented: $showingRecurring) {
                    NavigationStack {
                        RecurringTransactionsView()
                    }
                }
                .sheet(isPresented: $showingDebts) {
                    DebtsView()
                }
                .sheet(isPresented: $showingForecast) {
                    CashFlowForecastView()
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
                            expenseCategories: expenseCategoriesList,
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
                .safeAreaInset(edge: .bottom) {
                    compactSummaryBar(
                        balance: netWorthValue,
                        freeToSpend: freeToSpendValue,
                        monthlyNet: monthlyNetValue
                    )
                }
            }
        }
    }

    private func heroSnapshotSection(
        netWorth: Decimal,
        freeToSpend: Decimal,
        monthlyNet: Decimal,
        dailyAllowance: Decimal?
    ) -> some View {
        HeroMetricCard(
            title: String(localized: "Net Worth"),
            value: CurrencyFormatter.string(from: netWorth),
            supportingTitle: String(localized: "Free to Spend"),
            supportingValue: CurrencyFormatter.string(from: freeToSpend),
            note: Date().formatted(date: .abbreviated, time: .omitted),
            badgeText: monthlyTrendBadge(monthlyNet)
        )
        .overlay(alignment: .bottomTrailing) {
            if let dailyAllowance {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(localized: "Daily Allowance"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppTheme.heroCardTitle.opacity(0.68))
                    Text(CurrencyFormatter.string(from: dailyAllowance))
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(AppTheme.heroCardTitle)
                }
                .padding(16)
            }
        }
    }

    private func quickActionsSection(scrollToBudget: @escaping () -> Void) -> some View {
        SectionShell(
            title: String(localized: "Quick Actions"),
            subtitle: String(localized: "Capture, review, and adjust from one place")
        ) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ActionTile(
                    title: String(localized: "Quick Add"),
                    subtitle: String(localized: "Capture a transaction fast"),
                    systemImage: "plus.circle.fill",
                    tint: AppTheme.primaryAccent
                ) {
                    showingQuickAdd = true
                }
                ActionTile(
                    title: String(localized: "Budget"),
                    subtitle: String(localized: "Set monthly limits by category"),
                    systemImage: "gauge.with.needle.fill",
                    tint: AppTheme.success,
                    action: scrollToBudget
                )
                .accessibilityIdentifier("dashboard.quickAction.budget")
                ActionTile(
                    title: String(localized: "Forecast"),
                    subtitle: String(localized: "Stress-test upcoming cash flow"),
                    systemImage: "chart.line.uptrend.xyaxis",
                    tint: AppTheme.info
                ) {
                    showingForecast = true
                }
                ActionTile(
                    title: String(localized: "Recurring"),
                    subtitle: recurringTransactions.isEmpty
                        ? String(localized: "No recurring items yet")
                        : String(format: String(localized: "%lld active automations"), recurringTransactions.count),
                    systemImage: "arrow.triangle.2.circlepath",
                    tint: AppTheme.secondaryAccent
                ) {
                    showingRecurring = true
                }
                ActionTile(
                    title: String(localized: "Subscriptions"),
                    subtitle: activeSubscriptions.isEmpty
                        ? String(localized: "Track fixed monthly costs")
                        : CurrencyFormatter.string(from: activeSubscriptions.reduce(.zero) { $0 + $1.monthlyCost }),
                    systemImage: "repeat.circle.fill",
                    tint: AppTheme.primaryAccent
                ) {
                    showingSubscriptions = true
                }
                ActionTile(
                    title: String(localized: "Debts"),
                    subtitle: activeDebts.isEmpty
                        ? String(localized: "No active debts")
                        : CurrencyFormatter.string(from: activeDebts.reduce(.zero) { $0 + $1.remainingAmount }),
                    systemImage: "creditcard.trianglebadge.exclamationmark.fill",
                    tint: AppTheme.warning
                ) {
                    showingDebts = true
                }
            }
        }
    }

    private func monthlyHealthSection(
        stats s: DashboardStats,
        expenseCategories: [Category],
        current: (year: Int, month: Int, day: Int),
        previousMonth: (year: Int, month: Int),
        dailyAllowance: Decimal?
    ) -> some View {
        let net = s.monthlyIncome - s.monthlyExpense
        let monthTitle = currentMonthLabel(from: current)

        return SectionShell(
            title: String(localized: "Monthly Health"),
            subtitle: monthTitle,
            trailing: {
                Button(String(localized: "Manage")) {
                    showingBudgetManager = true
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.plain)
                .accessibilityIdentifier("dashboard.monthlyHealth.manageBudgets")
            }
        ) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                InsightCard(
                    title: String(localized: "Income"),
                    value: CurrencyFormatter.string(from: s.monthlyIncome),
                    message: String(localized: "Posted income this month"),
                    systemImage: "arrow.down.circle.fill",
                    tint: AppTheme.success
                )
                InsightCard(
                    title: String(localized: "Expense"),
                    value: CurrencyFormatter.string(from: s.monthlyExpense),
                    message: String(localized: "Committed outflow this month"),
                    systemImage: "arrow.up.circle.fill",
                    tint: AppTheme.danger
                )
                InsightCard(
                    title: String(localized: "Net"),
                    value: CurrencyFormatter.string(from: net),
                    message: net >= 0
                        ? String(localized: "You are still ahead this month")
                        : String(localized: "Expenses are ahead of income"),
                    systemImage: "equal.circle.fill",
                    tint: net >= 0 ? AppTheme.success : AppTheme.danger
                )
                InsightCard(
                    title: String(localized: "Daily Allowance"),
                    value: CurrencyFormatter.string(from: dailyAllowance ?? .zero),
                    message: dailyAllowance == nil
                        ? String(localized: "Set budgets to unlock a daily allowance")
                        : String(localized: "Safe spend per day until month end"),
                    systemImage: "calendar.badge.clock",
                    tint: AppTheme.info
                )
            }

            if expenseCategories.isEmpty {
                Text(String(localized: "Create expense categories to start building monthly guardrails."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text(String(localized: "Budget Breakdown"))
                        .font(.subheadline.weight(.semibold))
                    ForEach(expenseCategories) { category in
                        budgetRow(
                            for: category,
                            stats: s,
                            currentMonth: current.month,
                            currentYear: current.year,
                            previousMonth: previousMonth
                        )
                    }
                }
            }
        }
    }

    private var commitmentsSection: some View {
        SectionShell(
            title: String(localized: "Commitments"),
            subtitle: String(localized: "Recurring obligations and long-term goals")
        ) {
            VStack(spacing: 12) {
                Button {
                    showingSubscriptions = true
                } label: {
                    InsightCard(
                        title: String(localized: "Subscriptions"),
                        value: CurrencyFormatter.string(from: activeSubscriptions.reduce(.zero) { $0 + $1.monthlyCost }),
                        message: activeSubscriptions.isEmpty
                            ? String(localized: "No active subscriptions")
                            : String(format: String(localized: "%lld active plans billed monthly"), activeSubscriptions.count),
                        systemImage: "repeat.circle.fill",
                        tint: AppTheme.primaryAccent
                    )
                }
                .buttonStyle(.plain)

                Button {
                    showingDebts = true
                } label: {
                    InsightCard(
                        title: String(localized: "Debts"),
                        value: CurrencyFormatter.string(from: activeDebts.reduce(.zero) { $0 + $1.remainingAmount }),
                        message: activeDebts.isEmpty
                            ? String(localized: "No active debts")
                            : String(format: String(localized: "%lld balances still open"), activeDebts.count),
                        systemImage: "creditcard.trianglebadge.exclamationmark.fill",
                        tint: AppTheme.warning
                    )
                }
                .buttonStyle(.plain)

                Button {
                    showingGoals = true
                } label: {
                    InsightCard(
                        title: String(localized: "Goals"),
                        value: activeGoals.first.map { "\(Int($0.progress * 100))%" } ?? String(localized: "No target"),
                        message: activeGoals.first.map { "\($0.name)" } ?? String(localized: "Set a savings goal to track progress"),
                        systemImage: "flag.fill",
                        tint: AppTheme.secondaryAccent
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func recentActivitySection(
        recentTransactions: [Transaction],
        categoryById: [UUID: Category]
    ) -> some View {
        SectionShell(
            title: String(localized: "Recent Activity"),
            subtitle: String(localized: "Latest posted transactions")
        ) {
            HStack {
                Text(String(localized: "Stay close to the journal when balances move."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 12)
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = .transactions
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(String(localized: "Open Transactions"))
                        Image(systemName: "arrow.right")
                    }
                    .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
            }

            if recentTransactions.isEmpty {
                InsightCard(
                    title: String(localized: "No recent activity"),
                    value: String(localized: "Ready"),
                    message: String(localized: "Your recent posted transactions will surface here."),
                    systemImage: "clock.arrow.circlepath",
                    tint: AppTheme.info
                )
            } else {
                VStack(spacing: 10) {
                    ForEach(recentTransactions.prefix(4)) { txn in
                        recentTransactionRow(txn, categoryById: categoryById)
                    }
                }
            }
        }
    }

    private func budgetRow(
        for category: Category,
        stats s: DashboardStats,
        currentMonth: Int,
        currentYear: Int,
        previousMonth: (year: Int, month: Int)
    ) -> some View {
        let b = budget(for: category, month: currentMonth, year: currentYear)
        let spent = s.spentByCategory[category.id, default: .zero]
        let limit = effectiveLimit(
            for: category,
            month: currentMonth,
            year: currentYear,
            previousMonth: previousMonth,
            previousSpentByCategory: s.prevSpentByCategory
        )
        let hasBudget = b != nil
        let ratio = limit > 0 ? NSDecimalNumber(decimal: spent / limit).doubleValue : 0
        let progress = min(max(ratio, 0), 1)
        let accent = ratio >= 1 ? AppTheme.danger : (ratio >= 0.8 ? AppTheme.warning : AppTheme.success)

        return Button {
            quickAddCategory = category
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: category.iconName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(hex: category.colorHex))
                        .frame(width: 30, height: 30)
                        .background(Color(hex: category.colorHex).opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(category.name)
                            .font(.subheadline.weight(.semibold))
                        Text(hasBudget
                             ? "\(CurrencyFormatter.string(from: spent)) / \(CurrencyFormatter.string(from: limit))"
                             : (spent > 0
                                ? String(format: String(localized: "Spent: %@"), CurrencyFormatter.string(from: spent))
                                : String(localized: "No expenses")))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 10)
                    Text(hasBudget && spent > limit
                         ? String(localized: "Over")
                         : percentageLabel(progress))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(accent.opacity(0.12))
                        .clipShape(Capsule())
                }

                if hasBudget && limit > 0 {
                    VStack(spacing: 8) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(AppTheme.surfaceMuted)
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(accent)
                                    .frame(width: max(8, geo.size.width * progress))
                            }
                        }
                        .frame(height: 10)

                        HStack {
                            Text(spent < limit
                                 ? String(format: String(localized: "Remaining: %@"), CurrencyFormatter.string(from: limit - spent))
                                 : String(localized: "Budget exhausted"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(CurrencyFormatter.string(from: limit))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cockpitSurface(cornerRadius: 20, elevated: true, compact: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("dashboard.budgetRow.\(category.id.uuidString)")
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .swipeActions(edge: .trailing) {
            Button {
                settingBudgetForCategory = category
            } label: {
                Label(String(localized: "Budget"), systemImage: "slider.horizontal.3")
            }
            .tint(.orange)
        }
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
        let subtitle: String = {
            switch txn.type {
            case .transfer:
                return String(localized: "Transfer")
            case .income:
                return String(localized: "Income")
            case .expense:
                return String(localized: "Expense")
            }
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

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("\(subtitle) • \(txn.date.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text("\(sign)\(CurrencyFormatter.string(from: txn.amount))")
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(tint)
        }
        .cockpitSurface(cornerRadius: 20, elevated: true, compact: true)
    }

    private func compactSummaryBar(balance: Decimal, freeToSpend: Decimal, monthlyNet: Decimal) -> some View {
        HStack(spacing: 12) {
            summaryColumn(title: String(localized: "Balance"), value: CurrencyFormatter.string(from: balance))
            Divider()
                .frame(height: 24)
            summaryColumn(title: String(localized: "Free"), value: CurrencyFormatter.string(from: freeToSpend))
            Spacer(minLength: 12)
            Text(monthlyTrendBadge(monthlyNet))
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(monthlyNet >= 0 ? AppTheme.success : AppTheme.danger)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background((monthlyNet >= 0 ? AppTheme.success : AppTheme.danger).opacity(0.12))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AppTheme.surface.opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(AppTheme.outline.opacity(0.55), lineWidth: 1)
                )
                .shadow(color: AppTheme.shadowSoft, radius: 12, x: 0, y: 6)
        )
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    private func summaryColumn(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospacedDigit().weight(.semibold))
                .lineLimit(1)
        }
    }

    private func monthlyTrendBadge(_ value: Decimal) -> String {
        let prefix = value >= 0 ? "+" : "-"
        return "\(prefix)\(CurrencyFormatter.string(from: abs(value)))"
    }

    private func percentageLabel(_ progress: Double) -> String {
        "\(Int(progress * 100))%"
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
        stats s: DashboardStats,
        expenseCategories: [Category],
        current: (year: Int, month: Int, day: Int),
        previousMonth: (year: Int, month: Int)
    ) -> Decimal? {
        let totalEffectiveLimit = expenseCategories.reduce(Decimal.zero) {
            $0 + effectiveLimit(
                for: $1,
                month: current.month,
                year: current.year,
                previousMonth: previousMonth,
                previousSpentByCategory: s.prevSpentByCategory
            )
        }
        let totalSpent = expenseCategories.reduce(Decimal.zero) { $0 + s.spentByCategory[$1.id, default: .zero] }
        let remaining = totalEffectiveLimit - totalSpent
        guard remaining > 0, totalEffectiveLimit > 0 else { return nil }
        let daysInMonth = Calendar.current.range(of: .day, in: .month, for: Date())?.count ?? 30
        let daysLeft = max(1, daysInMonth - current.day + 1)
        return remaining / Decimal(daysLeft)
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

    private func rescheduleNotifications(spentByCategory: [UUID: Decimal], categoryById: [UUID: Category]) {
        Task {
            _ = await NotificationService.requestPermission()
            NotificationService.rescheduleAll(
                subscriptions: subscriptionRemindersEnabled ? allSubscriptions : [],
                debts: debtRemindersEnabled ? debts : [],
                budgets: budgetNotificationsEnabled ? budgets : [],
                spentByCategory: spentByCategory,
                categoryById: categoryById
            )
        }
    }
}
