import SwiftUI
import SwiftData

// MARK: - Scenario enum

enum WhatIfScenario: String, CaseIterable {
    case goal = "Save More"
    case budget = "Spend Less"
    case debt = "Extra Payment"
}

// MARK: - WhatIfCalculator

private enum WhatIfCalculator {

    // Scenario A
    struct GoalResult {
        let months: Int?
        let reachDate: Date?
        let totalSaved: Decimal
    }

    static func goalResult(
        target: Decimal,
        saved: Decimal,
        monthly: Decimal
    ) -> GoalResult {
        let remaining = max(.zero, target - saved)
        guard monthly > 0 else {
            return GoalResult(months: nil, reachDate: nil, totalSaved: saved)
        }
        let remainingDouble = NSDecimalNumber(decimal: remaining).doubleValue
        let monthlyDouble   = NSDecimalNumber(decimal: monthly).doubleValue
        let months = Int(ceil(remainingDouble / monthlyDouble))
        let reachDate = Calendar.current.date(byAdding: .month, value: months, to: Date())
        let totalSaved = saved + monthly * Decimal(months)
        return GoalResult(months: months, reachDate: reachDate, totalSaved: totalSaved)
    }

    // Scenario B
    struct BudgetResult {
        let monthlySaving: Decimal
        let annualSaving: Decimal
    }

    static func budgetResult(
        currentExpense: Decimal,
        reductionPercent: Decimal
    ) -> BudgetResult {
        let monthly = currentExpense * (reductionPercent / 100)
        return BudgetResult(monthlySaving: monthly, annualSaving: monthly * 12)
    }

    // Scenario C — single-debt payoff with / without extra payment
    struct DebtResult {
        let originalMonths: Int
        let newMonths: Int
        let monthsSaved: Int
        let interestSaved: Decimal
        let originalPayoffDate: Date
        let newPayoffDate: Date
    }

    static func debtResult(
        remaining: Decimal,
        annualRate: Decimal,
        minPayment: Decimal,
        extraPayment: Decimal
    ) -> DebtResult? {
        guard minPayment > 0, remaining > 0 else { return nil }

        func months(balance: Decimal, rate: Decimal, payment: Decimal) -> Int {
            // Interest-free (installment / 0% rate)
            if rate == 0 {
                let bal = NSDecimalNumber(decimal: balance).doubleValue
                let pay = NSDecimalNumber(decimal: payment).doubleValue
                return max(1, Int(ceil(bal / pay)))
            }
            let r   = NSDecimalNumber(decimal: rate / 1200).doubleValue
            let b   = NSDecimalNumber(decimal: balance).doubleValue
            let p   = NSDecimalNumber(decimal: payment).doubleValue
            guard p > b * r else { return 360 } // payment doesn't cover interest
            let raw = ceil(log(p / (p - b * r)) / log(1 + r))
            return min(360, max(1, Int(raw)))
        }

        func totalInterest(balance: Decimal, rate: Decimal, payment: Decimal, monthCount: Int) -> Decimal {
            if rate == 0 { return .zero }
            return payment * Decimal(monthCount) - balance
        }

        let origMonths  = months(balance: remaining, rate: annualRate, payment: minPayment)
        let newMonths   = months(balance: remaining, rate: annualRate, payment: minPayment + extraPayment)
        let origInterest = totalInterest(balance: remaining, rate: annualRate, payment: minPayment, monthCount: origMonths)
        let newInterest  = totalInterest(balance: remaining, rate: annualRate, payment: minPayment + extraPayment, monthCount: newMonths)
        let saved = max(.zero, origInterest - newInterest)

        let cal = Calendar.current
        let now = Date()
        return DebtResult(
            originalMonths: origMonths,
            newMonths: newMonths,
            monthsSaved: max(0, origMonths - newMonths),
            interestSaved: saved,
            originalPayoffDate: cal.date(byAdding: .month, value: origMonths, to: now) ?? now,
            newPayoffDate: cal.date(byAdding: .month, value: newMonths, to: now) ?? now
        )
    }
}

// MARK: - WhatIfView

struct WhatIfView: View {
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query(sort: \Goal.createdDate) private var goals: [Goal]
    @Query(sort: \Debt.name) private var debts: [Debt]

    @State private var selectedScenario: WhatIfScenario = .goal

