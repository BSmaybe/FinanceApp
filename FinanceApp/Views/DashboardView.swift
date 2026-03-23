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

    @State private var monthOffset: Int = 0

    @State private var settingBudgetForCategory: Category?
    @State private var quickAddCategory: Category?
    @State private var showingQuickAdd = false
    @State private var showingGoals = false
    @State private var showingSubscriptions = false
    @State private var showingDebts = false
    @State private var showingForecast = false
    @State private var showingBudgetManager = false
    @State private var showingDashboardSettings = false

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
        let budgetPressures = budgetPressureList(
            stats: dashboardStats,
            expenseCategories: expenseCategoriesList,
            current: current,
            previousMonth: previousMonth
        )

        return NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Hero: gradient background auto-sized to content
                    heroFloatingSection(
                        netWorth: netWorthValue,
                        income: dashboardStats.monthlyIncome,
                        expense: dashboardStats.monthlyExpense,
                        savingsRate: dashboardStats.monthlyIncome > 0
                            ? max(.zero, (dashboardStats.monthlyIncome - dashboardStats.monthlyExpense) / dashboardStats.monthlyIncome)
                            : .zero
                    )
                    .background(
                        AppTheme.heroGradient
                            .ignoresSafeArea(edges: .top)
                    )
                    .accessibilityIdentifier("dashboard.hero.section")

                    // Content area: rounded top, canvas colour
                    LazyVStack(spacing: 12) {
                        if !accounts.isEmpty {
                                accountsScrollSection(
                                    balances: dashboardStats.netWorthByAccount
                                )
                            }

                            if showQuickActions {
                                fabAddTransactionButton
                                    .accessibilityIdentifier("dashboard.primaryActions.section")
                                featureShortcutsRow
                            }

                            if showThisMonth {
                                budgetRingsSection(
                                    budgetPressures: budgetPressures,
                                    freeToSpend: freeToSpendValue,
                                    current: current
                                )
                                .accessibilityIdentifier("dashboard.thisMonth.section")
                            }

                            if showDebts && !activeDebts.isEmpty {
                                debtsSummarySection
                                    .accessibilityIdentifier("dashboard.debts.section")
                            }

                            if showCommitments {
                                upcomingPaymentsSection
                                    .accessibilityIdentifier("dashboard.commitments.section")
                            }

                            if showRecentActivity {
                                recentActivitySection(
                                    recentTransactions: recentTransactionsList,
                                    categoryById: categoryById
                                )
                                .accessibilityIdentifier("dashboard.recentActivity.section")
                            }
                        }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .padding(.bottom, 32)
                    .frame(maxWidth: .infinity, minHeight: UIScreen.main.bounds.height * 0.7)
                    .background(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 24,
                            bottomLeadingRadius: 0,
                            bottomTrailingRadius: 0,
                            topTrailingRadius: 24
                        )
                        .fill(AppTheme.canvas)
                        .ignoresSafeArea(edges: .bottom)
                    )
                }
            }
            .background(AppTheme.canvas.ignoresSafeArea())
            .accessibilityIdentifier("dashboard.screen")
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingDashboardSettings) {
                NavigationStack {
                    DashboardSettingsView(showsDoneButton: true)
                }
            }
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
        }
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

    private func heroFloatingSection(
        netWorth: Decimal,
        income: Decimal,
        expense: Decimal,
        savingsRate: Decimal
    ) -> some View {
        let isCurrentMonth = monthOffset == 0
        let monthLabel = currentMonthLabel(from: currentComponents)
        let savingsPct = Int((savingsRate * 100 as NSDecimalNumber).doubleValue.rounded())

        return VStack(alignment: .leading, spacing: 0) {
            // Top row: greeting + settings
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(greetingText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.heroCardLabel)
                    Text(Date().formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                        .font(.caption2)
                        .foregroundStyle(AppTheme.heroCardLabel.opacity(0.5))
                }
                Spacer()
                Button {
                    HapticManager.impact(.light)
                    showingDashboardSettings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(AppTheme.heroCardLabel)
                        .frame(width: 34, height: 34)
                        .background(.white.opacity(0.15))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("dashboard.openLayoutSettings")
            }

            Spacer().frame(height: 14)

            // Net worth
            Text(String(localized: "Net Worth"))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.heroCardLabel.opacity(0.7))
                .textCase(.uppercase)
                .tracking(0.8)
            Text(NumberAbbreviator.string(from: netWorth))
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.heroCardTitle)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .padding(.top, 2)

            // Quote strip
            let quote = DailyQuoteStore.today
            Text("\u{201C}\(quote.localizedText)\u{201D}  — \(quote.source)")
                .font(.system(size: 11, weight: .regular, design: .serif))
                .italic()
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .padding(.top, 6)

            Spacer().frame(height: 14)

            // Month nav + income/expense/savings chips
            HStack(spacing: 8) {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { monthOffset -= 1 }
                    HapticManager.impact(.light)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(AppTheme.heroCardLabel)
                        .frame(width: 26, height: 26)
                        .background(.white.opacity(0.15))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Text(monthLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.heroCardLabel)

                Button {
                    guard monthOffset < 0 else { return }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { monthOffset += 1 }
                    HapticManager.impact(.light)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(isCurrentMonth ? .clear : AppTheme.heroCardLabel)
                        .frame(width: 26, height: 26)
                        .background(isCurrentMonth ? .clear : .white.opacity(0.15))
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
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 22)
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

    private func accountsScrollSection(balances: [UUID: Decimal]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Accounts"))
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(accounts) { account in
                        let balance = balances[account.id, default: .zero]
                        accountMiniCard(account: account, balance: balance)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
            }
            .padding(.horizontal, -16)
        }
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
                shortcutChip(icon: "target", label: String(localized: "Goals")) { showingGoals = true }
                shortcutChip(icon: "creditcard.fill", label: String(localized: "Debts")) { showingDebts = true }
                shortcutChip(icon: "repeat", label: String(localized: "Subscriptions")) { showingSubscriptions = true }
                shortcutChip(icon: "chart.line.uptrend.xyaxis", label: String(localized: "Forecast")) { showingForecast = true }
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
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.title3.weight(.semibold))
                Text(String(localized: "Add Transaction"))
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppTheme.fabGradient)
                    .shadow(color: AppTheme.shadowSoft, radius: 6, x: 0, y: 2)
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
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(AppTheme.outline.opacity(0.5), lineWidth: 1)
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
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(AppTheme.outline.opacity(0.5), lineWidth: 1)
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

    private var upcomingPaymentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(String(localized: "Upcoming Payments"))
                    .font(.headline.weight(.semibold))
                Spacer()
                Button(String(localized: "Debts")) { showingDebts = true }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.warning)
                    .buttonStyle(.plain)
                Text("·")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(String(localized: "Subscriptions")) { showingSubscriptions = true }
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
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(AppTheme.outline.opacity(0.5), lineWidth: 1)
                )
        )
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

    private func buildUpcomingItems() -> [UpcomingItem] {
        var items: [UpcomingItem] = []

        let cal = Calendar.current
        let now = Date()

        // Next subscription billing dates
        let sortedSubs = activeSubscriptions
            .sorted { $0.nextBillingDate < $1.nextBillingDate }
            .prefix(3)
        for sub in sortedSubs {
            items.append(UpcomingItem(
                id: sub.id,
                name: sub.name,
                amount: sub.amount,
                date: sub.nextBillingDate,
                icon: "repeat.circle.fill",
                tint: AppTheme.primaryAccent,
                subtitle: sub.nextBillingDate.formatted(date: .abbreviated, time: .omitted)
            ))
        }

        // Next debt payments this month
        let sortedDebts = activeDebts
            .sorted { $0.dueDay < $1.dueDay }
            .prefix(3)
        for debt in sortedDebts {
            var comps = cal.dateComponents([.year, .month], from: now)
            comps.day = debt.dueDay
            let dueDate = cal.date(from: comps) ?? now
            items.append(UpcomingItem(
                id: debt.id,
                name: debt.name,
                amount: debt.minimumPayment,
                date: dueDate,
                icon: "creditcard.fill",
                tint: AppTheme.warning,
                subtitle: dueDate.formatted(date: .abbreviated, time: .omitted)
            ))
        }

        return items.sorted { $0.date < $1.date }
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
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(AppTheme.outline.opacity(0.5), lineWidth: 1)
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
