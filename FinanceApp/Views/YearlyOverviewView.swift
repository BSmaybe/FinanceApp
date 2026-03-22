import SwiftUI
import SwiftData
import Charts

// MARK: - MonthStats

private struct MonthStats {
    let month: Int
    let income: Decimal
    let expense: Decimal
    var net: Decimal { income - expense }
}

// MARK: - YearlyOverviewView

struct YearlyOverviewView: View {
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

    // MARK: Computed data

    private var yearTransactions: [Transaction] {
        allTransactions.filter {
            calendar.component(.year, from: $0.date) == year &&
            ($0.type == .income || $0.type == .expense)
        }
    }

    private var monthStats: [MonthStats] {
        (1...12).map { m in
            var inc: Decimal = .zero
            var exp: Decimal = .zero
            for t in yearTransactions {
                if calendar.component(.month, from: t.date) == m {
                    if t.type == .income  { inc += t.amount }
                    if t.type == .expense { exp += t.amount }
                }
            }
            return MonthStats(month: m, income: inc, expense: exp)
        }
    }

    private var totalIncome: Decimal  { monthStats.reduce(.zero) { $0 + $1.income } }
    private var totalExpense: Decimal { monthStats.reduce(.zero) { $0 + $1.expense } }
    private var totalNet: Decimal     { totalIncome - totalExpense }

    private var savingsRate: Double {
        guard totalIncome > 0 else { return 0 }
        let rate = NSDecimalNumber(decimal: totalNet / totalIncome * 100).doubleValue
        return rate
    }

    private var categoryMap: [UUID: Category] {
        Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
    }

    private var topCategories: [(name: String, color: Color, iconName: String, amount: Decimal, pct: Double)] {
        var grouped: [UUID: Decimal] = [:]
        for t in yearTransactions where t.type == .expense {
            if let cid = t.categoryId { grouped[cid, default: .zero] += t.amount }
        }
        let total = totalExpense
        return grouped.compactMap { cid, amt in
            guard let cat = categoryMap[cid] else { return nil }
            let pct: Double = total > 0
                ? NSDecimalNumber(decimal: amt / total * 100).doubleValue
                : 0
            return (name: cat.name, color: Color(hex: cat.colorHex), iconName: cat.iconName, amount: amt, pct: pct)
        }
        .sorted { $0.amount > $1.amount }
        .prefix(5)
        .map { $0 }
    }

    private var maxMonthExpense: Decimal {
        monthStats.map(\.expense).max() ?? .zero
    }

    private var bestMonth: MonthStats? { monthStats.max(by: { $0.net < $1.net }) }
    private var worstMonth: MonthStats? { monthStats.min(by: { $0.net < $1.net }) }

    private var hasData: Bool { !yearTransactions.isEmpty }

    // MARK: Month name helper

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

