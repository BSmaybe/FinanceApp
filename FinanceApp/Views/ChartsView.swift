import SwiftUI
import SwiftData
import Charts

// MARK: - AnalyticsPeriod

enum AnalyticsPeriod: String, CaseIterable {
    case week, month, year

    var title: String {
        switch self {
        case .week:  return String(localized: "Week")
        case .month: return String(localized: "Month")
        case .year:  return String(localized: "Year")
        }
    }
}

// MARK: - PeriodRange

struct PeriodRange {
    let start: Date
    let end: Date      // inclusive end (last second of the period)
    let label: String  // e.g. "Mar 2025", "W12", "2025"

    func contains(_ date: Date) -> Bool {
        date >= start && date <= end
    }
}

// MARK: - Period helpers

private func periodRange(for period: AnalyticsPeriod, offset: Int, from reference: Date = Date()) -> PeriodRange {
    let cal = Calendar.current
    switch period {
    case .week:
        // shift reference by `offset` weeks then get that week's interval
        let shifted = cal.date(byAdding: .weekOfYear, value: offset, to: reference) ?? reference
        let interval = cal.dateInterval(of: .weekOfYear, for: shifted)!
        let start = interval.start
        let end = cal.date(byAdding: .second, value: -1, to: interval.end) ?? interval.end
        let weekNum = cal.component(.weekOfYear, from: start)
        let year    = cal.component(.year, from: start)
        let label   = offset == 0 ? "W\(weekNum)" : (offset == -1 ? String(localized: "Previous") : "W\(weekNum) \(year)")
        return PeriodRange(start: start, end: end, label: label)

    case .month:
        let shifted = cal.date(byAdding: .month, value: offset, to: reference) ?? reference
        let comps   = cal.dateComponents([.year, .month], from: shifted)
        let start   = cal.date(from: comps)!
        let nextM   = cal.date(byAdding: .month, value: 1, to: start)!
        let end     = cal.date(byAdding: .second, value: -1, to: nextM)!
        let fmt     = DateFormatter()
        fmt.dateFormat = offset == 0 ? "MMM yyyy" : "MMM"
        // for last-year column (offset == -12) show short month + year abbrev
        if offset <= -12 {
            fmt.dateFormat = "MMM''yy"
        }
        return PeriodRange(start: start, end: end, label: fmt.string(from: start))

    case .year:
        let shifted   = cal.date(byAdding: .year, value: offset, to: reference) ?? reference
        let year      = cal.component(.year, from: shifted)
        var startComps = DateComponents(); startComps.year = year; startComps.month = 1; startComps.day = 1
        var endComps   = DateComponents(); endComps.year = year; endComps.month = 12; endComps.day = 31
        endComps.hour = 23; endComps.minute = 59; endComps.second = 59
        let start = cal.date(from: startComps)!
        let end   = cal.date(from: endComps)!
        return PeriodRange(start: start, end: end, label: "\(year)")
    }
}

/// The "same period last year" range
private func lastYearRange(for period: AnalyticsPeriod, from reference: Date = Date()) -> PeriodRange {
    switch period {
    case .week:
        return periodRange(for: .week, offset: -52, from: reference)
    case .month:
        return periodRange(for: .month, offset: -12, from: reference)
    case .year:
        return periodRange(for: .year, offset: -1, from: reference)
    }
}

/// The "previous period" range
private func previousRange(for period: AnalyticsPeriod, from reference: Date = Date()) -> PeriodRange {
    switch period {
    case .week:
        return periodRange(for: .week, offset: -1, from: reference)
    case .month:
        return periodRange(for: .month, offset: -1, from: reference)
    case .year:
        // previous year uses offset -1, but we want a distinct label
        let cal   = Calendar.current
        let y     = cal.component(.year, from: reference) - 1
        var sc    = DateComponents(); sc.year = y; sc.month = 1;  sc.day = 1
        var ec    = DateComponents(); ec.year = y; ec.month = 12; ec.day = 31
        ec.hour = 23; ec.minute = 59; ec.second = 59
        return PeriodRange(start: cal.date(from: sc)!, end: cal.date(from: ec)!, label: "\(y)")
    }
}

