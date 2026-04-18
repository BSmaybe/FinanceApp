import SwiftUI
import SwiftData
import Charts

private struct MonthStats {
    let month: Int
    let income: Decimal
    let expense: Decimal
    var net: Decimal { income - expense }
}

struct YearlyOverviewView: View {
    @Query(sort: \Transaction.date, order: .reverse) private var allTransactions: [Transaction]
    @Query private var categories: [Category]

    @State private var year: Int

    private let currentYear: Int = Calendar.current.component(.year, from: Date())
    private let calendar = Calendar.current
    private let shortMonthFmt: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter
    }()
    private let fullMonthFmt: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        return formatter
    }()

    init(year: Int = Calendar.current.component(.year, from: Date())) {
        _year = State(initialValue: year)
    }

    private var yearTransactions: [Transaction] {
        allTransactions.filter {
            calendar.component(.year, from: $0.date) == year &&
            ($0.type == .income || $0.type == .expense)
        }
    }

    private var monthStats: [MonthStats] {
        (1...12).map { month in
            var income: Decimal = .zero
            var expense: Decimal = .zero
            for transaction in yearTransactions where calendar.component(.month, from: transaction.date) == month {
                if transaction.type == .income { income += transaction.amount }
                if transaction.type == .expense { expense += transaction.amount }
            }
            return MonthStats(month: month, income: income, expense: expense)
        }
    }

    private var totalIncome: Decimal { monthStats.reduce(.zero) { $0 + $1.income } }
    private var totalExpense: Decimal { monthStats.reduce(.zero) { $0 + $1.expense } }
    private var totalNet: Decimal { totalIncome - totalExpense }

    private var savingsRate: Double {
        guard totalIncome > 0 else { return 0 }
        return NSDecimalNumber(decimal: totalNet / totalIncome * 100).doubleValue
    }

    private var activeMonths: [MonthStats] {
        monthStats.filter { $0.income != .zero || $0.expense != .zero }
    }

    private var activeMonthCount: Int { activeMonths.count }

    private var averageMonthNet: Decimal {
        guard activeMonthCount > 0 else { return .zero }
        return totalNet / Decimal(activeMonthCount)
    }

    private var averageMonthExpense: Decimal {
        guard activeMonthCount > 0 else { return .zero }
        return totalExpense / Decimal(activeMonthCount)
    }

    private var categoryMap: [UUID: Category] {
        Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
    }

    private var topCategories: [(name: String, color: Color, iconName: String, amount: Decimal, pct: Double)] {
        var grouped: [UUID: Decimal] = [:]
        for transaction in yearTransactions where transaction.type == .expense {
            if let categoryID = transaction.categoryId {
                grouped[categoryID, default: .zero] += transaction.amount
            }
        }
        let total = totalExpense
        return grouped.compactMap { categoryID, amount in
            guard let category = categoryMap[categoryID] else { return nil }
            let pct: Double = total > 0
                ? NSDecimalNumber(decimal: amount / total * 100).doubleValue
                : 0
            return (
                name: category.name,
                color: Color(hex: category.colorHex),
                iconName: category.iconName,
                amount: amount,
                pct: pct
            )
        }
        .sorted { $0.amount > $1.amount }
        .prefix(5)
        .map { $0 }
    }

    private var bestMonth: MonthStats? { activeMonths.max(by: { $0.net < $1.net }) }
    private var worstMonth: MonthStats? { activeMonths.min(by: { $0.net < $1.net }) }
    private var peakExpenseMonth: MonthStats? { activeMonths.max(by: { $0.expense < $1.expense }) }
    private var hasData: Bool { !yearTransactions.isEmpty }

    private func monthName(_ month: Int) -> String {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        let date = calendar.date(from: components) ?? Date()
        return shortMonthFmt.string(from: date)
    }

    private func fullMonthName(_ month: Int) -> String {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        let date = calendar.date(from: components) ?? Date()
        return fullMonthFmt.string(from: date)
    }

    var body: some View {
        ZStack {
            AppTheme.canvas.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    yearHeader

                    if hasData {
                        heroSection
                        summaryCards
                        monthlyBreakdownSection
                        spendingMixSection
                        incomeExpenseChartSection
                        yearExtremesSection
                    } else {
                        emptyStateSection
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .keyboardDismissable()
        .financeNavigationSurface()
        .navigationTitle(String(localized: "Yearly Overview"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("yearlyOverview.screen")
    }

    private var yearHeader: some View {
        HStack(spacing: 14) {
            Button {
                year -= 1
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryAccent)
                    .frame(width: 38, height: 38)
                    .background(AppTheme.primaryAccent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)

            VStack(spacing: 2) {
                Text(verbatim: "\(year)")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .monospacedDigit()
                Text(year == currentYear ? String(localized: "Current year") : String(localized: "Selected year"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Button {
                year += 1
            } label: {
                Image(systemName: "chevron.right")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(year >= currentYear ? .secondary : AppTheme.primaryAccent)
                    .frame(width: 38, height: 38)
                    .background((year >= currentYear ? AppTheme.surfaceMuted : AppTheme.primaryAccent.opacity(0.12)))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(year >= currentYear)
        }
        .padding(14)
        .cockpitSurface(cornerRadius: 22, elevated: true, compact: true)
    }

    private var heroSection: some View {
        HeroMetricCard(
            title: String(localized: "Net"),
            value: CurrencyFormatter.string(from: totalNet),
            supportingTitle: String(localized: "Savings Rate"),
            supportingValue: String(format: "%.1f%%", savingsRate),
            note: String(localized: "Full-year picture for income, spending, and momentum."),
            badgeText: String(year)
        )
    }

    private var summaryCards: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            CompactSummaryCard(
                title: String(localized: "Total Income"),
                value: CurrencyFormatter.string(from: totalIncome),
                detail: String(localized: "All income booked this year"),
                systemImage: "arrow.down.left.circle.fill",
                tint: AppTheme.success
            )

            CompactSummaryCard(
                title: String(localized: "Total Expense"),
                value: CurrencyFormatter.string(from: totalExpense),
                detail: String(localized: "All expenses booked this year"),
                systemImage: "arrow.up.right.circle.fill",
                tint: AppTheme.danger
            )

            CompactSummaryCard(
                title: String(localized: "Active Months"),
                value: String(activeMonthCount),
                detail: String(format: String(localized: "%lld months with activity"), Int64(activeMonthCount)),
                systemImage: "calendar",
                tint: AppTheme.info
            )

            CompactSummaryCard(
                title: String(localized: "Average Month"),
                value: CurrencyFormatter.string(from: averageMonthNet),
                detail: CurrencyFormatter.string(from: averageMonthExpense),
                systemImage: "chart.line.uptrend.xyaxis",
                tint: averageMonthNet >= .zero ? AppTheme.success : AppTheme.warning
            )
        }
    }

    private var monthlyBreakdownSection: some View {
        SectionShell(
            title: String(localized: "Monthly Overview"),
            subtitle: String(localized: "Track every active month in one place.")
        ) {
            EmptyView()
        } content: {
            VStack(spacing: 0) {
                headerRow
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)

                ForEach(monthStats, id: \.month) { stat in
                    MonthRowView(
                        stat: stat,
                        monthName: monthName(stat.month)
                    )
                    if stat.month < 12 {
                        Divider()
                            .padding(.leading, 12)
                    }
                }
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Text(String(localized: "Month"))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(String(localized: "Income"))
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text(String(localized: "Expense"))
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text(String(localized: "Net"))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    private var spendingMixSection: some View {
        SectionShell(
            title: String(localized: "Top Categories"),
            subtitle: String(localized: "Largest expense categories for the selected year.")
        ) {
            if topCategories.isEmpty {
                Text(String(localized: "No data for this year"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 12) {
                    ForEach(topCategories, id: \.name) { item in
                        CategoryRowView(item: item)
                    }
                }
            }
        }
    }

    private var incomeExpenseChartSection: some View {
        SectionShell(
            title: String(localized: "Income vs Expenses"),
            subtitle: String(localized: "Compare monthly inflow and outflow before planning next year.")
        ) {
            VStack(alignment: .leading, spacing: 14) {
                let chartData = monthStats.flatMap { stat -> [(id: String, label: String, value: Double, type: String)] in
                    let label = monthName(stat.month)
                    return [
                        (
                            id: "\(stat.month)-income",
                            label: label,
                            value: NSDecimalNumber(decimal: stat.income).doubleValue,
                            type: String(localized: "Income")
                        ),
                        (
                            id: "\(stat.month)-expense",
                            label: label,
                            value: NSDecimalNumber(decimal: stat.expense).doubleValue,
                            type: String(localized: "Expense")
                        )
                    ]
                }

                Chart(chartData, id: \.id) { item in
                    BarMark(
                        x: .value("Month", item.label),
                        y: .value("Amount", item.value)
                    )
                    .foregroundStyle(item.type == String(localized: "Income") ? AppTheme.success : AppTheme.danger)
                    .position(by: .value("Type", item.type))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .frame(height: 220)
                .chartForegroundStyleScale([
                    String(localized: "Income"): AppTheme.success,
                    String(localized: "Expense"): AppTheme.danger
                ])

                if let peakExpenseMonth {
                    HStack(spacing: 10) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.warning)
                            .frame(width: 28, height: 28)
                            .background(AppTheme.warning.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "Peak spending"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(fullMonthName(peakExpenseMonth.month))
                                .font(.subheadline.weight(.semibold))
                        }
                        Spacer(minLength: 8)
                        Text(CurrencyFormatter.string(from: peakExpenseMonth.expense))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                    }
                    .padding(12)
                    .background(AppTheme.surfaceMuted)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
    }

    private var yearExtremesSection: some View {
        SectionShell(
            title: String(localized: "Year extremes"),
            subtitle: String(localized: "Best and toughest stretches of the year.")
        ) {
            HStack(spacing: 12) {
                if let bestMonth {
                    InsightCard(
                        title: String(localized: "Best Month"),
                        value: CurrencyFormatter.string(from: bestMonth.net),
                        message: fullMonthName(bestMonth.month),
                        systemImage: "arrow.up.right",
                        tint: AppTheme.success
                    )
                }

                if let worstMonth {
                    InsightCard(
                        title: String(localized: "Worst Month"),
                        value: CurrencyFormatter.string(from: worstMonth.net),
                        message: fullMonthName(worstMonth.month),
                        systemImage: "arrow.down.right",
                        tint: AppTheme.warning
                    )
                }
            }
        }
    }

    private var emptyStateSection: some View {
        SectionShell(
            title: String(localized: "No yearly data yet"),
            subtitle: String(localized: "Add income and expense transactions to unlock the full-year picture.")
        ) {
            HStack(spacing: 12) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.title3)
                    .foregroundStyle(AppTheme.primaryAccent)
                    .frame(width: 42, height: 42)
                    .background(AppTheme.primaryAccent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                Text(String(localized: "No data for this year"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
    }
}

private struct MonthRowView: View {
    let stat: MonthStats
    let monthName: String

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(monthName)
                    .font(.subheadline.weight(.semibold))
                Text(statusLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(CurrencyFormatter.string(from: stat.income))
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.success)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .minimumScaleFactor(0.7)
                .monospacedDigit()

            Text(CurrencyFormatter.string(from: stat.expense))
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.danger)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .minimumScaleFactor(0.7)
                .monospacedDigit()

            Text(CurrencyFormatter.string(from: stat.net))
                .font(.caption.weight(.bold))
                .foregroundStyle(stat.net >= 0 ? AppTheme.success : AppTheme.danger)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .minimumScaleFactor(0.7)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(stat.net < 0 ? AppTheme.warning.opacity(0.08) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var statusLabel: String {
        if stat.income == .zero && stat.expense == .zero {
            return String(localized: "No activity")
        }
        return stat.net >= .zero ? String(localized: "Net positive") : String(localized: "Net negative")
    }
}

private struct CategoryRowView: View {
    let item: (name: String, color: Color, iconName: String, amount: Decimal, pct: Double)

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: item.iconName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(item.color)
                    .frame(width: 28, height: 28)
                    .background(item.color.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(String(format: "%.1f%% %@", item.pct, String(localized: "of expenses")))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Text(CurrencyFormatter.string(from: item.amount))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.75)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(item.color.opacity(0.12))
                        .frame(height: 7)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(item.color)
                        .frame(width: max(geometry.size.width * (item.pct / 100), item.pct > 0 ? 3 : 0), height: 7)
                }
            }
            .frame(height: 7)
        }
        .padding(12)
        .background(AppTheme.surfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
