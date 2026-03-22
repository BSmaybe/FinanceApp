import SwiftUI
import SwiftData
import UserNotifications

struct DashboardView: View {
    @Query private var accounts: [Account]
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query private var categories: [Category]
    @Query private var budgets: [Budget]
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
    @State private var showingGoals = false
    @State private var showingSubscriptions = false
    @State private var showingDebts = false
    @State private var showingRecurring = false
    @State private var showingForecast = false

    // MARK: - Single-pass stats

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

            // Net worth
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

            // Current month
            if c.year == current.year && c.month == current.month {
                switch txn.type {
                case .income: income += txn.amount
                case .expense:
                    expense += txn.amount
                    if let cid = txn.categoryId {
                        spentByCat[cid, default: .zero] += txn.amount
                    }
                case .transfer: break
                }
            }

            // Previous month (for rollover)
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

    // MARK: - Budget helpers

    private var expenseCategories: [Category] {
        categories.filter { $0.type == .expense }
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

    // MARK: - Recent transactions

    private var recentTransactions: [Transaction] {
        Array(transactions.filter { BalanceCalculator.isPosted($0) }.prefix(7))
    }

    // MARK: - Body

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

        return NavigationStack {
            ZStack {
                AppTheme.canvas
                    .ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: []) {
                        netWorthSection(netWorth: netWorthValue)
                        thisMonthSection(stats: dashboardStats)
                        budgetSection(
                            stats: dashboardStats,
                            expenseCategories: expenseCategoriesList,
                            current: current,
                            previousMonth: previousMonth
                        )
                        subscriptionsSection
                        recurringSection
                        forecastSection
                        debtsSection
                        recentTransactionsSection(
                            recentTransactions: recentTransactionsList,
                            categoryById: categoryById
                        )
                        goalsSection
                    }
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
                startLiveActivityIfNeeded(
                    expenseCategories: expenseCategoriesList,
                    current: current,
                    previousMonth: previousMonth,
                    dashStats: dashboardStats
                )
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                let current2 = currentComponents
                let prev2 = previousMonthComponents(from: current2)
                let s2 = stats(current: current2, previousMonth: prev2)
                let catById2 = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
                rescheduleNotifications(spentByCategory: s2.spentByCategory, categoryById: catById2)
            }
            .onChange(of: transactions.count) { _, _ in
                let current3 = currentComponents
                let prev3 = previousMonthComponents(from: current3)
                let s3 = stats(current: current3, previousMonth: prev3)
                let catById3 = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
                rescheduleNotifications(spentByCategory: s3.spentByCategory, categoryById: catById3)
                updateLiveActivity(
                    expenseCategories: expenseCategories,
                    current: current3,
                    previousMonth: prev3,
                    dashStats: s3
                )
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "Balance"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(CurrencyFormatter.string(from: netWorthValue))
                            .font(.subheadline.bold().monospacedDigit())
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(localized: "Free to Spend"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(CurrencyFormatter.string(from: freeToSpendValue))
                            .font(.subheadline.bold().monospacedDigit())
                            .foregroundStyle(freeToSpendValue >= 0 ? .green : .red)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(AppTheme.surface)
                .overlay(
                    Rectangle()
                        .fill(AppTheme.outline.opacity(0.45))
                        .frame(height: 1),
                    alignment: .top
                )
            }
        }
    }

    // MARK: - Free money (total budget remaining)

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

    // MARK: - Live Activity

    private func liveActivityCurrencySymbol() -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = Locale.current
        return f.currencySymbol ?? "$"
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
            let dailyBudget = totalMonthlyLimit > 0
                ? totalMonthlyLimit / Decimal(daysInMonth)
                : Decimal.zero

            let spentDouble = NSDecimalNumber(decimal: todayExpense).doubleValue
            let budgetDouble = NSDecimalNumber(decimal: dailyBudget).doubleValue
            let symbol = liveActivityCurrencySymbol()