// MARK: - Comparison totals

private struct PeriodTotals {
    let income:  Decimal
    let expense: Decimal
    var net:     Decimal { income - expense }
}

private func totals(for range: PeriodRange, in transactions: [Transaction]) -> PeriodTotals {
    var income:  Decimal = .zero
    var expense: Decimal = .zero
    for txn in transactions {
        guard range.contains(txn.date) else { continue }
        if txn.type == .income  { income  += txn.amount }
        if txn.type == .expense { expense += txn.amount }
    }
    return PeriodTotals(income: income, expense: expense)
}

// MARK: - ChartsView

struct ChartsView: View {
    @Binding var selectedTab: AppRootTab
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query private var categories: [Category]
    @Query private var accounts: [Account]
    @Query private var budgets: [Budget]

    @State private var selectedPeriod: AnalyticsPeriod = .month

    private var calendar: Calendar { Calendar.current }

    private var postedTransactions: [Transaction] {
        BalanceCalculator.postedTransactions(transactions)
    }

    // Category lookup
    private var categoryMap: [UUID: Category] {
        Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
    }

    // MARK: Current period range

    private var currentRange: PeriodRange {
        periodRange(for: selectedPeriod, offset: 0)
    }

    // MARK: Period-filtered transactions

    private var periodTransactions: [Transaction] {
        postedTransactions.filter { currentRange.contains($0.date) }
    }

    // MARK: Comparison totals

    private var currentTotals: PeriodTotals {
        totals(for: currentRange, in: postedTransactions)
    }
    private var previousTotals: PeriodTotals {
        totals(for: previousRange(for: selectedPeriod), in: postedTransactions)
    }
    private var lastYearTotals: PeriodTotals {
        totals(for: lastYearRange(for: selectedPeriod), in: postedTransactions)
    }

    // MARK: Expenses grouped by category

    private func expensesByCategory(
        from txns: [Transaction]
    ) -> [(name: String, amount: Double, color: Color, iconName: String)] {
        let expenses = txns.filter { $0.type == .expense }
        var grouped: [UUID: Decimal] = [:]
        for txn in expenses {
            if let catId = txn.categoryId {
                grouped[catId, default: .zero] += txn.amount
            }
        }
        return grouped.compactMap { catId, total in
            guard let cat = categoryMap[catId] else { return nil }
            let dbl = NSDecimalNumber(decimal: total).doubleValue
            return (name: cat.name, amount: dbl, color: Color(hex: cat.colorHex), iconName: cat.iconName)
        }
        .sorted { $0.amount > $1.amount }
    }

    // MARK: Daily/weekly/monthly bar data

    private func barData(
        from txns: [Transaction]
    ) -> [(label: String, xIndex: Int, amount: Double)] {
        switch selectedPeriod {
        case .week:
            var grouped: [Int: Decimal] = [:]
            for txn in txns where txn.type == .expense {
                let wd = calendar.component(.weekday, from: txn.date)
                grouped[wd, default: .zero] += txn.amount
            }
            // Mon=2...Sun=1 in Gregorian; re-map to 1=Mon..7=Sun
            let dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
            return (1...7).map { i in
                let wd = (i % 7) + 1  // Mon=2,Tue=3,...,Sun=1
                let amt = NSDecimalNumber(decimal: grouped[wd] ?? .zero).doubleValue
                return (label: dayNames[i - 1], xIndex: i, amount: amt)
            }
        case .month:
            var grouped: [Int: Decimal] = [:]
            for txn in txns where txn.type == .expense {
                let day = calendar.component(.day, from: txn.date)
                grouped[day, default: .zero] += txn.amount
            }
            let daysInMonth = calendar.range(of: .day, in: .month, for: currentRange.start)?.count ?? 30
            return (1...daysInMonth).map { day in
                (label: "\(day)", xIndex: day,
                 amount: NSDecimalNumber(decimal: grouped[day] ?? .zero).doubleValue)
            }
        case .year:
            let fmt = DateFormatter(); fmt.dateFormat = "MMM"
            var grouped: [Int: Decimal] = [:]
            for txn in txns where txn.type == .expense {
                let m = calendar.component(.month, from: txn.date)
                grouped[m, default: .zero] += txn.amount
            }
            return (1...12).map { m in
                var c = DateComponents(); c.year = calendar.component(.year, from: currentRange.start); c.month = m; c.day = 1
                let d = calendar.date(from: c) ?? currentRange.start
                return (label: fmt.string(from: d), xIndex: m,
                        amount: NSDecimalNumber(decimal: grouped[m] ?? .zero).doubleValue)
            }
        }
    }

