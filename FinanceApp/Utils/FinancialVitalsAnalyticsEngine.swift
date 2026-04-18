import Foundation

// MARK: - LightweightVitalsEngine

/// Computes proxy vitals scores from transactions only (no budgets/debts needed).
/// Used for timeline generation where full FinancialVitalsEngine data isn't available per-day.
enum LightweightVitalsEngine {

    static func readiness(expenses: Decimal, income: Decimal) -> Int {
        guard income > 0 else { return expenses == 0 ? 50 : 10 }
        let ratio = NSDecimalNumber(decimal: expenses / income).doubleValue
        switch ratio {
        case ..<0.5:  return 90
        case ..<0.7:  return 75
        case ..<0.85: return 60
        case ..<1.0:  return 45
        case ..<1.2:  return 30
        default:      return 10
        }
    }

    static func pressure(expenses: Decimal, income: Decimal) -> Int {
        guard income > 0 else { return expenses == 0 ? 20 : 90 }
        let ratio = NSDecimalNumber(decimal: expenses / income).doubleValue
        switch ratio {
        case ..<0.5:  return 15
        case ..<0.7:  return 30
        case ..<0.85: return 50
        case ..<1.0:  return 65
        case ..<1.2:  return 80
        default:      return 95
        }
    }

    static func reserve(income: Decimal, expenses: Decimal) -> Int {
        let net = income - expenses
        guard income > 0 else { return 10 }
        let ratio = NSDecimalNumber(decimal: net / income).doubleValue
        switch ratio {
        case 0.3...:    return 90
        case 0.2..<0.3: return 75
        case 0.1..<0.2: return 55
        case 0.0..<0.1: return 35
        default:        return 10
        }
    }
}

// MARK: - FinancialVitalsAnalyticsEngine

enum FinancialVitalsAnalyticsEngine {

    /// Build a timeline of vitals points over the given period.
    static func timeline(
        transactions: [Transaction],
        period: AnalyticsPeriod
    ) -> FinancialVitalsTimeline {
        let points: [FinancialVitalsPoint]
        switch period {
        case .week:   points = dailyPoints(transactions: transactions, days: 7)
        case .month:  points = dailyPoints(transactions: transactions, days: 30)
        case .year:   points = monthlyPoints(transactions: transactions, months: 12)
        }
        return FinancialVitalsTimeline(points: points, period: period)
    }

    // MARK: - Private helpers

    private static func dailyPoints(transactions: [Transaction], days: Int) -> [FinancialVitalsPoint] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<days).reversed().compactMap { offset -> FinancialVitalsPoint? in
            guard let dayStart = calendar.date(byAdding: .day, value: -offset, to: today),
                  let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
            let income = sum(transactions, from: dayStart, to: dayEnd, type: .income)
            let expenses = sum(transactions, from: dayStart, to: dayEnd, type: .expense)
            return FinancialVitalsPoint(
                date: dayStart,
                readiness: LightweightVitalsEngine.readiness(expenses: expenses, income: income),
                pressure:  LightweightVitalsEngine.pressure(expenses: expenses, income: income),
                reserve:   LightweightVitalsEngine.reserve(income: income, expenses: expenses)
            )
        }
    }

    private static func monthlyPoints(transactions: [Transaction], months: Int) -> [FinancialVitalsPoint] {
        let calendar = Calendar.current
        let today = Date()
        return (0..<months).reversed().compactMap { offset -> FinancialVitalsPoint? in
            guard let monthDate = calendar.date(byAdding: .month, value: -offset, to: today) else { return nil }
            let comps = calendar.dateComponents([.year, .month], from: monthDate)
            guard let month = comps.month, let year = comps.year,
                  let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
                  let end   = calendar.date(byAdding: .month, value: 1, to: start) else { return nil }
            let income   = sum(transactions, from: start, to: end, type: .income)
            let expenses = sum(transactions, from: start, to: end, type: .expense)
            return FinancialVitalsPoint(
                date: start,
                readiness: LightweightVitalsEngine.readiness(expenses: expenses, income: income),
                pressure:  LightweightVitalsEngine.pressure(expenses: expenses, income: income),
                reserve:   LightweightVitalsEngine.reserve(income: income, expenses: expenses)
            )
        }
    }

    private static func sum(
        _ transactions: [Transaction],
        from start: Date,
        to end: Date,
        type txType: TransactionType
    ) -> Decimal {
        transactions
            .filter { $0.type == txType && $0.date >= start && $0.date < end }
            .reduce(Decimal.zero) { $0 + $1.amount }
    }
}

