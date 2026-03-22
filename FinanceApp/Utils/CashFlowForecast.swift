import Foundation

enum CashFlowForecast {
    struct DailyForecast: Identifiable {
        let id = UUID()
        let date: Date
        let projectedBalance: Decimal
        let events: [String]
    }

    @MainActor
    static func forecast(
        accounts: [Account],
        transactions: [Transaction],
        recurringTransactions: [RecurringTransaction],
        subscriptions: [Subscription],
        days: Int = 30
    ) -> [DailyForecast] {
        // 1. Current total balance
        var balance = accounts.reduce(Decimal.zero) { $0 + BalanceCalculator.balance(for: $1, in: transactions) }

        // 2. Average daily expense from last 90 days
        let cal = Calendar.current
        let now = Date()
        let ninetyDaysAgo = cal.date(byAdding: .day, value: -90, to: now)!
        let recentExpenses = transactions.filter { $0.type == .expense && $0.date >= ninetyDaysAgo && $0.date <= now }
        let totalExpense = recentExpenses.reduce(Decimal.zero) { $0 + $1.amount }
        let daysSinceStart = max(1, cal.dateComponents([.day], from: ninetyDaysAgo, to: now).day ?? 90)
        let avgDailyExpense = totalExpense / Decimal(daysSinceStart)

        // 3. Build daily forecast
        var result: [DailyForecast] = []
        let startOfToday = cal.startOfDay(for: now)

        for dayOffset in 0..<days {
            guard let date = cal.date(byAdding: .day, value: dayOffset, to: startOfToday) else { continue }
            var events: [String] = []

            // Subtract average daily expense (skip today — it's current balance)
            if dayOffset > 0 {
                balance -= avgDailyExpense
            }

            // Recurring transactions
            for rt in recurringTransactions where rt.isActive {
                if isScheduled(rt.frequency, startDate: rt.startDate, on: date) {
                    if rt.type == .income {
                        balance += rt.amount
                        events.append("+ \(rt.title)")
                    } else if rt.type == .expense {
                        balance -= rt.amount
                        events.append("− \(rt.title)")
                    }
                }
            }

            // Subscriptions
            for sub in subscriptions where sub.isActive {
                if isScheduled(sub.frequency, startDate: sub.nextBillingDate, on: date) {
                    balance -= sub.amount
                    events.append("− \(sub.name)")
                }
            }

            result.append(DailyForecast(date: date, projectedBalance: balance, events: events))
        }
        return result
    }

    private static func isScheduled(_ frequency: RecurringFrequency, startDate: Date, on date: Date) -> Bool {
        let cal = Calendar.current
        switch frequency {
        case .daily:
            return true
        case .weekly:
            return cal.component(.weekday, from: date) == cal.component(.weekday, from: startDate)
        case .monthly:
            return cal.component(.day, from: date) == cal.component(.day, from: startDate)
        case .yearly:
            let d1 = cal.dateComponents([.month, .day], from: startDate)
            let d2 = cal.dateComponents([.month, .day], from: date)
            return d1.month == d2.month && d1.day == d2.day
        }
    }
}