    // MARK: Monthly totals (last 6 months — for Savings Rate + Income vs Expense bar)

    private var monthlyTotals: [(month: Date, income: Double, expense: Double)] {
        let now = Date()
        var result: [(month: Date, income: Double, expense: Double)] = []
        for offset in (0..<6).reversed() {
            guard let monthDate = calendar.date(byAdding: .month, value: -offset, to: now) else { continue }
            let comps = calendar.dateComponents([.year, .month], from: monthDate)
            let monthStart = calendar.date(from: comps) ?? monthDate
            var income: Decimal = .zero
            var expense: Decimal = .zero
            for txn in postedTransactions {
                let tc = calendar.dateComponents([.year, .month], from: txn.date)
                if tc.year == comps.year && tc.month == comps.month {
                    if txn.type == .income  { income  += txn.amount }
                    else if txn.type == .expense { expense += txn.amount }
                }
            }
            result.append((month: monthStart,
                           income:  NSDecimalNumber(decimal: income).doubleValue,
                           expense: NSDecimalNumber(decimal: expense).doubleValue))
        }
        return result
    }

    // MARK: Yearly totals (12 months of selected year)

    private var yearlyMonthTotals: [(month: Date, income: Double, expense: Double)] {
        let year = calendar.component(.year, from: currentRange.start)
        var result: [(month: Date, income: Double, expense: Double)] = []
        for m in 1...12 {
            var comps = DateComponents(); comps.year = year; comps.month = m; comps.day = 1
            let monthStart = calendar.date(from: comps)!
            var income: Decimal = .zero
            var expense: Decimal = .zero
            for txn in postedTransactions {
                let tc = calendar.dateComponents([.year, .month], from: txn.date)
                if tc.year == year && tc.month == m {
                    if txn.type == .income  { income  += txn.amount }
                    else if txn.type == .expense { expense += txn.amount }
                }
            }
            result.append((month: monthStart,
                           income:  NSDecimalNumber(decimal: income).doubleValue,
                           expense: NSDecimalNumber(decimal: expense).doubleValue))
        }
        return result
    }

    // Income vs Expense data for the currently selected period
    private var incomeExpenseBarData: [(month: Date, income: Double, expense: Double)] {
        switch selectedPeriod {
        case .week, .month:
            return monthlyTotals
        case .year:
            return yearlyMonthTotals
        }
    }

    private var shortMonthFormatter: DateFormatter {
        let f = DateFormatter(); f.dateFormat = "MMM"; return f
    }

    // MARK: - body