// MARK: - FinancialVitalsDriverEngine

enum FinancialVitalsDriverEngine {

    @MainActor
    static func drivers(
        vitals: FinancialVitals,
        transactions: [Transaction],
        categories: [Category],
        budgets: [Budget],
        debts: [Debt],
        month: Int,
        year: Int
    ) -> [FinancialVitalsDriver] {
        var result: [FinancialVitalsDriver] = []

        // Positive: income present this month
        let income = monthlyTotal(transactions, month: month, year: year, type: .income)
        if income > 0 {
            result.append(FinancialVitalsDriver(
                id: "income_present",
                title: String(localized: "Income recorded this month"),
                explanation: String(localized: "Having income logged keeps your readiness score anchored."),
                impact: .helps,
                cta: .transactions
            ))
        }

        // Negative: budget overruns
        let overrunBudgets = budgets.filter { b in
            guard b.month == month, b.year == year else { return false }
            let spent = monthlySpend(transactions, categoryId: b.categoryId, month: month, year: year)
            return spent > b.limitAmount
        }
        if !overrunBudgets.isEmpty {
            result.append(FinancialVitalsDriver(
                id: "budget_overrun",
                title: String(format: String(localized: "%lld budget(s) exceeded"), Int64(overrunBudgets.count)),
                explanation: String(localized: "Overspending in budgeted categories raises pressure and lowers reserve."),
                impact: .hurts,
                cta: .budgets
            ))
        }

        // Negative: active debts (remaining > 0)
        let activeDebts = debts.filter { $0.remainingAmount > 0 }
        if !activeDebts.isEmpty {
            let totalDebt = activeDebts.reduce(Decimal.zero) { $0 + $1.remainingAmount }
            result.append(FinancialVitalsDriver(
                id: "active_debts",
                title: String(localized: "Active debts outstanding"),
                explanation: String(format: String(localized: "Outstanding balance of %@ reduces your reserve score."), CurrencyFormatter.string(from: totalDebt)),
                impact: .hurts,
                cta: .debts
            ))
        }

        // Positive or negative: runway
        if vitals.runwayDays >= 14 {
            result.append(FinancialVitalsDriver(
                id: "runway_ok",
                title: String(format: String(localized: "%lld-day runway"), Int64(vitals.runwayDays)),
                explanation: String(localized: "Your current balance covers expenses for a healthy buffer period."),
                impact: .helps,
                cta: .analytics
            ))
        } else {
            result.append(FinancialVitalsDriver(
                id: "runway_short",
                title: String(format: String(localized: "Short runway: %lld days"), Int64(vitals.runwayDays)),
                explanation: String(localized: "Balance may not cover upcoming expenses comfortably."),
                impact: .hurts,
                cta: .analytics
            ))
        }

        // Positive: budget stability >= 80
        if vitals.budgetStability >= 80 {
            result.append(FinancialVitalsDriver(
                id: "budget_stable",
                title: String(localized: "Budget discipline is strong"),
                explanation: String(format: String(localized: "%lld%% of budgets are on track."), Int64(vitals.budgetStability)),
                impact: .helps,
                cta: .budgets
            ))
        }

        // Sort: hurts first so user sees problems at the top
        return result.sorted { a, b in
            if a.impact == b.impact { return false }
            return a.impact == .hurts
        }
    }

    // MARK: - Helpers

    private static func monthlyTotal(
        _ transactions: [Transaction],
        month: Int,
        year: Int,
        type txType: TransactionType
    ) -> Decimal {
        transactions
            .filter { t in
                t.type == txType &&
                Calendar.current.component(.month, from: t.date) == month &&
                Calendar.current.component(.year,  from: t.date) == year
            }
            .reduce(Decimal.zero) { $0 + $1.amount }
    }

    private static func monthlySpend(
        _ transactions: [Transaction],
        categoryId: UUID,
        month: Int,
        year: Int
    ) -> Decimal {
        transactions
            .filter { t in
                t.type == .expense &&
                t.categoryId == categoryId &&
                Calendar.current.component(.month, from: t.date) == month &&
                Calendar.current.component(.year,  from: t.date) == year
            }
            .reduce(Decimal.zero) { $0 + $1.amount }
    }
}
