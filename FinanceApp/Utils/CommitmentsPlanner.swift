import Foundation

enum CommitmentScheduleSource {
    case debt
    case subscription
    case recurring
}

struct CommitmentScheduleItem: Identifiable {
    let id: String
    let title: String
    let amount: Decimal
    let date: Date
    let source: CommitmentScheduleSource
    let transactionType: TransactionType

    var isExpense: Bool { transactionType == .expense }
    var isIncome: Bool { transactionType == .income }
    var isTransfer: Bool { transactionType == .transfer }
}

enum CommitmentsPlanner {
    static func nextOccurrence(
        for recurring: RecurringTransaction,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Date? {
        let today = calendar.startOfDay(for: referenceDate)
        return nextRecurringDate(recurring: recurring, from: today, calendar: calendar)
    }

    static func monthlyEquivalent(amount: Decimal, frequency: RecurringFrequency) -> Decimal {
        switch frequency {
        case .daily:
            return amount * 30
        case .weekly:
            return amount * Decimal(52) / Decimal(12)
        case .monthly:
            return amount
        case .yearly:
            return amount / 12
        }
    }

    static func monthlyOutflow(
        debts: [Debt],
        subscriptions: [Subscription],
        recurringTransactions: [RecurringTransaction]
    ) -> Decimal {
        let debtLoad = debts
            .filter { $0.remainingAmount > 0 }
            .reduce(Decimal.zero) { $0 + min($1.remainingAmount, $1.minimumPayment) }

        let subscriptionLoad = subscriptions
            .filter(\.isActive)
            .reduce(Decimal.zero) { $0 + $1.monthlyCost }

        let recurringLoad = recurringTransactions
            .filter { $0.isActive && $0.type == .expense }
            .reduce(Decimal.zero) { $0 + monthlyEquivalent(amount: $1.amount, frequency: $1.frequency) }

        return debtLoad + subscriptionLoad + recurringLoad
    }

    static func monthlyInflow(recurringTransactions: [RecurringTransaction]) -> Decimal {
        recurringTransactions
            .filter { $0.isActive && $0.type == .income }
            .reduce(Decimal.zero) { $0 + monthlyEquivalent(amount: $1.amount, frequency: $1.frequency) }
    }

    static func upcomingItems(
        debts: [Debt],
        subscriptions: [Subscription],
        recurringTransactions: [RecurringTransaction],
        referenceDate: Date = Date(),
        limit: Int? = nil,
        includeRecurringIncome: Bool = true
    ) -> [CommitmentScheduleItem] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: referenceDate)

        var items: [CommitmentScheduleItem] = []

        for debt in debts where debt.remainingAmount > 0 && debt.minimumPayment > 0 {
            let amount = min(debt.remainingAmount, debt.minimumPayment)
            guard amount > 0 else { continue }
            guard let nextDate = nextDebtDueDate(for: debt, from: today, calendar: calendar) else { continue }

            items.append(
                CommitmentScheduleItem(
                    id: "debt-\(debt.id.uuidString)-\(nextDate.timeIntervalSince1970)",
                    title: debt.name,
                    amount: amount,
                    date: nextDate,
                    source: .debt,
                    transactionType: .expense
                )
            )
        }

        for subscription in subscriptions where subscription.isActive {
            guard let nextDate = nextScheduledDate(
                startDate: subscription.nextBillingDate,
                frequency: subscription.frequency,
                from: today,
                calendar: calendar
            ) else { continue }

            items.append(
                CommitmentScheduleItem(
                    id: "subscription-\(subscription.id.uuidString)-\(nextDate.timeIntervalSince1970)",
                    title: subscription.name,
                    amount: subscription.amount,
                    date: nextDate,
                    source: .subscription,
                    transactionType: .expense
                )
            )
        }

        for recurring in recurringTransactions where recurring.isActive {
            if recurring.type == .income && !includeRecurringIncome { continue }
            guard let nextDate = nextRecurringDate(recurring: recurring, from: today, calendar: calendar) else { continue }

            let trimmedTitle = recurring.title.trimmingCharacters(in: .whitespacesAndNewlines)
            items.append(
                CommitmentScheduleItem(
                    id: "recurring-\(recurring.id.uuidString)-\(nextDate.timeIntervalSince1970)",
                    title: trimmedTitle.isEmpty ? recurring.type.localizedName : trimmedTitle,
                    amount: recurring.amount,
                    date: nextDate,
                    source: .recurring,
                    transactionType: recurring.type
                )
            )
        }

        let sorted = items.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            if $0.isExpense != $1.isExpense { return $0.isExpense }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }

        if let limit {
            return Array(sorted.prefix(limit))
        }
        return sorted
    }

    private static func nextRecurringDate(
        recurring: RecurringTransaction,
        from today: Date,
        calendar: Calendar
    ) -> Date? {
        let startDate = calendar.startOfDay(for: recurring.startDate)

        if startDate > today {
            return startDate
        }

        if let lastGeneratedDate = recurring.lastGeneratedDate {
            let normalizedLast = calendar.startOfDay(for: lastGeneratedDate)
            if let nextAfterLast = nextDate(after: normalizedLast, frequency: recurring.frequency, calendar: calendar) {
                return advanceToToday(candidate: nextAfterLast, frequency: recurring.frequency, today: today, calendar: calendar)
            }
        }

        return nextScheduledDate(
            startDate: startDate,
            frequency: recurring.frequency,
            from: today,
            calendar: calendar
        )
    }

    private static func nextScheduledDate(
        startDate: Date,
        frequency: RecurringFrequency,
        from today: Date,
        calendar: Calendar
    ) -> Date? {
        let normalizedStart = calendar.startOfDay(for: startDate)
        if normalizedStart >= today {
            return normalizedStart
        }
        return advanceToToday(candidate: normalizedStart, frequency: frequency, today: today, calendar: calendar)
    }

    private static func advanceToToday(
        candidate: Date,
        frequency: RecurringFrequency,
        today: Date,
        calendar: Calendar
    ) -> Date? {
        var current = candidate
        var safety = 0

        while current < today && safety < 800 {
            guard let next = nextDate(after: current, frequency: frequency, calendar: calendar) else { break }
            current = next
            safety += 1
        }

        return current >= today ? current : nil
    }

    private static func nextDebtDueDate(
        for debt: Debt,
        from today: Date,
        calendar: Calendar
    ) -> Date? {
        guard debt.dueDay > 0 else { return nil }

        func dueDate(in monthDate: Date) -> Date {
            var components = calendar.dateComponents([.year, .month], from: monthDate)
            let daysInMonth = calendar.range(of: .day, in: .month, for: monthDate)?.count ?? 30
            components.day = min(max(debt.dueDay, 1), daysInMonth)
            return calendar.startOfDay(for: calendar.date(from: components) ?? monthDate)
        }

        let currentMonthDueDate = dueDate(in: today)
        if currentMonthDueDate >= today {
            return currentMonthDueDate
        }

        guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: today) else { return nil }
        return dueDate(in: nextMonth)
    }

    private static func nextDate(
        after date: Date,
        frequency: RecurringFrequency,
        calendar: Calendar
    ) -> Date? {
        switch frequency {
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: date)
        case .weekly:
            return calendar.date(byAdding: .day, value: 7, to: date)
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: date)
        case .yearly:
            return calendar.date(byAdding: .year, value: 1, to: date)
        }
    }
}
