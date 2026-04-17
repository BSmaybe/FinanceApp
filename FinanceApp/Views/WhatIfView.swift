import SwiftUI
import SwiftData

// MARK: - WhatIfView

struct WhatIfView: View {
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query(sort: \Debt.name) private var debts: [Debt]

    private var planningBase: Decimal {
        averageMonthlyExpense(from: transactions)
    }

    var body: some View {
        ZStack {
            AppTheme.canvas.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    HeroMetricCard(
                        title: String(localized: "Scenario planning"),
                        value: formatMoney(planningBase),
                        supportingTitle: String(localized: "Scenarios"),
                        supportingValue: String(localized: "3 planning levers"),
                        note: String(localized: "Test tradeoffs before you commit real money to a new plan."),
                        badgeText: String(localized: "What If")
                    )

                    ReduceSpendingCard(transactions: transactions)
                    SaveMonthlyCard()
                    PayOffDebtCard(debts: debts)
                }
                .padding(16)
            }
            .keyboardDismissable()
        }
        .navigationTitle(String(localized: "What If"))
        .navigationBarTitleDisplayMode(.large)
        .accessibilityIdentifier("whatIf.screen")
    }
}

// MARK: - Average monthly expense helper

private func averageMonthlyExpense(from transactions: [Transaction]) -> Decimal {
    let now = Date()
    let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: now) ?? now
    var total: Decimal = .zero
    for txn in transactions {
        guard txn.type == .expense, txn.date >= cutoff else { continue }
        total += txn.amount
    }
    return total / 3
}

// MARK: - Duration formatting helper

private func formatDuration(months: Int) -> String {
    if months < 12 {
        return String(format: String(localized: "%lld months"), Int64(months))
    }
    let years = months / 12
    let remaining = months % 12
    if remaining == 0 {
        return String(format: String(localized: "%lld months"), Int64(months))
    }
    return String(format: String(localized: "%lld yr %lld mo"), Int64(years), Int64(remaining))
}

// MARK: - Money formatting helper

@MainActor
private func formatMoney(_ value: Decimal) -> String {
    let rounded = (value as NSDecimalNumber).rounding(
        accordingToBehavior: NSDecimalNumberHandler(
            roundingMode: .plain, scale: 0,
            raiseOnExactness: false, raiseOnOverflow: false,
            raiseOnUnderflow: false, raiseOnDivideByZero: false
        )
    )
    return CurrencyFormatter.string(from: rounded as Decimal)
}

// MARK: - Scenario Card Shell

private struct ScenarioCard<Content: View>: View {
    let title: String
    let systemImage: String
    let tint: Color
    let content: Content

    init(
        title: String,
        systemImage: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 32, height: 32)
                    .background(tint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(title)
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                Spacer(minLength: 0)
            }

            Divider()

            content
        }
        .cockpitSurface(cornerRadius: 22, elevated: true)
    }
}

// MARK: - Result Row

private struct WhatIfResultRow: View {
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Scenario 1: Reduce Spending

private struct ReduceSpendingCard: View {
    let transactions: [Transaction]

    @State private var reductionPercent: Double = 10

    private var avgExpense: Decimal {
        averageMonthlyExpense(from: transactions)
    }

    private var monthlySaving: Decimal {
        avgExpense * Decimal(Int(reductionPercent)) / 100
    }

    private var annualSaving: Decimal {
        monthlySaving * 12
    }