    var body: some View {
        Form {
            Section {
                Picker(String(localized: "Scenario"), selection: $selectedScenario) {
                    ForEach(WhatIfScenario.allCases, id: \.self) { s in
                        Text(String(localized: String.LocalizationValue(s.rawValue))).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            switch selectedScenario {
            case .goal:   ScenarioGoalView(goals: goals)
            case .budget: ScenarioBudgetView(transactions: transactions, goals: goals)
            case .debt:   ScenarioDebtView(debts: debts)
            }
        }
        .navigationTitle(String(localized: "What-If Scenarios"))
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - Scenario A: Save More

private struct ScenarioGoalView: View {
    let goals: [Goal]

    @State private var targetText: String = ""
    @State private var savedText: String  = ""
    @State private var monthlySavings: Double = 500

    private var target: Decimal  { Decimal(string: targetText) ?? .zero }
    private var saved: Decimal   { Decimal(string: savedText)  ?? .zero }
    private var monthly: Decimal { Decimal(monthlySavings) }
    private var result: WhatIfCalculator.GoalResult {
        WhatIfCalculator.goalResult(target: target, saved: saved, monthly: monthly)
    }

    private var monthYear: DateFormatter {
        let f = DateFormatter(); f.dateFormat = "MMM yyyy"; return f
    }

    var body: some View {
        Section(String(localized: "Goal")) {
            TextField(String(localized: "Enter amount"), text: $targetText)
                .keyboardType(.decimalPad)
                .overlay(alignment: .leading) {
                    Text(String(localized: "Target Amount"))
                        .foregroundStyle(.secondary)
                        .allowsHitTesting(false)
                        .opacity(targetText.isEmpty ? 1 : 0)
                }
            if let first = goals.first {
                Button {
                    targetText = (first.targetAmount as NSDecimalNumber).stringValue
                    savedText  = (first.currentAmount as NSDecimalNumber).stringValue
                } label: {
                    Label(first.name, systemImage: "flag")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryAccent)
                }
            }
        }

        Section(String(localized: "Current Amount")) {
            TextField(String(localized: "Enter amount"), text: $savedText)
                .keyboardType(.decimalPad)
        }

        Section {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(String(localized: "Monthly Savings"))
                    Spacer()
                    Text(CurrencyFormatter.string(from: monthly))
                        .foregroundStyle(.secondary)
                }
                Slider(value: $monthlySavings, in: 0...10000, step: 50)
                    .tint(AppTheme.primaryAccent)
            }
        } header: {
            Text(String(localized: "Monthly Savings"))
        }

        Section {
            ResultCard {
                if let months = result.months, let date = result.reachDate {
                    ResultRow(
                        label: String(localized: "Months to Goal"),
                        value: "\(months)",
                        color: AppTheme.success
                    )
                    ResultRow(
                        label: String(localized: "Estimated Date"),
                        value: monthYear.string(from: date),
                        color: AppTheme.success
                    )
                    ResultRow(
                        label: String(localized: "Total Saved"),
                        value: CurrencyFormatter.string(from: result.totalSaved),
                        color: AppTheme.primaryAccent
                    )
                } else {
                    Text(String(localized: "Enter a monthly savings amount"))
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
            }
        } header: {
            Text(String(localized: "Results"))
        }
    }
}

// MARK: - Scenario B: Spend Less

private struct ScenarioBudgetView: View {
    let transactions: [Transaction]
    let goals: [Goal]

    @State private var expenseText: String = ""
    @State private var reductionPercent: Double = 10
    @State private var goalAmountText: String = ""

    private var currentExpense: Decimal { Decimal(string: expenseText) ?? .zero }
    private var reduction: Decimal      { Decimal(reductionPercent) }
    private var goalTarget: Decimal     { Decimal(string: goalAmountText) ?? .zero }

    private var result: WhatIfCalculator.BudgetResult {
        WhatIfCalculator.budgetResult(currentExpense: currentExpense, reductionPercent: reduction)
    }

    private var monthsToGoal: Int? {
        guard result.monthlySaving > 0, goalTarget > 0 else { return nil }
        let v = NSDecimalNumber(decimal: goalTarget / result.monthlySaving).doubleValue
        return Int(ceil(v))
    }

    var body: some View {
        Section(String(localized: "Current Monthly Expense")) {
            HStack {
                TextField(String(localized: "Enter amount"), text: $expenseText)
                    .keyboardType(.decimalPad)
                if let prefill = currentMonthExpense, expenseText.isEmpty {
                    Button {
                        expenseText = (prefill as NSDecimalNumber).stringValue
                    } label: {
                        Text(String(localized: "Use actual"))
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryAccent)
                    }
                }
            }
        }

        Section {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(String(localized: "Reduction"))
                    Spacer()
                    Text("\(Int(reductionPercent))%")
                        .foregroundStyle(.secondary)
                }
                Slider(value: $reductionPercent, in: 0...50, step: 5)
                    .tint(AppTheme.primaryAccent)
            }
        } header: {
            Text(String(localized: "Reduction"))
        }

        Section(String(localized: "Goal Amount (optional)")) {
            if let first = goals.first {
                HStack {
                    TextField(String(localized: "Enter amount"), text: $goalAmountText)
                        .keyboardType(.decimalPad)
                    Button {
                        goalAmountText = (first.targetAmount as NSDecimalNumber).stringValue
                    } label: {
                        Text(first.name)
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryAccent)
                    }
                }
            } else {
                TextField(String(localized: "Enter amount"), text: $goalAmountText)
                    .keyboardType(.decimalPad)
            }
        }