    // MARK: - body

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                yearHeader
                if hasData {
                    summaryBadges
                    monthlyBreakdownSection
                    topCategoriesSection
                    incomeExpenseBarChartSection
                    bestWorstSection
                } else {
                    Text(String(localized: "No data for this year"))
                        .foregroundStyle(.secondary)
                        .padding(.top, 40)
                }
            }
            .padding()
        }
        .navigationTitle(String(localized: "Yearly Overview"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("yearlyOverview.screen")
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

            Text("\(year)")
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
        }
    }

    // MARK: - Summary Badges

    private var summaryBadges: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                summaryBadge(
                    title: String(localized: "Total Income"),
                    value: CurrencyFormatter.string(from: totalIncome),
                    color: AppTheme.success
                )
                summaryBadge(
                    title: String(localized: "Total Expense"),
                    value: CurrencyFormatter.string(from: totalExpense),
                    color: AppTheme.danger
                )
            }
            HStack(spacing: 12) {
                summaryBadge(
                    title: String(localized: "Net"),
                    value: CurrencyFormatter.string(from: totalNet),
                    color: totalNet >= 0 ? AppTheme.success : AppTheme.danger
                )
                savingsRateBadge
            }
        }
    }

    private func summaryBadge(title: String, value: String, color: Color) -> some View {
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
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var savingsRateBadge: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "Savings Rate"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(String(format: "%.1f%%", savingsRate))
                .font(.headline.bold())
                .foregroundStyle(savingsRate >= 0 ? AppTheme.success : AppTheme.danger)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Monthly Breakdown

    private var monthlyBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Monthly Overview"))
                .font(.headline)

            VStack(spacing: 0) {
                ForEach(monthStats, id: \.month) { stat in
                    MonthRowView(
                        stat: stat,
                        monthName: monthName(stat.month),
                        maxExpense: maxMonthExpense
                    )
                    if stat.month < 12 {
                        Divider().padding(.horizontal, 8)
                    }
                }
            }
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Top Categories

    private var topCategoriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Top Categories"))
                .font(.headline)

            if topCategories.isEmpty {
                Text(String(localized: "No data for this year"))
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(topCategories, id: \.name) { item in
                        CategoryRowView(item: item)
                    }
                }
            }
        }
        .padding()
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Income vs Expense Bar Chart

    private var incomeExpenseBarChartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Income vs Expenses"))
                .font(.headline)

            let chartData = monthStats.flatMap { stat -> [(label: String, value: Double, type: String)] in
                let label = monthName(stat.month)
                return [
                    (label: label,
                     value: NSDecimalNumber(decimal: stat.income).doubleValue,
                     type: String(localized: "Income")),
                    (label: label,
                     value: NSDecimalNumber(decimal: stat.expense).doubleValue,
                     type: String(localized: "Expense"))
                ]
            }

            Chart(chartData, id: \.type) { item in
                BarMark(
                    x: .value("Month", item.label),
                    y: .value("Amount", item.value)
                )
                .foregroundStyle(item.type == String(localized: "Income")
                    ? AppTheme.success
                    : AppTheme.danger)
                .position(by: .value("Type", item.type))
            }
            .frame(height: 220)
            .chartForegroundStyleScale([
                String(localized: "Income"):  AppTheme.success,
                String(localized: "Expense"): AppTheme.danger
            ])
        }
        .padding()
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Best / Worst Month

    private var bestWorstSection: some View {
        HStack(spacing: 12) {
            if let best = bestMonth {
                bestWorstCard(
                    title: String(localized: "Best Month"),
                    monthName: fullMonthName(best.month),
                    net: best.net,
                    isGood: true
                )
            }
            if let worst = worstMonth {
                bestWorstCard(
                    title: String(localized: "Worst Month"),
                    monthName: fullMonthName(worst.month),
                    net: worst.net,
                    isGood: false
                )
            }
        }
    }

    private func bestWorstCard(title: String, monthName: String, net: Decimal, isGood: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(monthName)
                .font(.subheadline.bold())
            Text(CurrencyFormatter.string(from: net))
                .font(.subheadline)
                .foregroundStyle(net >= 0 ? AppTheme.success : AppTheme.danger)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - MonthRowView

private struct MonthRowView: View {
    let stat: MonthStats
    let monthName: String
    let maxExpense: Decimal

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

            expenseBar
                .frame(width: 40)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    private var expenseBar: some View {
        let ratio: Double = maxExpense > 0
            ? NSDecimalNumber(decimal: stat.expense / maxExpense).doubleValue
            : 0
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(AppTheme.danger.opacity(0.15))
                    .frame(width: geo.size.width, height: 6)
                RoundedRectangle(cornerRadius: 2)
                    .fill(AppTheme.danger)
                    .frame(width: max(geo.size.width * ratio, ratio > 0 ? 2 : 0), height: 6)
            }
        }
        .frame(height: 6)
    }
}

// MARK: - CategoryRowView

private struct CategoryRowView: View {
    let item: (name: String, color: Color, iconName: String, amount: Decimal, pct: Double)

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: item.iconName)
                    .font(.caption2)
                    .foregroundStyle(item.color)
                    .frame(width: 22, height: 22)
                    .background(item.color.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 5))

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
                    RoundedRectangle(cornerRadius: 3)
                        .fill(item.color.opacity(0.15))
                        .frame(width: geo.size.width, height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(item.color)
                        .frame(width: geo.size.width * (item.pct / 100), height: 6)
                }
            }
            .frame(height: 6)
        }
    }
}