    var body: some View {
        ScenarioCard(
            title: String(localized: "Reduce Spending"),
            systemImage: "scissors",
            tint: AppTheme.warning
        ) {
            VStack(alignment: .leading, spacing: 4) {
                Text(
                    String(
                        format: String(localized: "Reduce expenses by %lld%% and see the impact"),
                        Int64(reductionPercent)
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(Int(reductionPercent))%")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(AppTheme.warning)
                        .monospacedDigit()
                    Text(String(localized: "reduction"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                Slider(value: $reductionPercent, in: 5...50, step: 5)
                    .tint(AppTheme.warning)
            }

            Divider()

            VStack(spacing: 8) {
                WhatIfResultRow(
                    label: String(localized: "Monthly savings gained"),
                    value: formatMoney(monthlySaving),
                    tint: AppTheme.success
                )
                WhatIfResultRow(
                    label: String(localized: "Projected annual savings"),
                    value: formatMoney(annualSaving),
                    tint: AppTheme.success
                )
            }
        }
    }
}

// MARK: - Scenario 2: Save Monthly

private struct SaveMonthlyCard: View {
    @State private var monthlySavings: Double = 500
    @State private var goalText: String = ""

    private var monthly: Decimal { Decimal(Int(monthlySavings)) }
    private var goal: Decimal    { Decimal(string: goalText) ?? .zero }

    private var monthsToGoal: Int? {
        guard monthly > 0, goal > 0 else { return nil }
        let v = NSDecimalNumber(decimal: goal / monthly).doubleValue
        return Int(ceil(v))
    }

    private var goalDate: Date? {
        guard let months = monthsToGoal else { return nil }
        return Calendar.current.date(byAdding: .month, value: months, to: Date())
    }

    private var goalDateString: String {
        guard let date = goalDate else { return "–" }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM yyyy"
        return fmt.string(from: date)
    }

    var body: some View {
        ScenarioCard(
            title: String(localized: "Save Monthly"),
            systemImage: "banknote",
            tint: AppTheme.success
        ) {
            Text(String(localized: "Monthly savings target"))
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(formatMoney(monthly))
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(AppTheme.success)
                        .monospacedDigit()
                    Spacer(minLength: 0)
                }
                Slider(value: $monthlySavings, in: 100...50000, step: 100)
                    .tint(AppTheme.success)
            }

            HStack {
                Text(String(localized: "Savings goal"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                TextField("0", text: $goalText)
                    .financeNumericKeyboard()
                    .multilineTextAlignment(.trailing)
                    .font(.subheadline.weight(.semibold))
                    .frame(minWidth: 80, maxWidth: 140)
            }

            Divider()

            VStack(spacing: 8) {
                WhatIfResultRow(
                    label: String(localized: "Months to goal"),
                    value: monthsToGoal.map { formatDuration(months: $0) } ?? "–",
                    tint: AppTheme.primaryAccent
                )
                WhatIfResultRow(
                    label: String(localized: "Goal date"),
                    value: goalDateString,
                    tint: AppTheme.primaryAccent
                )
            }
        }
    }
}

// MARK: - Scenario 3: Pay Off Debt Faster

private struct PayOffDebtCard: View {
    let debts: [Debt]

    @State private var extraPaymentFraction: Double = 0

    private var activeDebt: Debt? {
        debts.filter { $0.remainingAmount > 0 }.max { $0.remainingAmount < $1.remainingAmount }
    }

    private var extraPayment: Decimal {
        guard let debt = activeDebt else { return .zero }
        return debt.minimumPayment * Decimal(extraPaymentFraction)
    }

    private var debtResult: DebtPayoffResult? {
        guard let debt = activeDebt else { return nil }
        return calculateDebtPayoff(debt: debt, extra: extraPayment)
    }

    var body: some View {
        ScenarioCard(
            title: String(localized: "Pay Off Debt Faster"),
            systemImage: "creditcard",
            tint: AppTheme.danger
        ) {
            if let debt = activeDebt {
                payoffContent(debt: debt)
            } else {
                Text(String(localized: "No debt data"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func payoffContent(debt: Debt) -> some View {
        Text(debt.name)
            .font(.caption)
            .foregroundStyle(.secondary)

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(formatMoney(debt.minimumPayment * Decimal(extraPaymentFraction)))
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(AppTheme.danger)
                    .monospacedDigit()
                Spacer(minLength: 0)
            }
            Text(String(localized: "Extra monthly payment"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Slider(value: $extraPaymentFraction, in: 0...2, step: 0.1)
                .tint(AppTheme.danger)
        }

        Divider()

        if let result = debtResult {
            VStack(spacing: 8) {
                WhatIfResultRow(
                    label: String(localized: "Months saved"),
                    value: formatDuration(months: result.monthsSaved),
                    tint: AppTheme.success
                )
                if result.interestSaved > 0 {
                    WhatIfResultRow(
                        label: String(localized: "Interest saved"),
                        value: formatMoney(result.interestSaved),
                        tint: AppTheme.success
                    )
                }
                WhatIfResultRow(
                    label: String(localized: "New payoff date"),
                    value: result.newPayoffDateString,
                    tint: AppTheme.primaryAccent
                )
            }
        }
    }
}

// MARK: - Debt payoff calculation

private struct DebtPayoffResult {
    let monthsSaved: Int
    let interestSaved: Decimal
    let newPayoffDateString: String
}

private func calculateDebtPayoff(debt: Debt, extra: Decimal) -> DebtPayoffResult {
    let remaining = debt.remainingAmount
    let rate = debt.interestRate
    let minPayment = debt.minimumPayment
    guard minPayment > 0, remaining > 0 else {
        return DebtPayoffResult(monthsSaved: 0, interestSaved: .zero, newPayoffDateString: "–")
    }

    func monthsToPayoff(balance: Decimal, annualRate: Decimal, payment: Decimal) -> Int {
        if annualRate == 0 {
            let b = NSDecimalNumber(decimal: balance).doubleValue
            let p = NSDecimalNumber(decimal: payment).doubleValue
            guard p > 0 else { return 360 }
            return max(1, Int(ceil(b / p)))
        }
        let r = NSDecimalNumber(decimal: annualRate / 1200).doubleValue
        let b = NSDecimalNumber(decimal: balance).doubleValue
        let p = NSDecimalNumber(decimal: payment).doubleValue
        guard p > b * r else { return 360 }
        let raw = ceil(log(p / (p - b * r)) / log(1 + r))
        return min(360, max(1, Int(raw)))
    }

    func totalInterest(balance: Decimal, annualRate: Decimal, payment: Decimal, monthCount: Int) -> Decimal {
        guard annualRate > 0 else { return .zero }
        return payment * Decimal(monthCount) - balance
    }

    let origMonths = monthsToPayoff(balance: remaining, annualRate: rate, payment: minPayment)
    let newMonths  = monthsToPayoff(balance: remaining, annualRate: rate, payment: minPayment + extra)
    let origInterest = totalInterest(balance: remaining, annualRate: rate, payment: minPayment, monthCount: origMonths)
    let newInterest  = totalInterest(balance: remaining, annualRate: rate, payment: minPayment + extra, monthCount: newMonths)
    let interestSaved = max(.zero, origInterest - newInterest)

    let cal = Calendar.current
    let newDate = cal.date(byAdding: .month, value: newMonths, to: Date()) ?? Date()
    let fmt = DateFormatter()
    fmt.dateFormat = "MMM yyyy"

    return DebtPayoffResult(
        monthsSaved: max(0, origMonths - newMonths),
        interestSaved: interestSaved,
        newPayoffDateString: fmt.string(from: newDate)
    )
}
