import SwiftUI
import SwiftData
import Charts

private struct AnnualStats {
    let year: Int
    let income: Decimal
    let expense: Decimal
    var net: Decimal { income - expense }
    var savingsRate: Double {
        guard income > 0 else { return 0 }
        return NSDecimalNumber(decimal: net / income * 100).doubleValue
    }
}

private struct AnnualMonthStats: Identifiable {
    let month: Int
    let income: Decimal
    let expense: Decimal
    var net: Decimal { income - expense }
    var id: Int { month }
}

private struct AnnualCategoryStats: Identifiable {
    let name: String
    let color: Color
    let iconName: String
    let amount: Decimal
    let pct: Double
    var id: String { name }
}

struct AnnualOverviewView: View {
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

    private var categoryMap: [UUID: Category] {
        Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
    }

    private func yearTransactions(for selectedYear: Int) -> [Transaction] {
        allTransactions.filter {
            calendar.component(.year, from: $0.date) == selectedYear &&
            ($0.type == .income || $0.type == .expense)
        }
    }

    private func annualStats(for selectedYear: Int) -> AnnualStats {
        let transactions = yearTransactions(for: selectedYear)
        var income: Decimal = .zero
        var expense: Decimal = .zero
        for transaction in transactions {
            if transaction.type == .income { income += transaction.amount }
            if transaction.type == .expense { expense += transaction.amount }
        }
        return AnnualStats(year: selectedYear, income: income, expense: expense)
    }

    private func monthStats(for selectedYear: Int) -> [AnnualMonthStats] {
        let transactions = yearTransactions(for: selectedYear)
        return (1...12).map { month in
            var income: Decimal = .zero
            var expense: Decimal = .zero
            for transaction in transactions where calendar.component(.month, from: transaction.date) == month {
                if transaction.type == .income { income += transaction.amount }
                if transaction.type == .expense { expense += transaction.amount }
            }
            return AnnualMonthStats(month: month, income: income, expense: expense)
        }
    }