            LiveActivityManager.update(
                spentToday: spentDouble,
                dailyBudget: budgetDouble,
                currencySymbol: symbol
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
            let dailyBudget = totalMonthlyLimit > 0
                ? totalMonthlyLimit / Decimal(daysInMonth)
                : Decimal.zero

            let spentDouble = NSDecimalNumber(decimal: todayExpense).doubleValue
            let budgetDouble = NSDecimalNumber(decimal: dailyBudget).doubleValue
            let symbol = liveActivityCurrencySymbol()

            LiveActivityManager.start(
                spentToday: spentDouble,
                dailyBudget: budgetDouble,
                currencySymbol: symbol
            )
        }
#endif
    }

    // MARK: - Notifications

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

    // MARK: - Sections

    private func netWorthSection(netWorth: Decimal) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "Net Worth"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.heroCardLabel)
                Text(CurrencyFormatter.string(from: netWorth))
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.heroCardTitle)
                Text(Date(), format: .dateTime.weekday(.wide).day().month(.abbreviated))
                    .font(.caption)
                    .foregroundStyle(AppTheme.heroCardTitle.opacity(0.55))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(AppTheme.heroGradient)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(AppTheme.outline.opacity(0.5), lineWidth: 1)
                    )
            )
            .dashboardPlainRow()
        }
    }

    private func thisMonthSection(stats s: DashboardStats) -> some View {
        let net = s.monthlyIncome - s.monthlyExpense
        return VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: "This Month"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 4)
            VStack(spacing: 10) {
                monthlyStatRow(
                    icon: "arrow.down.circle.fill",
                    title: String(localized: "Income"),
                    value: s.monthlyIncome,
                    color: .green
                )
                Divider()
                    .overlay(AppTheme.outline.opacity(0.35))
                monthlyStatRow(
                    icon: "arrow.up.circle.fill",
                    title: String(localized: "Expense"),
                    value: s.monthlyExpense,
                    color: .red
                )
                Divider()
                    .overlay(AppTheme.outline.opacity(0.35))
                monthlyStatRow(
                    icon: "equal.circle.fill",
                    title: String(localized: "Net"),
                    value: net,
                    color: net >= 0 ? .green : .red,
                    bold: true
                )
            }
            .padding(14)
            .background(cardBackground(cornerRadius: 16))
            .dashboardPlainRow()
        }
    }

    @ViewBuilder
    private func budgetSection(
        stats s: DashboardStats,
        expenseCategories: [Category],
        current: (year: Int, month: Int, day: Int),
        previousMonth: (year: Int, month: Int)
    ) -> some View {
        if !expenseCategories.isEmpty {
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

            if remaining > 0 && totalEffectiveLimit > 0 {
                let daysInMonth = Calendar.current.range(of: .day, in: .month, for: Date())?.count ?? 30
                let daysLeft = max(1, daysInMonth - current.day + 1)
                let daily = remaining / Decimal(daysLeft)
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "Daily Allowance"))
                                .font(.headline)
                            Text(String(format: String(localized: "%lld days left"), daysLeft))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(CurrencyFormatter.string(from: daily))
                            .font(.title3.monospacedDigit().bold())
                            .foregroundStyle(.green)
                    }
                    .padding(14)
                    .background(cardBackground(cornerRadius: 16))
                    .dashboardPlainRow()
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(String(localized: "Budget"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .padding(.bottom, 4)
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

        return Button {
            quickAddCategory = category
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: category.iconName)
                        .font(.caption)
                        .foregroundStyle(Color(hex: category.colorHex))
                        .frame(width: 24, height: 24)
                        .background(Color(hex: category.colorHex).opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    Text(category.name)
                    Spacer()
                    if hasBudget {
                        if spent > limit {
                            Text(String(localized: "Over budget"))
                                .font(.caption)
                                .foregroundStyle(.red)
                        } else {
                            Text("\(CurrencyFormatter.string(from: spent)) / \(CurrencyFormatter.string(from: limit))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text(
                            spent > 0
                            ? String(format: String(localized: "Spent: %@"), CurrencyFormatter.string(from: spent))
                            : String(localized: "No expenses")
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                if hasBudget && limit > 0 {
                    let ratio = NSDecimalNumber(decimal: spent / limit).doubleValue
                    let progress = min(ratio, 1.0)
                    let color: Color = ratio >= 1.0 ? .red : (ratio >= 0.8 ? .orange : .green)

                    ProgressView(value: progress)
                        .tint(color)
                    HStack {
                        if spent < limit {
                            Text(String(format: String(localized: "Remaining: %@"), CurrencyFormatter.string(from: limit - spent)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(Int(progress * 100))% \(String(localized: "used"))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(color)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(cardBackground(cornerRadius: 14))
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("dashboard.budgetRow.\(category.id.uuidString)")
        .buttonStyle(.plain)
        .padding(.vertical, 2)
        .dashboardPlainRow()
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

    @ViewBuilder
    private func recentTransactionsSection(
        recentTransactions: [Transaction],
        categoryById: [UUID: Category]
    ) -> some View {
        if !recentTransactions.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text(String(localized: "Recent Transactions"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .padding(.bottom, 4)
                ForEach(recentTransactions) { txn in
                    recentTransactionRow(txn, categoryById: categoryById)
                }
            }
        }
    }

    // MARK: - Subscriptions Section

    @ViewBuilder
    private var subscriptionsSection: some View {
        let totalMonthly = activeSubscriptions.reduce(Decimal.zero) { $0 + $1.monthlyCost }
        VStack(alignment: .leading, spacing: 0) {
            Button {
                showingSubscriptions = true
            } label: {
                HStack {
                    Image(systemName: "repeat.circle.fill")
                        .foregroundStyle(AppTheme.primaryAccent)
                    Text(String(localized: "Subscriptions"))
                    Spacer()
                    Text(CurrencyFormatter.string(from: totalMonthly))
                        .font(.body.monospacedDigit())
                        .foregroundStyle(AppTheme.primaryAccent)
                    Text(String(localized: "/mo"))
                        .font(.caption)
                        .foregroundStyle(AppTheme.primaryAccent.opacity(0.75))
                }
                .padding(12)
                .background(cardBackground(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .dashboardPlainRow()
        }
    }

    // MARK: - Recurring Section

    private var recurringSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                showingRecurring = true
            } label: {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(AppTheme.primaryAccent)
                    Text(String(localized: "Recurring Transactions"))
                    Spacer()
                    Text("\(recurringTransactions.count)")
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(cardBackground(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .dashboardPlainRow()
        }
    }

    // MARK: - Forecast Section

    private var forecastSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                showingForecast = true
            } label: {
                HStack {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .foregroundStyle(AppTheme.primaryAccent)
                    Text(String(localized: "Cash Flow Forecast"))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(cardBackground(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .dashboardPlainRow()
        }
    }

    // MARK: - Debts Section

    @ViewBuilder
    private var debtsSection: some View {
        let activeDebts = debts.filter { $0.remainingAmount > 0 }
        if !activeDebts.isEmpty {
            let totalDebt = activeDebts.reduce(Decimal.zero) { $0 + $1.remainingAmount }
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    showingDebts = true
                } label: {
                    HStack {
                        Image(systemName: "creditcard.trianglebadge.exclamationmark.fill")
                            .foregroundStyle(.red)
                        Text(String(localized: "Debts"))
                        Spacer()
                        Text(CurrencyFormatter.string(from: totalDebt))
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.red)
                    }
                    .padding(12)
                    .background(cardBackground(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .dashboardPlainRow()
            }
        }
    }

    private var goalsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                showingGoals = true
            } label: {
                HStack {
                    Image(systemName: "flag.fill")
                        .foregroundStyle(AppTheme.secondaryAccent)
                    Text(String(localized: "Goals"))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(cardBackground(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .dashboardPlainRow()
        }
    }

    // MARK: - Recent Transaction Row

    private func recentTransactionRow(_ txn: Transaction, categoryById: [UUID: Category]) -> some View {
        let cat = txn.categoryId.flatMap { categoryById[$0] }
        return HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(txn.type == .expense ? Color.red : (txn.type == .income ? Color.green : AppTheme.timelineDot))
                .frame(width: 8, height: 8)
                .padding(.top, 13)

            HStack {
                if let cat = cat {
                    Image(systemName: cat.iconName)
                        .font(.callout)
                        .foregroundStyle(Color(hex: cat.colorHex))
                        .frame(width: 32, height: 32)
                        .background(Color(hex: cat.colorHex).opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                } else {
                    Image(systemName: txn.type == .income ? "arrow.down.circle.fill" :
                            txn.type == .expense ? "arrow.up.circle.fill" : "arrow.left.arrow.right.circle.fill")
                        .foregroundStyle(txn.type == .income ? .green : (txn.type == .expense ? .red : .blue))
                        .font(.title3)
                }

                VStack(alignment: .leading, spacing: 2) {
                    if txn.note.isEmpty {
                        if let cid = txn.categoryId, let cat = categoryById[cid] {
                            Text(cat.name)
                        } else {
                            Text(txn.type.localizedName)
                        }
                    } else {
                        Text(txn.note)
                    }
                    Text(txn.date, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                let sign = txn.type == .income ? "+" : (txn.type == .expense ? "-" : "")
                Text("\(sign)\(CurrencyFormatter.string(from: txn.amount))")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(txn.type == .income ? .green : (txn.type == .expense ? .red : .primary))
            }
            .padding(12)
            .background(cardBackground(cornerRadius: 14))
        }
        .dashboardPlainRow()
    }

    private func monthlyStatRow(
        icon: String,
        title: String,
        value: Decimal,
        color: Color,
        bold: Bool = false
    ) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(title)
                .fontWeight(bold ? .semibold : .regular)
            Spacer()
            Text(CurrencyFormatter.string(from: value))
                .font(bold ? .body.monospacedDigit().bold() : .body.monospacedDigit())
                .foregroundStyle(color)
        }
    }

    private func cardBackground(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(AppTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(AppTheme.outline.opacity(0.45), lineWidth: 1)
            )
    }
}

private extension View {
    func dashboardPlainRow() -> some View {
        self
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
    }
}