        Section {
            ResultCard {
                ResultRow(
                    label: String(localized: "Monthly Savings"),
                    value: CurrencyFormatter.string(from: result.monthlySaving),
                    color: AppTheme.success
                )
                ResultRow(
                    label: String(localized: "Annual Savings"),
                    value: CurrencyFormatter.string(from: result.annualSaving),
                    color: AppTheme.success
                )
                if let m = monthsToGoal {
                    ResultRow(
                        label: String(localized: "Months to Goal"),
                        value: "\(m)",
                        color: AppTheme.primaryAccent
                    )
                }
            }
        } header: {
            Text(String(localized: "Results"))
        }
    }

    private var currentMonthExpense: Decimal? {
        let cal = Calendar.current
        let now = Date()
        let comps = cal.dateComponents([.year, .month], from: now)
        var total: Decimal = .zero
        for txn in transactions {
            guard txn.type == .expense else { continue }
            let tc = cal.dateComponents([.year, .month], from: txn.date)
            if tc.year == comps.year && tc.month == comps.month {
                total += txn.amount
            }
        }
        return total > 0 ? total : nil
    }
}

// MARK: - Scenario C: Extra Payment

private struct ScenarioDebtView: View {
    let debts: [Debt]

    @State private var selectedDebtID: UUID?
    @State private var extraPaymentText: String = ""

    // Manual entry for when there are no debts
    @State private var manualRemainingText: String  = ""
    @State private var manualRateText: String       = ""
    @State private var manualMinPaymentText: String = ""

    private var extra: Decimal { Decimal(string: extraPaymentText) ?? .zero }

    private var selectedDebt: Debt? {
        debts.first { $0.id == selectedDebtID }
    }

    private var result: WhatIfCalculator.DebtResult? {
        if let debt = selectedDebt {
            return WhatIfCalculator.debtResult(
                remaining:    debt.remainingAmount,
                annualRate:   debt.interestRate,
                minPayment:   debt.minimumPayment,
                extraPayment: extra
            )
        }
        // manual entry
        let remaining   = Decimal(string: manualRemainingText)  ?? .zero
        let rate        = Decimal(string: manualRateText)        ?? .zero
        let minPayment  = Decimal(string: manualMinPaymentText)  ?? .zero
        guard remaining > 0, minPayment > 0 else { return nil }
        return WhatIfCalculator.debtResult(
            remaining:    remaining,
            annualRate:   rate,
            minPayment:   minPayment,
            extraPayment: extra
        )
    }

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM yyyy"; return f
    }()

    var body: some View {
        if debts.isEmpty {
            Section(String(localized: "Debt Details")) {
                TextField(String(localized: "Remaining Balance"), text: $manualRemainingText)
                    .keyboardType(.decimalPad)
                TextField(String(localized: "Annual Interest Rate (%)"), text: $manualRateText)
                    .keyboardType(.decimalPad)
                TextField(String(localized: "Minimum Payment"), text: $manualMinPaymentText)
                    .keyboardType(.decimalPad)
            }
        } else {
            Section(String(localized: "Select a debt")) {
                Picker(String(localized: "Select a debt"), selection: $selectedDebtID) {
                    Text(String(localized: "Manual Entry")).tag(Optional<UUID>.none)
                    ForEach(debts) { debt in
                        Text(debt.name).tag(Optional(debt.id))
                    }
                }
                if selectedDebt == nil {
                    TextField(String(localized: "Remaining Balance"), text: $manualRemainingText)
                        .keyboardType(.decimalPad)
                    TextField(String(localized: "Annual Interest Rate (%)"), text: $manualRateText)
                        .keyboardType(.decimalPad)
                    TextField(String(localized: "Minimum Payment"), text: $manualMinPaymentText)
                        .keyboardType(.decimalPad)
                } else if let debt = selectedDebt {
                    LabeledContent(String(localized: "Remaining"), value: CurrencyFormatter.string(from: debt.remainingAmount))
                    LabeledContent(
                        String(localized: "Min Payment"),
                        value: CurrencyFormatter.string(from: debt.minimumPayment)
                    )
                }
            }
        }

        Section(String(localized: "Extra Payment")) {
            TextField(String(localized: "Enter amount"), text: $extraPaymentText)
                .keyboardType(.decimalPad)
        }

        Section {
            ResultCard {
                if let r = result {
                    ResultRow(
                        label: String(localized: "Original Payoff"),
                        value: dateFormatter.string(from: r.originalPayoffDate),
                        color: .secondary
                    )
                    ResultRow(
                        label: String(localized: "New Payoff"),
                        value: dateFormatter.string(from: r.newPayoffDate),
                        color: AppTheme.success
                    )
                    ResultRow(
                        label: String(localized: "Months Saved"),
                        value: "\(r.monthsSaved)",
                        color: AppTheme.success
                    )
                    if r.interestSaved > 0 {
                        ResultRow(
                            label: String(localized: "Interest Saved"),
                            value: CurrencyFormatter.string(from: r.interestSaved),
                            color: AppTheme.success
                        )
                    }
                } else {
                    Text(String(localized: "Enter debt details above"))
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
            }
        } header: {
            Text(String(localized: "Results"))
        }
    }
}

// MARK: - Shared sub-views

private struct ResultCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowBackground(Color.clear)
    }
}

private struct ResultRow: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .font(.subheadline.bold())
                .foregroundStyle(color)
        }
    }
}
