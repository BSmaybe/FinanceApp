import SwiftUI
import SwiftData
import Charts

// MARK: - AnnualStats

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

// MARK: - AnnualMonthStats

private struct AnnualMonthStats: Identifiable {
    let month: Int
    let income: Decimal
    let expense: Decimal
    var net: Decimal { income - expense }
    var id: Int { month }
}

// MARK: - AnnualCategoryStats

private struct AnnualCategoryStats: Identifiable {
    let name: String
    let color: Color
    let iconName: String
    let amount: Decimal
    let pct: Double
    var id: String { name }
}

// MARK: - AnnualOverviewView

struct AnnualOverviewView: View {
    @Query(sort: \Transaction.date, order: .reverse) private var allTransactions: [Transaction]
    @Query private var categories: [Category]

    @State private var year: Int

    private let currentYear: Int = Calendar.current.component(.year, from: Date())
    private let calendar = Calendar.current
    private let shortMonthFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM"; return f
    }()
    private let fullMonthFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMMM"; return f
    }()

    init(year: Int = Calendar.current.component(.year, from: Date())) {
        _year = State(initialValue: year)
    }

    // MARK: Category lookup

    private var categoryMap: [UUID: Category] {
        Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
    }

    // MARK: Year-filtered transactions

    private func yearTransactions(for y: Int) -> [Transaction] {
        allTransactions.filter {
            calendar.component(.year, from: $0.date) == y &&
            ($0.type == .income || $0.type == .expense)
        }
    }

    // MARK: Stats for a given year

    private func annualStats(for y: Int) -> AnnualStats {
        let txns = yearTransactions(for: y)
        var inc: Decimal = .zero
        var exp: Decimal = .zero
        for t in txns {
            if t.type == .income  { inc += t.amount }
            if t.type == .expense { exp += t.amount }
        }
        return AnnualStats(year: y, income: inc, expense: exp)
    }

    private func monthStats(for y: Int) -> [AnnualMonthStats] {
        let txns = yearTransactions(for: y)
        return (1...12).map { m in
            var inc: Decimal = .zero
            var exp: Decimal = .zero
            for t in txns where calendar.component(.month, from: t.date) == m {
                if t.type == .income  { inc += t.amount }
                if t.type == .expense { exp += t.amount }
            }
            return AnnualMonthStats(month: m, income: inc, expense: exp)
        }
    }

    private func topCategories(for y: Int) -> [AnnualCategoryStats] {
        let txns = yearTransactions(for: y)
        var grouped: [UUID: Decimal] = [:]
        for t in txns where t.type == .expense {
            if let cid = t.categoryId { grouped[cid, default: .zero] += t.amount }
        }
        let total = grouped.values.reduce(.zero, +)
        return grouped.compactMap { cid, amt in
            guard let cat = categoryMap[cid] else { return nil }
            let pct: Double = total > 0
                ? NSDecimalNumber(decimal: amt / total * 100).doubleValue
                : 0
            return AnnualCategoryStats(
                name: cat.name,
                color: Color(hex: cat.colorHex),
                iconName: cat.iconName,
                amount: amt,
                pct: pct
            )
        }
        .sorted { $0.amount > $1.amount }
        .prefix(5)
        .map { $0 }
    }

    // MARK: Derived

    private var currentStats: AnnualStats { annualStats(for: year) }
    private var prevStats: AnnualStats    { annualStats(for: year - 1) }

    private var currentMonthStats: [AnnualMonthStats] { monthStats(for: year) }
    private var currentTopCategories: [AnnualCategoryStats] { topCategories(for: year) }

    private var bestMonth: AnnualMonthStats? { currentMonthStats.max(by: { $0.net < $1.net }) }
    private var worstMonth: AnnualMonthStats? { currentMonthStats.min(by: { $0.net < $1.net }) }

    private var hasData: Bool { !yearTransactions(for: year).isEmpty }

    // MARK: Helpers

    private func monthName(_ m: Int) -> String {
        var c = DateComponents(); c.year = year; c.month = m; c.day = 1
        let d = calendar.date(from: c) ?? Date()
        return shortMonthFmt.string(from: d)
    }

    private func fullMonthName(_ m: Int) -> String {
        var c = DateComponents(); c.year = year; c.month = m; c.day = 1
        let d = calendar.date(from: c) ?? Date()
        return fullMonthFmt.string(from: d)
    }

    private func deltaPercent(current: Decimal, previous: Decimal) -> Double? {
        guard previous != 0 else { return nil }
        let delta = current - previous
        return NSDecimalNumber(decimal: delta / abs(previous) * 100).doubleValue
    }

    // MARK: - body

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                yearHeader
                if hasData {
                    summaryCards
                    monthlyBreakdownSection
                    topCategoriesSection
                    bestWorstSection
                    yearOverYearSection
                } else {
                    Text(String(localized: "No transactions this year"))
                        .foregroundStyle(.secondary)
                        .padding(.top, 40)
                }
            }
            .padding()
        }
        .keyboardDismissable()
        .background(AppTheme.canvas.ignoresSafeArea())
        .navigationTitle(String(localized: "Annual Overview"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("annualOverview.screen")
    }

    // MARK: - Year Header

    private var yearHeader: some View {
        HStack(spacing: 20) {
            Button {
                year -= 1
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title2)
                    .foregroundStyle(AppTheme.primaryAccent)
            }
            .accessibilityIdentifier("annualOverview.prevYear")

            Text(verbatim: "\(year)")
                .font(.largeTitle.bold())
                .monospacedDigit()

            Button {
                year += 1
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title2)
                    .foregroundStyle(year >= currentYear ? .secondary : AppTheme.primaryAccent)
            }
            .disabled(year >= currentYear)
            .accessibilityIdentifier("annualOverview.nextYear")
        }
    }

    // MARK: - Summary Cards

    private var summaryCards: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                summaryCard(
                    title: String(localized: "Total Income"),
                    value: CurrencyFormatter.string(from: currentStats.income),
                    color: AppTheme.success
                )
                summaryCard(
                    title: String(localized: "Total Expenses"),
                    value: CurrencyFormatter.string(from: currentStats.expense),
                    color: AppTheme.danger
                )
            }
            HStack(spacing: 12) {
                summaryCard(
                    title: String(localized: "Net Savings"),
                    value: CurrencyFormatter.string(from: currentStats.net),
                    color: currentStats.net >= 0 ? AppTheme.success : AppTheme.danger
                )
                savingsRateCard
            }
        }
    }

    private func summaryCard(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.bold())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var savingsRateCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "Savings Rate"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(String(format: "%.1f%%", currentStats.savingsRate))
                .font(.headline.bold())
                .foregroundStyle(currentStats.savingsRate >= 0 ? AppTheme.success : AppTheme.danger)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Monthly Breakdown

    private var monthlyBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Monthly Breakdown"))
                .font(.headline)

            let chartData: [(label: String, value: Double, kind: String)] = currentMonthStats.flatMap { stat in
                [
                    (label: monthName(stat.month),
                     value: NSDecimalNumber(decimal: stat.income).doubleValue,
                     kind: String(localized: "Income")),
                    (label: monthName(stat.month),
                     value: NSDecimalNumber(decimal: stat.expense).doubleValue,
                     kind: String(localized: "Expenses"))
                ]
            }

            Chart(chartData, id: \.kind) { item in
                BarMark(
                    x: .value("Month", item.label),
                    y: .value("Amount", item.value)
                )
                .foregroundStyle(item.kind == String(localized: "Income")
                    ? AppTheme.success
                    : AppTheme.danger)
                .position(by: .value("Type", item.kind))
            }
            .frame(height: 220)
            .chartForegroundStyleScale([
                String(localized: "Income"):   AppTheme.success,
                String(localized: "Expenses"): AppTheme.danger
            ])

            Divider()

            // Monthly table rows
            VStack(spacing: 0) {
                ForEach(currentMonthStats) { stat in
                    AnnualMonthRowView(
                        monthName: monthName(stat.month),
                        stat: stat
                    )
                    if stat.month < 12 {
                        Divider().padding(.horizontal, 8)
                    }
                }
            }
        }
        .padding()
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Top Categories

    private var topCategoriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Top Categories"))
                .font(.headline)

            if currentTopCategories.isEmpty {
                Text(String(localized: "No transactions this year"))
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(currentTopCategories) { item in
                        AnnualCategoryRowView(item: item)
                    }
                }
            }
        }
        .padding()
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Best / Worst Month

    private var bestWorstSection: some View {
        HStack(spacing: 12) {
            if let best = bestMonth {
                bestWorstCard(
                    title: String(localized: "Best Month"),
                    name: fullMonthName(best.month),
                    net: best.net,
                    isGood: true
                )
            }
            if let worst = worstMonth {
                bestWorstCard(
                    title: String(localized: "Worst Month"),
                    name: fullMonthName(worst.month),
                    net: worst.net,
                    isGood: false
                )
            }
        }
    }

    private func bestWorstCard(title: String, name: String, net: Decimal, isGood: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(name)
                .font(.subheadline.bold())
            Text(CurrencyFormatter.string(from: net))
                .font(.subheadline)
                .foregroundStyle(net >= 0 ? AppTheme.success : AppTheme.danger)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Year-over-Year Comparison

    private var yearOverYearSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Year Overview"))
                .font(.headline)

            HStack {
                Text("")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(verbatim: "\(year)")
                    .font(.caption.bold())
                    .frame(minWidth: 80, alignment: .trailing)
                Text(verbatim: "\(year - 1)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 80, alignment: .trailing)
                Text("Δ")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 48, alignment: .trailing)
            }

            Divider()

            yoyRow(
                label: String(localized: "Total Income"),
                current: currentStats.income,
                previous: prevStats.income,
                higherIsBetter: true
            )
            yoyRow(
                label: String(localized: "Total Expenses"),
                current: currentStats.expense,
                previous: prevStats.expense,
                higherIsBetter: false
            )
            yoyRow(
                label: String(localized: "Net Savings"),
                current: currentStats.net,
                previous: prevStats.net,
                higherIsBetter: true
            )

            Divider()

            yoySavingsRateRow
        }
        .padding()
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func yoyRow(
        label: String,
        current: Decimal,
        previous: Decimal,
        higherIsBetter: Bool
    ) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(CurrencyFormatter.string(from: current))
                .font(.subheadline)
                .frame(minWidth: 80, alignment: .trailing)
            Text(CurrencyFormatter.string(from: previous))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(minWidth: 80, alignment: .trailing)
            deltaText(current: current, previous: previous, higherIsBetter: higherIsBetter)
                .frame(minWidth: 48, alignment: .trailing)
        }
    }

    private var yoySavingsRateRow: some View {
        HStack {
            Text(String(localized: "Savings Rate"))
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(String(format: "%.1f%%", currentStats.savingsRate))
                .font(.subheadline.bold())
                .frame(minWidth: 80, alignment: .trailing)
            Text(String(format: "%.1f%%", prevStats.savingsRate))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(minWidth: 80, alignment: .trailing)
            savingsRateDeltaText
                .frame(minWidth: 48, alignment: .trailing)
        }
    }

    @ViewBuilder
    private func deltaText(current: Decimal, previous: Decimal, higherIsBetter: Bool) -> some View {
        if let pct = deltaPercent(current: current, previous: previous) {
            let isPositive = pct >= 0
            let isGood = higherIsBetter ? isPositive : !isPositive
            let symbol = isPositive ? "▲" : "▼"
            Text(String(format: "%@%.1f%%", symbol, abs(pct)))
                .font(.caption.bold())
                .foregroundStyle(isGood ? AppTheme.success : AppTheme.danger)
        } else {
            Text("—")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var savingsRateDeltaText: some View {
        let diff = currentStats.savingsRate - prevStats.savingsRate
        let isPositive = diff >= 0
        let symbol = isPositive ? "▲" : "▼"
        return Text(String(format: "%@%.1f pt", symbol, abs(diff)))
            .font(.caption.bold())
            .foregroundStyle(isPositive ? AppTheme.success : AppTheme.danger)
    }
}

// MARK: - AnnualMonthRowView

private struct AnnualMonthRowView: View {
    let monthName: String
    let stat: AnnualMonthStats

    var body: some View {
        HStack(spacing: 8) {
            Text(monthName)
                .font(.caption.bold())
                .frame(width: 34, alignment: .leading)

            Text(CurrencyFormatter.string(from: stat.income))
                .font(.caption2)
                .foregroundStyle(AppTheme.success)
                .frame(maxWidth: .infinity, alignment: .trailing)

            Text(CurrencyFormatter.string(from: stat.expense))
                .font(.caption2)
                .foregroundStyle(AppTheme.danger)
                .frame(maxWidth: .infinity, alignment: .trailing)

            Text(CurrencyFormatter.string(from: stat.net))
                .font(.caption2.bold())
                .foregroundStyle(stat.net >= 0 ? AppTheme.success : AppTheme.danger)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(stat.net < 0 ? AppTheme.danger.opacity(0.06) : Color.clear)
    }
}

// MARK: - AnnualCategoryRowView

private struct AnnualCategoryRowView: View {
    let item: AnnualCategoryStats

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: item.iconName)
                    .font(.caption2)
                    .foregroundStyle(item.color)
                    .frame(width: 22, height: 22)
                    .background(item.color.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                Text(item.name)
                    .font(.subheadline)
                    .lineLimit(1)

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(CurrencyFormatter.string(from: item.amount))
                        .font(.subheadline.bold())
                    Text(String(format: "%.1f%% %@", item.pct, String(localized: "of expenses")))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(item.color.opacity(0.15))
                        .frame(width: geo.size.width, height: 6)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(item.color)
                        .frame(width: max(geo.size.width * (item.pct / 100), item.pct > 0 ? 2 : 0), height: 6)
                }
            }
            .frame(height: 6)
        }
    }
}
