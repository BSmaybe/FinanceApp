import Foundation

enum DebtPayoffCalculator {
    struct PayoffResult: Identifiable {
        let id: UUID
        let name: String
        let monthsToPayoff: Int
        let totalInterestPaid: Decimal
        let payoffDate: Date
    }

    enum Strategy: String, CaseIterable {
        case snowball = "Snowball"
        case avalanche = "Avalanche"

        var localizedName: String {
            String(localized: String.LocalizationValue(rawValue))
        }
    }

    static func calculate(debts: [Debt], extraMonthlyPayment: Decimal, strategy: Strategy) -> [PayoffResult] {
        guard !debts.isEmpty else { return [] }

        struct DebtState {
            let id: UUID
            let name: String
            var remaining: Decimal
            let monthlyRate: Decimal
            let minPayment: Decimal
            var interestPaid: Decimal = .zero
            var paidOffMonth: Int?
        }

        var states: [DebtState] = debts.filter { $0.remainingAmount > 0 }.map { debt in
            DebtState(
                id: debt.id,
                name: debt.name,
                remaining: debt.remainingAmount,
                monthlyRate: debt.interestRate / 12,
                minPayment: debt.minimumPayment
            )
        }

        // Sort by strategy
        switch strategy {
        case .snowball:
            states.sort { $0.remaining < $1.remaining }
        case .avalanche:
            states.sort { $0.monthlyRate > $1.monthlyRate }
        }

        var month = 0
        let maxMonths = 360 // 30 years cap

        while states.contains(where: { $0.paidOffMonth == nil }) && month < maxMonths {
            month += 1

            // Apply monthly interest
            for i in states.indices where states[i].paidOffMonth == nil {
                let interest = states[i].remaining * states[i].monthlyRate
                states[i].remaining += interest
                states[i].interestPaid += interest
            }

            // Apply minimum payments first
            for i in states.indices where states[i].paidOffMonth == nil {
                let payment = min(states[i].minPayment, states[i].remaining)
                states[i].remaining -= payment
                if states[i].remaining <= 0 {
                    states[i].remaining = .zero
                    states[i].paidOffMonth = month
                }
            }

            // Funnel extra payment to first unpaid debt (in strategy order)
            var extraLeft = extraMonthlyPayment
            for i in states.indices where states[i].paidOffMonth == nil && extraLeft > 0 {
                let payment = min(extraLeft, states[i].remaining)
                states[i].remaining -= payment
                extraLeft -= payment
                if states[i].remaining <= 0 {
                    states[i].remaining = .zero
                    states[i].paidOffMonth = month
                }
                break // snowball/avalanche: all extra goes to one target
            }
        }

        let cal = Calendar.current
        let now = Date()
        return states.map { state in
            let months = state.paidOffMonth ?? maxMonths
            let payoffDate = cal.date(byAdding: .month, value: months, to: now) ?? now
            return PayoffResult(
                id: state.id,
                name: state.name,
                monthsToPayoff: months,
                totalInterestPaid: state.interestPaid,
                payoffDate: payoffDate
            )
        }
    }
}