    var body: some View {
        let txns           = periodTransactions
        let catExpenses    = expensesByCategory(from: txns)
        let bars           = barData(from: txns)
        let hasExpenses    = txns.contains { $0.type == .expense }
        let incExpData     = incomeExpenseBarData
        let savingsRates   = savingsRateData(from: monthlyTotals)
        let trendData      = netWorthTrendData
        let budgetActual   = budgetVsActualData(monthTransactions: periodTransactions)

        return NavigationStack {
            ZStack {
                AppTheme.canvas
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        analyticsHeroCard
                        groupHeader(
                            title: String(localized: "Compare"),
                            subtitle: compareSectionTakeaway
                        )
                        periodPicker
                        periodComparisonCard
                        budgetVsActualChart(data: budgetActual)

                        groupHeader(
                            title: String(localized: "Trends"),
                            subtitle: trendsSectionTakeaway(expensesByCategory: catExpenses, netWorthTrendData: trendData)
                        )
                        categoryPieChart(expensesByCategory: catExpenses)
                        topSpendingChart(expensesByCategory: catExpenses)
                        dailyExpenseChart(hasExpenses: hasExpenses, barData: bars)
                        monthlyBarChart(monthlyTotals: incExpData)
                        savingsRateChart(savingsRateData: savingsRates)
                        netWorthTrendChart(netWorthTrendData: trendData)

                        groupHeader(
                            title: String(localized: "Planning"),
                            subtitle: String(localized: "Explore scenarios and review longer horizons")
                        )
                        planningCards
                    }
                    .padding(16)
                }
            }
            .navigationTitle(String(localized: "Analytics"))
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(AppTheme.surface, for: .navigationBar)
        }
    }

    // MARK: - Period Picker

    private var periodPicker: some View {
        Picker(String(localized: "Period"), selection: $selectedPeriod) {
            ForEach(AnalyticsPeriod.allCases, id: \.self) { p in
                Text(p.title).tag(p)
            }
        }
        .pickerStyle(.segmented)
        .padding(12)
        .cockpitSurface(cornerRadius: 20, elevated: true, compact: true)
    }

    private var analyticsHeroCard: some View {
        HeroMetricCard(
            title: String(localized: "Analytics"),
            value: currentRange.label,
            supportingTitle: String(localized: "Net"),
            supportingValue: CurrencyFormatter.string(from: currentTotals.net),
            note: selectedPeriod.title,
            badgeText: compareBadgeText
        )
    }

    private func groupHeader(title: String, subtitle: String) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 2)
    }

    private var compareBadgeText: String {
        let delta = currentTotals.net - previousTotals.net
        let prefix = delta >= 0 ? "+" : "-"
        return "\(prefix)\(CurrencyFormatter.string(from: abs(delta)))"
    }

    private var compareSectionTakeaway: String {
        if currentTotals.net == previousTotals.net {
            return String(localized: "Current period is tracking in line with the previous period.")
        }
        let stronger = currentTotals.net > previousTotals.net
        let diff = abs(currentTotals.net - previousTotals.net)
        return stronger
            ? String(format: String(localized: "Net is up by %@ versus the prior comparable period."), CurrencyFormatter.string(from: diff))
            : String(format: String(localized: "Net is down by %@ versus the prior comparable period."), CurrencyFormatter.string(from: diff))
    }

    private func trendsSectionTakeaway(
        expensesByCategory: [(name: String, amount: Double, color: Color, iconName: String)],
        netWorthTrendData: [(month: String, date: Date, balance: Double)]
    ) -> String {
        let topCategory = expensesByCategory.first?.name ?? String(localized: "No category")
        let delta = (netWorthTrendData.last?.balance ?? 0) - (netWorthTrendData.dropLast().last?.balance ?? 0)
        let direction = delta >= 0 ? String(localized: "up") : String(localized: "down")
        return String(format: String(localized: "Top spending is %@ and net worth is %@ month over month."), topCategory, direction)
    }

    private var planningCards: some View {
        VStack(spacing: 12) {
            NavigationLink(destination: WhatIfView()) {
                InsightCard(
                    title: String(localized: "What If"),
                    value: String(localized: "Scenarios"),
                    message: String(localized: "Test savings, spending, and debt payoff decisions before acting."),
                    systemImage: "questionmark.circle.fill",
                    tint: AppTheme.secondaryAccent
                )
            }
            .buttonStyle(.plain)

            NavigationLink(destination: YearlyOverviewView()) {
                InsightCard(
                    title: String(localized: "Yearly Overview"),
                    value: String(localized: "12 Months"),
                    message: String(localized: "Review full-year cash flow, savings rate, and category concentration."),
                    systemImage: "calendar.badge.clock",
                    tint: AppTheme.primaryAccent
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func analyticsCard<Content: View>(
        title: String,
        takeaway: String,
        actionTitle: String,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(takeaway)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(actionTitle, action: action)
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.primaryAccent)
            }
            content()
        }
        .cockpitSurface(cornerRadius: 24, elevated: true)
    }

    // MARK: - Period Comparison Card

    private var periodComparisonCard: some View {
        let prev    = previousRange(for: selectedPeriod)
        let ly      = lastYearRange(for: selectedPeriod)
        let curT    = currentTotals
        let prevT   = previousTotals
        let lyT     = lastYearTotals

        return analyticsCard(
            title: String(localized: "Period Comparison"),
            takeaway: compareSectionTakeaway,
            actionTitle: String(localized: "Open Dashboard"),
            action: { selectedTab = .dashboard }
        ) {
            HStack {
                Text("").frame(maxWidth: .infinity, alignment: .leading)
                Text(currentRange.label)
                    .font(.caption.bold())
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Text(prev.label)
                    .font(.caption.bold())
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Text(ly.label)
                    .font(.caption.bold())
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .foregroundStyle(.secondary)

            Divider()

            comparisonRow(
                label: String(localized: "Income"),
                cur: curT.income,
                prev: prevT.income,
                ly: lyT.income,
                isNegativeWorse: false
            )
            comparisonRow(
                label: String(localized: "Expenses"),
                cur: curT.expense,
                prev: prevT.expense,
                ly: lyT.expense,
                isNegativeWorse: false
            )

            Divider()

            HStack {
                Text(String(localized: "Net"))
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)
                netValueText(curT.net)
                netValueText(prevT.net)
                netValueText(lyT.net)
            }
        }
    }

    @ViewBuilder
    private func comparisonRow(
        label: String,
        cur: Decimal,
        prev: Decimal,
        ly: Decimal,
        isNegativeWorse: Bool
    ) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(CurrencyFormatter.string(from: cur))
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text(CurrencyFormatter.string(from: prev))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text(CurrencyFormatter.string(from: ly))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func netValueText(_ value: Decimal) -> some View {
        Text(CurrencyFormatter.string(from: value))
            .font(.subheadline.bold())
            .foregroundStyle(value >= 0 ? AppTheme.success : AppTheme.danger)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    // MARK: - Category Pie Chart

    private func categoryPieChart(
        expensesByCategory: [(name: String, amount: Double, color: Color, iconName: String)]
    ) -> some View {
        analyticsCard(
            title: String(localized: "Expenses by Category"),
            takeaway: categoryTakeaway(expensesByCategory),
            actionTitle: String(localized: "Open Transactions"),
            action: { selectedTab = .transactions }
        ) {
            if expensesByCategory.isEmpty {
                Text(String(localized: "No expenses this month"))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                Chart(expensesByCategory, id: \.name) { item in
                    SectorMark(
                        angle: .value("Amount", item.amount),
                        innerRadius: .ratio(0.6),
                        angularInset: 1.5
                    )
                    .foregroundStyle(item.color)
                    .cornerRadius(4)
                }
                .frame(height: 220)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(expensesByCategory, id: \.name) { item in
                        HStack(spacing: 6) {
                            Image(systemName: item.iconName)
                                .font(.caption2)
                                .foregroundStyle(item.color)
                                .frame(width: 20, height: 20)
                                .background(item.color.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            Text(item.name)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Text(CurrencyFormatter.string(from: Decimal(item.amount)))
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Daily/Weekly/Monthly Expense Bar Chart

    private func dailyExpenseChart(
        hasExpenses: Bool,
        barData: [(label: String, xIndex: Int, amount: Double)]
    ) -> some View {
        let chartTitle: String = {
            switch selectedPeriod {
            case .week:  return String(localized: "Daily Expenses")
            case .month: return String(localized: "Daily Expenses")
            case .year:  return String(localized: "Monthly Expenses")
            }
        }()

        return analyticsCard(
            title: chartTitle,
            takeaway: expenseBarTakeaway(hasExpenses: hasExpenses, barData: barData),
            actionTitle: String(localized: "Open Transactions"),
            action: { selectedTab = .transactions }
        ) {
            if !hasExpenses {
                Text(String(localized: "No expenses this month"))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                Chart(barData, id: \.xIndex) { item in
                    BarMark(
                        x: .value("Label", item.label),
                        y: .value("Amount", item.amount)
                    )
                    .foregroundStyle(Color.orange.gradient)
                    .cornerRadius(2)
                }
                .frame(height: 150)
                .chartXAxis {
                    if selectedPeriod == .month {
                        AxisMarks(values: .stride(by: 5)) { _ in AxisValueLabel() }
                    } else {
                        AxisMarks { _ in AxisValueLabel() }
                    }
                }
            }
        }
    }

    // MARK: - Income vs Expenses Bar Chart

    private func monthlyBarChart(
        monthlyTotals: [(month: Date, income: Double, expense: Double)]
    ) -> some View {
        analyticsCard(
            title: String(localized: "Income vs Expenses"),
            takeaway: incomeVsExpenseTakeaway(monthlyTotals),
            actionTitle: String(localized: "Open Dashboard"),
            action: { selectedTab = .dashboard }
        ) {
            if monthlyTotals.allSatisfy({ $0.income == 0 && $0.expense == 0 }) {
                Text(String(localized: "No transactions yet"))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                Chart {
                    ForEach(monthlyTotals, id: \.month) { item in
                        BarMark(
                            x: .value("Month", shortMonthFormatter.string(from: item.month)),
                            y: .value("Amount", item.income)
                        )
                        .foregroundStyle(Color.green)
                        .position(by: .value("Type", String(localized: "Income")))

                        BarMark(
                            x: .value("Month", shortMonthFormatter.string(from: item.month)),
                            y: .value("Amount", item.expense)
                        )
                        .foregroundStyle(Color.red)
                        .position(by: .value("Type", String(localized: "Expense")))
                    }
                }
                .frame(height: 220)
                .chartForegroundStyleScale([
                    String(localized: "Income"): Color.green,
                    String(localized: "Expense"): Color.red
                ])
            }
        }
    }

    // MARK: - Savings Rate Chart (last 6 months — always)

    private func savingsRateData(
        from monthlyTotals: [(month: Date, income: Double, expense: Double)]
    ) -> [(month: String, rate: Double)] {
        monthlyTotals.map { item in
            let rate: Double = item.income > 0
                ? (item.income - item.expense) / item.income * 100
                : 0
            return (month: shortMonthFormatter.string(from: item.month), rate: rate)
        }
    }

    private func savingsRateChart(
        savingsRateData: [(month: String, rate: Double)]
    ) -> some View {
        analyticsCard(
            title: String(localized: "Savings Rate"),
            takeaway: savingsRateTakeaway(savingsRateData),
            actionTitle: String(localized: "Review Year"),
            action: { selectedPeriod = .year }
        ) {
            if savingsRateData.allSatisfy({ $0.rate == 0 }) {
                Text(String(localized: "No income data yet"))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                Chart(savingsRateData, id: \.month) { item in
                    BarMark(
                        x: .value("Month", item.month),
                        y: .value("Rate", item.rate)
                    )
                    .foregroundStyle(item.rate >= 0 ? Color.green.gradient : Color.red.gradient)
                    .cornerRadius(4)
                }
                .frame(height: 180)
                .chartYAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text("\(Int(v))%")
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Top Spending

    private func topSpendingChart(
        expensesByCategory: [(name: String, amount: Double, color: Color, iconName: String)]
    ) -> some View {
        let top5 = Array(expensesByCategory.prefix(5))
        return analyticsCard(
            title: String(localized: "Top Spending"),
            takeaway: topSpendingTakeaway(top5),
            actionTitle: String(localized: "Open Transactions"),
            action: { selectedTab = .transactions }
        ) {
            if top5.isEmpty {
                Text(String(localized: "No expenses this month"))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                Chart(top5, id: \.name) { item in
                    BarMark(
                        x: .value("Amount", item.amount),
                        y: .value("Category", item.name)
                    )
                    .foregroundStyle(item.color)
                    .cornerRadius(4)
                    .annotation(position: .trailing) {
                        Text(CurrencyFormatter.string(from: Decimal(item.amount)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: CGFloat(top5.count) * 44)
                .chartYAxis {
                    AxisMarks { _ in AxisValueLabel() }
                }
            }
        }
    }

    // MARK: - Net Worth Trend (always last 12 months)

    private var netWorthTrendData: [(month: String, date: Date, balance: Double)] {
        let now = Date()
        var result: [(month: String, date: Date, balance: Double)] = []
        for offset in (0..<12).reversed() {
            guard let monthDate = calendar.date(byAdding: .month, value: -offset, to: now) else { continue }
            let comps      = calendar.dateComponents([.year, .month], from: monthDate)
            let monthStart = calendar.date(from: comps) ?? monthDate
            let nextMonth  = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
            let endOfMonth = calendar.date(byAdding: .second, value: -1, to: nextMonth) ?? monthStart

            let netWorth: Decimal = accounts.reduce(.zero) { sum, account in
                sum + BalanceCalculator.balance(for: account, in: postedTransactions, asOf: endOfMonth)
            }
            result.append((
                month:   shortMonthFormatter.string(from: monthStart),
                date:    monthStart,
                balance: NSDecimalNumber(decimal: netWorth).doubleValue
            ))
        }
        return result
    }

    private func netWorthTrendChart(
        netWorthTrendData: [(month: String, date: Date, balance: Double)]
    ) -> some View {
        let last      = netWorthTrendData.last?.balance ?? 0
        let prev      = netWorthTrendData.dropLast().last?.balance ?? last
        let delta     = last - prev
        let isPositive = delta >= 0

        return analyticsCard(
            title: String(localized: "Net Worth History"),
            takeaway: netWorthTakeaway(delta: delta, isPositive: isPositive),
            actionTitle: String(localized: "Open Dashboard"),
            action: { selectedTab = .dashboard }
        ) {
            if netWorthTrendData.allSatisfy({ $0.balance == 0 }) {
                Text(String(localized: "No transactions yet"))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                Chart(netWorthTrendData, id: \.month) { item in
                    LineMark(
                        x: .value("Month", item.month),
                        y: .value("Balance", item.balance)
                    )
                    .foregroundStyle(AppTheme.primaryAccent)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .symbol(Circle().strokeBorder(lineWidth: 2))

                    AreaMark(
                        x: .value("Month", item.month),
                        y: .value("Balance", item.balance)
                    )
                    .foregroundStyle(AppTheme.primaryAccent.opacity(0.10))
                }
                .frame(height: 200)
            }
        }
    }

    private func categoryTakeaway(
        _ expensesByCategory: [(name: String, amount: Double, color: Color, iconName: String)]
    ) -> String {
        guard let first = expensesByCategory.first else {
            return String(localized: "No category has meaningfully emerged in this period yet.")
        }
        return String(format: String(localized: "%@ is currently the largest expense bucket."), first.name)
    }

    private func expenseBarTakeaway(
        hasExpenses: Bool,
        barData: [(label: String, xIndex: Int, amount: Double)]
    ) -> String {
        guard hasExpenses, let peak = barData.max(by: { $0.amount < $1.amount }) else {
            return String(localized: "No spend trend is available for the selected period.")
        }
        return String(format: String(localized: "The highest spend point lands on %@."), peak.label)
    }

    private func incomeVsExpenseTakeaway(
        _ monthlyTotals: [(month: Date, income: Double, expense: Double)]
    ) -> String {
        guard let latest = monthlyTotals.last else {
            return String(localized: "Income and expense history will appear here once transactions exist.")
        }
        let net = latest.income - latest.expense
        let direction = net >= 0 ? String(localized: "ahead") : String(localized: "behind")
        return String(format: String(localized: "The latest period closes %@ by %@."), direction, CurrencyFormatter.string(from: Decimal(abs(net))))
    }

    private func savingsRateTakeaway(
        _ savingsRateData: [(month: String, rate: Double)]
    ) -> String {
        guard let latest = savingsRateData.last else {
            return String(localized: "Savings trend will appear once income is recorded.")
        }
        return String(format: String(localized: "Latest savings rate is %.1f%%."), latest.rate)
    }

    private func topSpendingTakeaway(
        _ top5: [(name: String, amount: Double, color: Color, iconName: String)]
    ) -> String {
        guard let first = top5.first else {
            return String(localized: "Top spending categories will appear once expenses are logged.")
        }
        return String(format: String(localized: "%@ leads current spend ranking."), first.name)
    }

    private func netWorthTakeaway(delta: Double, isPositive: Bool) -> String {
        guard delta != 0 else {
            return String(localized: "Net worth is flat versus the previous month.")
        }
        let direction = isPositive ? String(localized: "up") : String(localized: "down")
        return String(format: String(localized: "Net worth is %@ by %@ month over month."), direction, CurrencyFormatter.string(from: Decimal(abs(delta))))
    }

    private func budgetTakeaway(
        _ data: [(category: String, budget: Double, actual: Double, color: Color)]
    ) -> String {
        let overspent = data.filter { $0.actual > $0.budget }.count
        if overspent == 0 {
            return String(localized: "Every tracked budget category remains within plan.")
        }
        return String(format: String(localized: "%lld categories are currently over budget."), overspent)
    }

    // MARK: - Budget vs Actual (always uses current calendar month)

    private func budgetVsActualData(
        monthTransactions: [Transaction]
    ) -> [(category: String, budget: Double, actual: Double, color: Color)] {
        let refDate    = selectedPeriod == .month ? currentRange.start : Date()
        let comps      = calendar.dateComponents([.year, .month], from: refDate)
        let expenseCats = categories.filter { $0.type == .expense }
        let s = Dictionary(
            grouping: monthTransactions.filter { $0.type == .expense },
            by: { $0.categoryId }
        )
        return expenseCats.compactMap { cat in
            let b = budgets.first {
                $0.categoryId == cat.id &&
                $0.month == (comps.month ?? 1) &&
                $0.year  == (comps.year  ?? 2025)
            }
            guard let b, b.limitAmount > 0 else { return nil }
            let spent = (s[cat.id] ?? []).reduce(Decimal.zero) { $0 + $1.amount }
            return (
                category: cat.name,
                budget:   NSDecimalNumber(decimal: b.limitAmount).doubleValue,
                actual:   NSDecimalNumber(decimal: spent).doubleValue,
                color:    Color(hex: cat.colorHex)
            )
        }
    }

    @ViewBuilder
    private func budgetVsActualChart(
        data: [(category: String, budget: Double, actual: Double, color: Color)]
    ) -> some View {
        if !data.isEmpty {
            analyticsCard(
                title: String(localized: "Budget vs Actual"),
                takeaway: budgetTakeaway(data),
                actionTitle: String(localized: "Open Dashboard"),
                action: { selectedTab = .dashboard }
            ) {
                Chart {
                    ForEach(data, id: \.category) { item in
                        BarMark(
                            x: .value("Category", item.category),
                            y: .value("Amount", item.budget)
                        )
                        .foregroundStyle(Color.blue.opacity(0.3))
                        .position(by: .value("Type", String(localized: "Budget")))

                        BarMark(
                            x: .value("Category", item.category),
                            y: .value("Amount", item.actual)
                        )
                        .foregroundStyle(item.actual > item.budget ? Color.red : item.color)
                        .position(by: .value("Type", String(localized: "Actual")))
                    }
                }
                .frame(height: 220)
                .chartForegroundStyleScale([
                    String(localized: "Budget"): Color.blue.opacity(0.3),
                    String(localized: "Actual"): Color.orange
                ])
            }
        }
    }
}