    private func topCategories(for selectedYear: Int) -> [AnnualCategoryStats] {
        let transactions = yearTransactions(for: selectedYear)
        var grouped: [UUID: Decimal] = [:]
        for transaction in transactions where transaction.type == .expense {
            if let categoryID = transaction.categoryId {
                grouped[categoryID, default: .zero] += transaction.amount
            }
        }

        let total = grouped.values.reduce(.zero, +)
        return grouped.compactMap { categoryID, amount in
            guard let category = categoryMap[categoryID] else { return nil }
            let pct: Double = total > 0
                ? NSDecimalNumber(decimal: amount / total * 100).doubleValue
                : 0
            return AnnualCategoryStats(
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

    private var currentStats: AnnualStats { annualStats(for: year) }
    private var previousStats: AnnualStats { annualStats(for: year - 1) }
    private var currentMonthStats: [AnnualMonthStats] { monthStats(for: year) }
    private var currentTopCategories: [AnnualCategoryStats] { topCategories(for: year) }
    private var activeMonthCount: Int { currentMonthStats.filter { $0.income != .zero || $0.expense != .zero }.count }
    private var averageMonthNet: Decimal {
        guard activeMonthCount > 0 else { return .zero }
        return currentStats.net / Decimal(activeMonthCount)
    }
    private var bestMonth: AnnualMonthStats? { currentMonthStats.max(by: { $0.net < $1.net }) }
    private var worstMonth: AnnualMonthStats? { currentMonthStats.min(by: { $0.net < $1.net }) }
    private var hasData: Bool { !yearTransactions(for: year).isEmpty }

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

    private func deltaPercent(current: Decimal, previous: Decimal) -> Double? {
        guard previous != 0 else { return nil }
        let delta = current - previous
        return NSDecimalNumber(decimal: delta / abs(previous) * 100).doubleValue
    }

    private func formattedDelta(_ value: Double?, suffix: String = "%") -> String {
        guard let value else { return String(localized: "No baseline") }
        let symbol = value >= 0 ? "+" : "−"
        return String(format: "%@%.1f%@", symbol, abs(value), suffix)
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
                        comparisonSection
                        monthlyBreakdownSection
                        categoryMixSection
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
        .navigationTitle(String(localized: "Annual Overview"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("annualOverview.screen")
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
            .accessibilityIdentifier("annualOverview.prevYear")

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
                    .background(year >= currentYear ? AppTheme.surfaceMuted : AppTheme.primaryAccent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(year >= currentYear)
            .accessibilityIdentifier("annualOverview.nextYear")
        }
        .padding(14)
        .cockpitSurface(cornerRadius: 22, elevated: true, compact: true)
    }

    private var heroSection: some View {
        HeroMetricCard(
            title: String(localized: "Annual comparison"),
            value: CurrencyFormatter.string(from: currentStats.net),
            supportingTitle: String(localized: "vs previous year"),
            supportingValue: formattedDelta(deltaPercent(current: currentStats.net, previous: previousStats.net)),
            note: String(localized: "Compare how the year moved before changing long-range plans."),
            badgeText: String(year)
        )
    }

    private var summaryCards: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            CompactSummaryCard(
                title: String(localized: "Total Income"),
                value: CurrencyFormatter.string(from: currentStats.income),
                detail: String(localized: "Current year income"),
                systemImage: "arrow.down.left.circle.fill",
                tint: AppTheme.success
            )

            CompactSummaryCard(
                title: String(localized: "Total Expenses"),
                value: CurrencyFormatter.string(from: currentStats.expense),
                detail: String(localized: "Current year expenses"),
                systemImage: "arrow.up.right.circle.fill",
                tint: AppTheme.danger
            )

            CompactSummaryCard(
                title: String(localized: "Savings Rate"),
                value: String(format: "%.1f%%", currentStats.savingsRate),
                detail: formattedDelta(currentStats.savingsRate - previousStats.savingsRate, suffix: " pt"),
                systemImage: "percent",
                tint: currentStats.savingsRate >= 0 ? AppTheme.success : AppTheme.warning
            )

            CompactSummaryCard(
                title: String(localized: "Average Month"),
                value: CurrencyFormatter.string(from: averageMonthNet),
                detail: String(format: String(localized: "%lld months with activity"), Int64(activeMonthCount)),
                systemImage: "calendar.badge.clock",
                tint: AppTheme.info
            )
        }
    }

    private var comparisonSection: some View {
        SectionShell(
            title: String(localized: "Year over year"),
            subtitle: String(localized: "Compare the selected year against the previous year.")
        ) {
            VStack(spacing: 14) {
                HStack {
                    Text("")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(String(localized: "This year"))
                        .frame(minWidth: 88, alignment: .trailing)
                    Text(String(localized: "Previous year"))
                        .frame(minWidth: 88, alignment: .trailing)
                    Text("Δ")
                        .frame(minWidth: 58, alignment: .trailing)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

                comparisonRow(
                    label: String(localized: "Total Income"),
                    current: currentStats.income,
                    previous: previousStats.income,
                    higherIsBetter: true
                )
                comparisonRow(
                    label: String(localized: "Total Expenses"),
                    current: currentStats.expense,
                    previous: previousStats.expense,
                    higherIsBetter: false
                )
                comparisonRow(
                    label: String(localized: "Net Savings"),
                    current: currentStats.net,
                    previous: previousStats.net,
                    higherIsBetter: true
                )

                Divider()

                HStack {
                    Text(String(localized: "Savings Rate"))
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(String(format: "%.1f%%", currentStats.savingsRate))
                        .font(.subheadline.weight(.semibold))
                        .frame(minWidth: 88, alignment: .trailing)
                    Text(String(format: "%.1f%%", previousStats.savingsRate))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 88, alignment: .trailing)
                    Text(formattedDelta(currentStats.savingsRate - previousStats.savingsRate, suffix: " pt"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(currentStats.savingsRate >= previousStats.savingsRate ? AppTheme.success : AppTheme.danger)
                        .frame(minWidth: 58, alignment: .trailing)
                }
            }
        }
    }

    @ViewBuilder
    private func comparisonRow(label: String, current: Decimal, previous: Decimal, higherIsBetter: Bool) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(CurrencyFormatter.string(from: current))
                .font(.subheadline.weight(.semibold))
                .frame(minWidth: 88, alignment: .trailing)
                .minimumScaleFactor(0.75)
                .monospacedDigit()
            Text(CurrencyFormatter.string(from: previous))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(minWidth: 88, alignment: .trailing)
                .minimumScaleFactor(0.75)
                .monospacedDigit()
            deltaText(current: current, previous: previous, higherIsBetter: higherIsBetter)
                .frame(minWidth: 58, alignment: .trailing)
        }
    }

    @ViewBuilder
    private func deltaText(current: Decimal, previous: Decimal, higherIsBetter: Bool) -> some View {
        if let percent = deltaPercent(current: current, previous: previous) {
            let isPositive = percent >= 0
            let isGood = higherIsBetter ? isPositive : !isPositive
            let symbol = isPositive ? "▲" : "▼"
            Text(String(format: "%@%.1f%%", symbol, abs(percent)))
                .font(.caption.weight(.semibold))
                .foregroundStyle(isGood ? AppTheme.success : AppTheme.danger)
        } else {
            Text(String(localized: "No baseline"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var monthlyBreakdownSection: some View {
        SectionShell(
            title: String(localized: "Monthly Breakdown"),
            subtitle: String(localized: "See which months carried the year and where pressure spiked.")
        ) {
            VStack(alignment: .leading, spacing: 14) {
                let chartData = currentMonthStats.flatMap { stat -> [(id: String, label: String, value: Double, kind: String)] in
                    [
                        (
                            id: "\(stat.month)-income",
                            label: monthName(stat.month),
                            value: NSDecimalNumber(decimal: stat.income).doubleValue,
                            kind: String(localized: "Income")
                        ),
                        (
                            id: "\(stat.month)-expense",
                            label: monthName(stat.month),
                            value: NSDecimalNumber(decimal: stat.expense).doubleValue,
                            kind: String(localized: "Expenses")
                        )
                    ]
                }

                Chart(chartData, id: \.id) { item in
                    BarMark(
                        x: .value("Month", item.label),
                        y: .value("Amount", item.value)
                    )
                    .foregroundStyle(item.kind == String(localized: "Income") ? AppTheme.success : AppTheme.danger)
                    .position(by: .value("Type", item.kind))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .frame(height: 220)
                .chartForegroundStyleScale([
                    String(localized: "Income"): AppTheme.success,
                    String(localized: "Expenses"): AppTheme.danger
                ])

                VStack(spacing: 0) {
                    ForEach(currentMonthStats) { stat in
                        AnnualMonthRowView(monthName: monthName(stat.month), stat: stat)
                        if stat.month < 12 {
                            Divider()
                                .padding(.leading, 12)
                        }
                    }
                }
            }
        }
    }

    private var categoryMixSection: some View {
        SectionShell(
            title: String(localized: "Top Categories"),
            subtitle: String(localized: "Largest expense categories for the selected year.")
        ) {
            if currentTopCategories.isEmpty {
                Text(String(localized: "No transactions this year"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 12) {
                    ForEach(currentTopCategories) { item in
                        AnnualCategoryRowView(item: item)
                    }
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
            title: String(localized: "No annual data yet"),
            subtitle: String(localized: "Add income and expense transactions to compare years with confidence.")
        ) {
            HStack(spacing: 12) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.title3)
                    .foregroundStyle(AppTheme.primaryAccent)
                    .frame(width: 42, height: 42)
                    .background(AppTheme.primaryAccent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                Text(String(localized: "No transactions this year"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
    }
}

private struct AnnualMonthRowView: View {
    let monthName: String
    let stat: AnnualMonthStats

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

private struct AnnualCategoryRowView: View {
    let item: AnnualCategoryStats

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
