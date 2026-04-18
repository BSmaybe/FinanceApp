import Foundation

struct Achievement: Identifiable {
    let id: String
    let title: String
    let description: String
    let symbolName: String
    let xpReward: Int
}

enum AchievementStore {
    static let all: [Achievement] = [
        Achievement(
            id: "first_transaction",
            title: String(localized: "First record"),
            description: String(localized: "Add your first transaction"),
            symbolName: "plus.circle.fill",
            xpReward: 50
        ),
        Achievement(
            id: "budget_keeper",
            title: String(localized: "Month under plan"),
            description: String(localized: "Stay under budget for a full month"),
            symbolName: "checkmark.seal.fill",
            xpReward: 100
        ),
        Achievement(
            id: "debt_slayer",
            title: String(localized: "First debt closed"),
            description: String(localized: "Pay off your first debt"),
            symbolName: "creditcard.and.123",
            xpReward: 200
        ),
        Achievement(
            id: "goal_getter",
            title: String(localized: "Goal funded"),
            description: String(localized: "Complete your first financial goal"),
            symbolName: "flag.checkered.2.crossed",
            xpReward: 100
        ),
        Achievement(
            id: "seven_day_streak",
            title: String(localized: "Consistency week"),
            description: String(localized: "7 consecutive days with transactions"),
            symbolName: "calendar.badge.clock",
            xpReward: 70
        ),
        Achievement(
            id: "thirty_day_streak",
            title: String(localized: "Consistency month"),
            description: String(localized: "30 consecutive days with transactions"),
            symbolName: "calendar.badge.checkmark",
            xpReward: 300
        ),
        Achievement(
            id: "saver",
            title: String(localized: "Savings month"),
            description: String(localized: "Save rate ≥ 20% for a month"),
            symbolName: "leaf.circle.fill",
            xpReward: 150
        ),
        Achievement(
            id: "debt_free",
            title: String(localized: "Debt free"),
            description: String(localized: "All debts paid off"),
            symbolName: "checkmark.circle.fill",
            xpReward: 500
        ),
        Achievement(
            id: "portfolio",
            title: String(localized: "Account structure"),
            description: String(localized: "Have 3 or more accounts"),
            symbolName: "building.columns.fill",
            xpReward: 75
        ),
        Achievement(
            id: "planner",
            title: String(localized: "Planning habit"),
            description: String(localized: "Set budgets for 5 or more categories"),
            symbolName: "list.clipboard.fill",
            xpReward: 100
        ),
        Achievement(
            id: "legend",
            title: String(localized: "Long-term discipline"),
            description: String(localized: "Maintain healthy progress over time"),
            symbolName: "chart.line.uptrend.xyaxis.circle.fill",
            xpReward: 0
        ),
    ]

    static func checkUnlocked(
        transactions: [Transaction],
        goals: [Goal],
        debts: [Debt],
        budgets: [Budget],
        accounts: [Account],
        heroStats: HeroStats
    ) -> Set<String> {
        var unlocked = Set<String>()

        if !transactions.isEmpty {
            unlocked.insert("first_transaction")
        }

        if transactions.count >= 2 {
            let cal = Calendar.current
            let comps = cal.dateComponents([.year, .month], from: Date())
            let year = comps.year ?? 2025
            let month = comps.month ?? 1

            let monthTransactions = transactions.filter {
                let c = cal.dateComponents([.year, .month], from: $0.date)
                return c.year == year && c.month == month
            }

            let income = monthTransactions
                .filter { $0.type == .income }
                .reduce(Decimal.zero) { $0 + $1.amount }
            let expense = monthTransactions
                .filter { $0.type == .expense }
                .reduce(Decimal.zero) { $0 + $1.amount }

            if income > 0, expense < income {
                unlocked.insert("budget_keeper")
            }

            if income > 0 {
                let savings = income - expense
                let rateDouble = NSDecimalNumber(decimal: savings / income).doubleValue
                if rateDouble >= 0.20 {
                    unlocked.insert("saver")
                }
            }
        }

        if debts.contains(where: { $0.remainingAmount <= 0 }) {
            unlocked.insert("debt_slayer")
        }

        if goals.contains(where: { $0.progress >= 1.0 }) {
            unlocked.insert("goal_getter")
        }

        if heroStats.streak >= 7 {
            unlocked.insert("seven_day_streak")
        }

        if heroStats.streak >= 30 {
            unlocked.insert("thirty_day_streak")
        }

        if !debts.isEmpty, debts.allSatisfy({ $0.remainingAmount <= 0 }) {
            unlocked.insert("debt_free")
        }

        if accounts.count >= 3 {
            unlocked.insert("portfolio")
        }

        let uniqueBudgetCategories = Set(budgets.map { $0.categoryId })
        if uniqueBudgetCategories.count >= 5 {
            unlocked.insert("planner")
        }

        if heroStats.level >= 20 {
            unlocked.insert("legend")
        }

        return unlocked
    }
}
