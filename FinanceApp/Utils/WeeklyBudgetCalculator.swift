import Foundation

struct WeeklyBudgetItem: Identifiable {
    var id: UUID { categoryId }

    let categoryId: UUID
    let categoryName: String
    let colorHex: String
    let iconName: String
    let weekStart: Date
    let weekEnd: Date
    let weeklyLimit: Decimal
    let weeklySpent: Decimal

    var remaining: Decimal { max(.zero, weeklyLimit - weeklySpent) }
    var overrun: Decimal { max(.zero, weeklySpent - weeklyLimit) }

    var ratio: Double {
        guard weeklyLimit > 0 else { return 0 }
        return NSDecimalNumber(decimal: weeklySpent / weeklyLimit).doubleValue
    }
}

enum WeeklyBudgetCalculator {
    private struct MonthCategoryKey: Hashable {
        let categoryId: UUID
        let month: Int
        let year: Int
    }

    static func items(
        referenceDate: Date = Date(),
        categories: [Category],
        budgets: [Budget],
        transactions: [Transaction],
        rolloverEnabled: Bool,
        calendar: Calendar = .current
    ) -> [WeeklyBudgetItem] {
        let expenseCategories = categories.filter { $0.type == .expense }
        guard !expenseCategories.isEmpty else { return [] }
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: referenceDate) else { return [] }

        let weekStart = calendar.startOfDay(for: weekInterval.start)
        guard
            let weekEndExclusive = calendar.date(byAdding: .day, value: 7, to: weekStart),
            let weekEnd = calendar.date(byAdding: .second, value: -1, to: weekEndExclusive)
        else {
            return []
        }

        var budgetByKey: [MonthCategoryKey: Budget] = [:]
        for budget in budgets {
            let key = MonthCategoryKey(categoryId: budget.categoryId, month: budget.month, year: budget.year)
            if budgetByKey[key] == nil {
                budgetByKey[key] = budget
            }
        }

        var monthlySpentByCategory: [MonthCategoryKey: Decimal] = [:]
        var weeklySpentByCategory: [UUID: Decimal] = [:]

        for txn in transactions where BalanceCalculator.isPosted(txn) && txn.type == .expense {
            guard let categoryId = txn.categoryId else { continue }

            let monthComps = calendar.dateComponents([.year, .month], from: txn.date)
            if let year = monthComps.year, let month = monthComps.month {
                let monthKey = MonthCategoryKey(categoryId: categoryId, month: month, year: year)
                monthlySpentByCategory[monthKey, default: .zero] += txn.amount
            }

            if txn.date >= weekStart && txn.date < weekEndExclusive {
                weeklySpentByCategory[categoryId, default: .zero] += txn.amount
            }
        }

        func previousMonth(from month: Int, year: Int) -> (month: Int, year: Int) {
            if month > 1 { return (month - 1, year) }
            return (12, year - 1)
        }

        var effectiveMonthlyLimitCache: [MonthCategoryKey: Decimal] = [:]

        func effectiveMonthlyLimit(categoryId: UUID, month: Int, year: Int) -> Decimal {
            let key = MonthCategoryKey(categoryId: categoryId, month: month, year: year)
            if let cached = effectiveMonthlyLimitCache[key] {
                return cached
            }

            guard let currentBudget = budgetByKey[key], currentBudget.limitAmount > 0 else {
                effectiveMonthlyLimitCache[key] = .zero
                return .zero
            }

            let base = currentBudget.limitAmount
            guard rolloverEnabled else {
                effectiveMonthlyLimitCache[key] = base
                return base
            }

            let prev = previousMonth(from: month, year: year)
            let prevKey = MonthCategoryKey(categoryId: categoryId, month: prev.month, year: prev.year)
            guard let previousBudget = budgetByKey[prevKey], previousBudget.limitAmount > 0 else {
                effectiveMonthlyLimitCache[key] = base
                return base
            }

            let previousSpent = monthlySpentByCategory[prevKey, default: .zero]
            let unused = max(.zero, previousBudget.limitAmount - previousSpent)
            let effective = base + unused
            effectiveMonthlyLimitCache[key] = effective
            return effective
        }

        var result: [WeeklyBudgetItem] = []

        for category in expenseCategories {
            var weeklyLimit: Decimal = .zero

            for dayOffset in 0..<7 {
                guard let day = calendar.date(byAdding: .day, value: dayOffset, to: weekStart) else { continue }
                let comps = calendar.dateComponents([.year, .month], from: day)
                guard let year = comps.year, let month = comps.month else { continue }

                let monthLimit = effectiveMonthlyLimit(categoryId: category.id, month: month, year: year)
                guard monthLimit > 0 else { continue }

                let daysInMonth = calendar.range(of: .day, in: .month, for: day)?.count ?? 30
                weeklyLimit += monthLimit / Decimal(daysInMonth)
            }

            guard weeklyLimit > 0 else { continue }

            result.append(
                WeeklyBudgetItem(
                    categoryId: category.id,
                    categoryName: category.name,
                    colorHex: category.colorHex,
                    iconName: category.iconName,
                    weekStart: weekStart,
                    weekEnd: weekEnd,
                    weeklyLimit: weeklyLimit,
                    weeklySpent: weeklySpentByCategory[category.id, default: .zero]
                )
            )
        }

        return result.sorted { lhs, rhs in
            if lhs.ratio != rhs.ratio {
                return lhs.ratio > rhs.ratio
            }
            if lhs.weeklySpent != rhs.weeklySpent {
                return lhs.weeklySpent > rhs.weeklySpent
            }
            return lhs.categoryName.localizedCaseInsensitiveCompare(rhs.categoryName) == .orderedAscending
        }
    }
}
