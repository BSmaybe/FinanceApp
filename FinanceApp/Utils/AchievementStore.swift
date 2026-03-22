import Foundation

struct Achievement: Identifiable {
    let id: String
    let title: String
    let description: String
    let icon: String
    let xpReward: Int
}

enum AchievementStore {
    static let all: [Achievement] = [
        Achievement(
            id: "first_transaction",
            title: String(localized: "First Step"),
            description: String(localized: "Add your first transaction"),
            icon: "🥇",
            xpReward: 50
        ),
        Achievement(
            id: "budget_keeper",
            title: String(localized: "Budget Keeper"),
            description: String(localized: "Stay under budget for a full month"),
            icon: "💰",
            xpReward: 100
        ),
        Achievement(
            id: "debt_slayer",
            title: String(localized: "Debt Slayer"),
            description: String(localized: "Pay off your first debt"),
            icon: "💪",
            xpReward: 200
        ),
        Achievement(
            id: "goal_getter",
            title: String(localized: "Goal Getter"),
            description: String(localized: "Complete your first financial goal"),
            icon: "🎯",
            xpReward: 100
        ),
        Achievement(
            id: "seven_day_streak",
            title: String(localized: "7-Day Streak"),
            description: String(localized: "7 consecutive days with transactions"),
            icon: "📅",
            xpReward: 70
        ),
        Achievement(
            id: "thirty_day_streak",
            title: String(localized: "30-Day Streak"),
            description: String(localized: "30 consecutive days with transactions"),
            icon: "🗓️",
            xpReward: 300
        ),
        Achievement(
            id: "saver",
            title: String(localized: "Saver"),
            description: String(localized: "Save rate ≥ 20% for a month"),
            icon: "🐷",
            xpReward: 150
        ),
        Achievement(
            id: "big_spender",
            title: String(localized: "Big Spender"),
            description: String(localized: "Single transaction over 10,000"),
            icon: "💸",
            xpReward: 25
        ),
        Achievement(
            id: "debt_free",
            title: String(localized: "Debt Free"),
            description: String(localized: "All debts paid off"),
            icon: "🏅",
            xpReward: 500
        ),
        Achievement(
            id: "portfolio",
            title: String(localized: "Portfolio"),
            description: String(localized: "Have 3 or more accounts"),
            icon: "🏦",
            xpReward: 75
        ),
        Achievement(
            id: "planner",
            title: String(localized: "Planner"),
            description: String(localized: "Set budgets for 5 or more categories"),
            icon: "📋",
            xpReward: 100
        ),
        Achievement(
            id: "legend",
            title: String(localized: "Legend"),
            description: String(localized: "Reach Level 20"),
            icon: "🏆",
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

        if transactions.contains(where: { $0.amount > 10_000 }) {
            unlocked.insert("big_spender")
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
