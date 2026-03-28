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
    @State private var showingCaptureScanner = false
    @State private var scannerErrorMessage: String?
    @State private var quickAddCapturePayload: PendingCapturePayload?

    // B4: Swipe hint (shown once)
    @AppStorage("dash.swipeHintShown") private var swipeHintShown = false
    @State private var showSwipeHint = false
    @State private var expandedAccounts = true
    @State private var expandedBudgets = false
    @State private var expandedDebts = false
    @State private var expandedUpcoming = false
    @State private var expandedActivity = false

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
        let budgetPressures = budgetPressureList(
            stats: dashboardStats,
            expenseCategories: expenseCategoriesList,
            current: current,
            previousMonth: previousMonth
        )

        return NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(hex: "#284867"), Color(hex: "#1B3552"), Color(hex: "#162C46")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        heroReferenceSection(
                            netWorth: netWorthValue,
                            freeToSpend: freeToSpendValue,
                            monthlyIncome: dashboardStats.monthlyIncome,
                            monthlyExpense: dashboardStats.monthlyExpense
                        )
                        .accessibilityIdentifier("dashboard.hero.section")

                        if accounts.isEmpty {
                            emptyAccountsCard
                                .accessibilityIdentifier("dashboard.accounts.empty")
                        } else {
                            accountsScrollSection(balances: dashboardStats.netWorthByAccount)
                                .accessibilityIdentifier("dashboard.accounts.section")
                        }

                        if showQuickActions {
                            actionRailSection
                                .accessibilityIdentifier("dashboard.primaryActions.section")
                        }

                        if showRecentActivity {
                            latestTransactionReferenceSection(
                                recentTransactions: recentTransactionsList,
                                categoryById: categoryById
                            )
                            .accessibilityIdentifier("dashboard.recentActivity.section")
                        }

                        if showThisMonth {
                            insightsReferenceSection(budgetPressures: budgetPressures)
                                .accessibilityIdentifier("dashboard.thisMonth.section")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 24)
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
            .sheet(isPresented: $showingForecast) {
                CashFlowForecastView()
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

    // MARK: - Reference Redesign Sections

    private func heroReferenceSection(
        netWorth: Decimal,
        freeToSpend: Decimal,
        monthlyIncome: Decimal,
        monthlyExpense: Decimal
    ) -> some View {
        let monthNet = monthlyIncome - monthlyExpense
        let trendTint: Color = monthNet >= 0 ? Color(hex: "#9BFF3A") : AppTheme.danger
        let trendValues = heroTrendValues(
            income: monthlyIncome,
            expense: monthlyExpense
        )
        let percentText: String = {
            guard monthlyIncome > 0 else { return "" }
            let pct = NSDecimalNumber(decimal: (monthNet / monthlyIncome) * 100).doubleValue
            let sign = pct >= 0 ? "+" : ""
            return "\(sign)\(String(format: "%.1f", pct))%"
        }()

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "👋 Hi"))
                        .font(.system(size: 27, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(Date().formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                Button {
                    HapticManager.impact(.light)
                    showingDashboardSettings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .frame(width: 34, height: 34)
                        .background(.white.opacity(0.14))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("dashboard.openLayoutSettings")
            }

            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "Funds"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.7))
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(CurrencyFormatter.string(from: netWorth))
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.44)
                            .allowsTightening(true)
                        if !percentText.isEmpty {
                            Text(percentText)
                                .font(.headline.weight(.bold))
                                .foregroundStyle(trendTint)
                        }
                    }
                    Text(
                        String(
                            format: String(localized: "Free to spend: %@"),
                            CurrencyFormatter.string(from: freeToSpend)
                        )
                    )
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
                }

                Spacer(minLength: 8)

                SparklineView(values: trendValues, tint: trendTint, showArea: true)
                    .frame(width: 132, height: 72)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.black.opacity(0.2))
                    )
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "#203A57"), Color(hex: "#162B43")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.28), radius: 18, x: 0, y: 8)
        )
    }

    private var actionRailSection: some View {
        HStack(spacing: 0) {
            actionRailItem(
                icon: "creditcard",
                label: String(localized: "Payment")
            ) {
                quickAddCapturePayload = nil
                showingQuickAdd = true
            }

            actionRailItem(
                icon: "clock.arrow.circlepath",
                label: String(localized: "History")
            ) {
                selectedTab = .transactions
            }

            actionRailItem(
                icon: "building.columns",
                label: String(localized: "Account")
            ) {
                selectedTab = .accounts
            }

            actionRailItem(
                icon: "qrcode.viewfinder",
                label: String(localized: "Scan QR")
            ) {
                showingCaptureScanner = true
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(hex: "#B98CFF"))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(.white.opacity(0.22), lineWidth: 1)
                )
                .shadow(color: Color(hex: "#B98CFF").opacity(0.34), radius: 14, x: 0, y: 6)
        )
    }

    private func actionRailItem(
        icon: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .frame(height: 24)
                Text(label)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(Color(hex: "#1F1633"))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    private func latestTransactionReferenceSection(
        recentTransactions: [Transaction],
        categoryById: [UUID: Category]
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(String(localized: "Latest transaction"))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.95))
                Spacer()
                Button(String(localized: "See all")) {
                    selectedTab = .transactions
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(hex: "#B98CFF"))
                .buttonStyle(.plain)
                .accessibilityIdentifier("dashboard.recentActivity.openTransactions")
            }

            if let txn = recentTransactions.first {
                latestTransactionReferenceRow(txn, categoryById: categoryById)
            } else {
                Button {
                    showingQuickAdd = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color(hex: "#7EE787"))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(String(localized: "No transactions yet"))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.9))
                            Text(String(localized: "Tap to add your first transaction"))
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.62))
                        }
                        Spacer()
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color(hex: "#233A56"))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(.white.opacity(0.08), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 2)
    }

    private func latestTransactionReferenceRow(
        _ txn: Transaction,
        categoryById: [UUID: Category]
    ) -> some View {
        let category = txn.categoryId.flatMap { categoryById[$0] }
        let tint: Color = {
            switch txn.type {
            case .income: return Color(hex: "#7EE787")
            case .expense: return Color(hex: "#FF8A80")
            case .transfer: return Color(hex: "#8EDBFF")
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
                    .foregroundStyle(.white.opacity(0.94))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text("\(sign) \(CurrencyFormatter.string(from: txn.amount))")
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(tint)
                .lineLimit(1)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(hex: "#233A56"))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func insightsReferenceSection(budgetPressures: [BudgetRisk]) -> some View {
        let topRisk = budgetPressures.first
        let topRiskPercent = Int((topRisk?.ratio ?? 0) * 100)
        let monthlyBills = activeSubscriptions.reduce(Decimal.zero) { $0 + $1.amount } +
            activeDebts.reduce(Decimal.zero) { $0 + $1.minimumPayment }

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(String(localized: "Insights"))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.95))
                Spacer()
                Button(String(localized: "See all")) {
                    selectedTab = .analytics
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(hex: "#B98CFF"))
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    Button {
                        showingBudgetManager = true
                    } label: {
                        insightReferenceCard(
                            badge: String(localized: "SPENDING"),
                            icon: topRisk?.category.iconName ?? "chart.pie.fill",
                            headline: topRisk == nil ? String(localized: "No budgets yet") : "\(topRiskPercent)%",
                            message: topRisk == nil
                                ? String(localized: "Create budgets to track monthly pressure")
                                : String(
                                    format: String(localized: "You reached %lld%% of %@ budget"),
                                    Int64(max(0, topRiskPercent)),
                                    topRisk?.category.name ?? ""
                                ),
                            background: Color(hex: "#F6D94C"),
                            foreground: Color(hex: "#2F2A12")
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("dashboard.thisMonth.openBudgets")

                    Button {
                        if featureSubscriptions {
                            showingSubscriptions = true
                        } else if featureDebts {
                            showingDebts = true
                        }
                    } label: {
                        insightReferenceCard(
                            badge: String(localized: "BILLS"),
                            icon: "waveform.path.ecg",
                            headline: CurrencyFormatter.string(from: monthlyBills),
                            message: String(
                                format: String(localized: "%lld active bills this month"),
                                Int64(activeSubscriptions.count + activeDebts.count)
                            ),
                            background: Color(hex: "#C699FF"),
                            foreground: Color(hex: "#26183A")
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        selectedTab = .analytics
                    } label: {
                        insightReferenceCard(
                            badge: String(localized: "PLANNING"),
                            icon: "target",
                            headline: "\(activeGoals.count)",
                            message: activeGoals.isEmpty
                                ? String(localized: "Create your first goal")
                                : String(
                                    format: String(localized: "%lld goals in progress"),
                                    Int64(activeGoals.count)
                                ),
                            background: Color(hex: "#79E6B2"),
                            foreground: Color(hex: "#103126")
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 1)
            }
        }
        .padding(.top, 2)
    }

    private func insightReferenceCard(
        badge: String,
        icon: String,
        headline: String,
        message: String,
        background: Color,
        foreground: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(badge)
                .font(.caption.weight(.bold))
                .tracking(1.3)
                .foregroundStyle(foreground.opacity(0.55))

            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: 36, height: 36)
                .background(.white.opacity(0.72))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 6) {
                Text(headline)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Text(message)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(foreground.opacity(0.95))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
        .frame(width: 182, height: 178, alignment: .topLeading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(background)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(.white.opacity(0.35), lineWidth: 1)
                )
        )
    }

    private var commitmentsCompactSection: some View {
        let subscriptionTotal = activeSubscriptions.reduce(Decimal.zero) { $0 + $1.amount }
        let debtTotal = activeDebts.reduce(Decimal.zero) { $0 + $1.remainingAmount }

        return VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Commitments"))
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white.opacity(0.95))

            HStack(spacing: 10) {
                if featureSubscriptions {
                    commitmentMiniCard(
                        title: String(localized: "Subscriptions"),
                        value: CurrencyFormatter.string(from: subscriptionTotal),
                        subtitle: "\(activeSubscriptions.count)",
                        icon: "repeat",
                        tint: Color(hex: "#B98CFF")
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
                        tint: Color(hex: "#FF9D66")
                    ) {
                        showingDebts = true
                    }
                }

                if featureGoals {
                    commitmentMiniCard(
                        title: String(localized: "Goals"),
                        value: "\(activeGoals.count)",
                        subtitle: String(localized: "in progress"),
                        icon: "flag.checkered",
                        tint: Color(hex: "#7EE787")
                    ) {
                        showingGoals = true
                    }
                }
            }
        }
        .padding(.top, 2)
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
                    .foregroundStyle(.white.opacity(0.93))
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(hex: "#223650"))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(.white.opacity(0.08), lineWidth: 1)
                    )
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

    // B3: Empty state when user has no accounts yet
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
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.outline.opacity(0.4), lineWidth: 0.5)
        )
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

    private func accountsScrollSection(balances: [UUID: Decimal]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(String(localized: "Accounts"))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.95))
                Spacer()
                Button(String(localized: "See all")) {
                    selectedTab = .accounts
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(hex: "#B98CFF"))
                .buttonStyle(.plain)
            }

    private func collapsibleSection<Content: View>(
        title: String,
        summary: String,
        expanded: Binding<Bool>,
        accessibilityId: String = "",
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    expanded.wrappedValue.toggle()
                }
                HapticManager.impact(.light)
            } label: {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    if !expanded.wrappedValue {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded.wrappedValue ? 90 : 0))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded.wrappedValue {
                Divider()
                    .padding(.horizontal, 14)
                content()
                    .padding(12)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AppTheme.outline.opacity(0.4), lineWidth: 0.5)
                )
        )
        .accessibilityIdentifier(accessibilityId)
    }

    // MARK: - Section Summary Strings

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

    private var debtsSummaryText: String {
        let total = activeDebts.reduce(Decimal.zero) { $0 + $1.remainingAmount }
        return "\(NumberAbbreviator.string(from: total)) · \(activeDebts.count)"
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

    // MARK: - Accounts Scroll

    private func accountsScrollContent(balances: [UUID: Decimal]) -> some View {
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

    // MARK: - Feature Shortcuts Row

    private var featureShortcutsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                if featureGoals {
                    shortcutChip(icon: "target", label: String(localized: "Goals")) { showingGoals = true }
                }
                if featureDebts {
                    shortcutChip(icon: "creditcard.fill", label: String(localized: "Debts")) { showingDebts = true }
                }
                if featureSubscriptions {
                    shortcutChip(icon: "repeat", label: String(localized: "Subscriptions")) { showingSubscriptions = true }
                }
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

    private func budgetRingsContent(budgetPressures: [BudgetRisk]) -> some View {
        let topRisks = Array(budgetPressures.prefix(4))
        return VStack(spacing: 12) {
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
            Button {
                showingBudgetManager = true
            } label: {
                Text(String(localized: "All Budgets"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryAccent)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .buttonStyle(.plain)
        }
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

    private var debtsSummaryContent: some View {
        let totalRemaining = activeDebts.reduce(Decimal.zero) { $0 + $1.remainingAmount }
        let totalMonthly   = activeDebts.reduce(Decimal.zero) { $0 + $1.minimumPayment }

        return VStack(alignment: .trailing, spacing: 8) {
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
            Button {
                showingDebts = true
            } label: {
                Text(String(localized: "View All"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryAccent)
            }
            .buttonStyle(.plain)
        }
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

    @ViewBuilder
    private var upcomingPaymentsContent: some View {
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

    private func recentActivityContent(
        recentTransactions: [Transaction],
        categoryById: [UUID: Category]
    ) -> some View {
        VStack(spacing: 2) {
            if recentTransactions.isEmpty && transactions.isEmpty && accounts.isEmpty {
                ForEach(0..<3, id: \.self) { _ in
                    SkeletonTransactionRow()
                }
            } else if recentTransactions.isEmpty {
                Text(String(localized: "No recent activity"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                ForEach(recentTransactions.prefix(5)) { txn in
                    recentTransactionRow(txn, categoryById: categoryById)
                    if txn.id != recentTransactions.prefix(5).last?.id {
                        Divider()
                            .padding(.leading, 58)
                    }
                }
            }
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { selectedTab = .transactions }
            } label: {
                Text(String(localized: "View All"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryAccent)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            .accessibilityIdentifier("dashboard.recentActivity.openTransactions")
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
