import Foundation

struct CashCalendarEvent: Identifiable {
    enum Direction: String {
        case income
        case expense
    }

    enum Source: String {
        case transaction
        case recurring
        case subscription
        case debt
    }

    enum Status: String {
        case actual
        case planned
    }

    let id: String
    let date: Date
    let title: String
    let amount: Decimal
    let direction: Direction
    let source: Source
    let status: Status
    let relatedId: UUID?
}

struct CashCalendarDay: Identifiable {
    let date: Date
    let events: [CashCalendarEvent]
    let actualIncome: Decimal
    let actualExpense: Decimal
    let plannedIncome: Decimal
    let plannedExpense: Decimal
    let net: Decimal

    var id: Date { date }
}

enum CashCalendarAssembler {
    private struct DebtCycleKey: Hashable {
        let debtId: UUID
        let cycle: String
    }

    static func monthDays(
        referenceDate: Date,
        transactions: [Transaction],
        categories: [Category],
        recurringTransactions: [RecurringTransaction],
        subscriptions: [Subscription],
        debts: [Debt],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [CashCalendarDay] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: referenceDate) else { return [] }

        let monthStart = calendar.startOfDay(for: monthInterval.start)
        let monthEndExclusive = monthInterval.end
        let todayStart = calendar.startOfDay(for: now)
        let categoryById = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })

        var eventsByDay: [Date: [CashCalendarEvent]] = [:]

        func addEvent(_ event: CashCalendarEvent) {
            let day = calendar.startOfDay(for: event.date)
            eventsByDay[day, default: []].append(event)
        }

        let postedTransactions = transactions.filter { BalanceCalculator.isPosted($0, asOf: now) }

        for txn in postedTransactions {
            guard txn.date >= monthStart && txn.date < monthEndExclusive else { continue }
            guard txn.type == .income || txn.type == .expense else { continue }

            let trimmedNote = txn.note.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallbackTitle: String = {
                if let categoryId = txn.categoryId,
                   let category = categoryById[categoryId] {
                    return category.name
                }
                return txn.type.localizedName
            }()

            addEvent(
                CashCalendarEvent(
                    id: "txn-\(txn.id.uuidString)",
                    date: txn.date,
                    title: trimmedNote.isEmpty ? fallbackTitle : trimmedNote,
                    amount: txn.amount,
                    direction: txn.type == .income ? .income : .expense,
                    source: .transaction,
                    status: .actual,
                    relatedId: txn.id
                )
            )
        }

        for recurring in recurringTransactions where recurring.isActive {
            guard recurring.type == .income || recurring.type == .expense else { continue }
            var day = monthStart
            while day < monthEndExclusive {
                if day >= todayStart,
                   day >= calendar.startOfDay(for: recurring.startDate),
                   isScheduled(recurring.frequency, startDate: recurring.startDate, on: day, calendar: calendar) {
                    addEvent(
                        CashCalendarEvent(
                            id: "recurring-\(recurring.id.uuidString)-\(day.timeIntervalSince1970)",
                            date: day,
                            title: recurring.title,
                            amount: recurring.amount,
                            direction: recurring.type == .income ? .income : .expense,
                            source: .recurring,
                            status: .planned,
                            relatedId: recurring.id
                        )
                    )
                }
                guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = nextDay
            }
        }

        for subscription in subscriptions where subscription.isActive {
            var day = monthStart
            while day < monthEndExclusive {
                if day >= todayStart,
                   day >= calendar.startOfDay(for: subscription.nextBillingDate),
                   isScheduled(subscription.frequency, startDate: subscription.nextBillingDate, on: day, calendar: calendar) {
                    addEvent(
                        CashCalendarEvent(
                            id: "subscription-\(subscription.id.uuidString)-\(day.timeIntervalSince1970)",
                            date: day,
                            title: subscription.name,
                            amount: subscription.amount,
                            direction: .expense,
                            source: .subscription,
                            status: .planned,
                            relatedId: subscription.id
                        )
                    )
                }
                guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = nextDay
            }
        }

        let autoPaidCycles = Set(postedTransactions.compactMap { debtCycleKey(from: $0) })

        for debt in debts where debt.remainingAmount > 0 && debt.minimumPayment > 0 && debt.dueDay > 0 {
            let dueDate = dueDate(for: debt, inMonthStartingAt: monthStart, calendar: calendar)
            guard dueDate >= monthStart && dueDate < monthEndExclusive else { continue }
            guard dueDate >= todayStart else { continue }

            let cycle = yearMonthKey(for: dueDate, calendar: calendar)
            let cycleKey = DebtCycleKey(debtId: debt.id, cycle: cycle)
            if autoPaidCycles.contains(cycleKey) { continue }

            let plannedAmount = min(debt.remainingAmount, debt.minimumPayment)
            guard plannedAmount > 0 else { continue }

            addEvent(
                CashCalendarEvent(
                    id: "debt-\(debt.id.uuidString)-\(cycle)",
                    date: dueDate,
                    title: String(format: String(localized: "Debt payment: %@"), debt.name),
                    amount: plannedAmount,
                    direction: .expense,
                    source: .debt,
                    status: .planned,
                    relatedId: debt.id
                )
            )
        }

        let daysCount = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30

        return (0..<daysCount).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: monthStart) else { return nil }
            let day = calendar.startOfDay(for: date)
            let sortedEvents = (eventsByDay[day] ?? []).sorted(by: compareEvents)

            var actualIncome: Decimal = .zero
            var actualExpense: Decimal = .zero
            var plannedIncome: Decimal = .zero
            var plannedExpense: Decimal = .zero

            for event in sortedEvents {
                switch (event.status, event.direction) {
                case (.actual, .income):
                    actualIncome += event.amount
                case (.actual, .expense):
                    actualExpense += event.amount
                case (.planned, .income):
                    plannedIncome += event.amount
                case (.planned, .expense):
                    plannedExpense += event.amount
                }
            }

            let net = (actualIncome + plannedIncome) - (actualExpense + plannedExpense)

            return CashCalendarDay(
                date: day,
                events: sortedEvents,
                actualIncome: actualIncome,
                actualExpense: actualExpense,
                plannedIncome: plannedIncome,
                plannedExpense: plannedExpense,
                net: net
            )
        }
    }

    private static func compareEvents(_ lhs: CashCalendarEvent, _ rhs: CashCalendarEvent) -> Bool {
        if lhs.status != rhs.status {
            return lhs.status == .actual
        }
        if lhs.direction != rhs.direction {
            return lhs.direction == .expense
        }
        if lhs.amount != rhs.amount {
            return lhs.amount > rhs.amount
        }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private static func isScheduled(
        _ frequency: RecurringFrequency,
        startDate: Date,
        on date: Date,
        calendar: Calendar
    ) -> Bool {
        switch frequency {
        case .daily:
            return true
        case .weekly:
            return calendar.component(.weekday, from: date) == calendar.component(.weekday, from: startDate)
        case .monthly:
            return calendar.component(.day, from: date) == calendar.component(.day, from: startDate)
        case .yearly:
            let left = calendar.dateComponents([.month, .day], from: startDate)
            let right = calendar.dateComponents([.month, .day], from: date)
            return left.month == right.month && left.day == right.day
        }
    }

    private static func dueDate(for debt: Debt, inMonthStartingAt monthStart: Date, calendar: Calendar) -> Date {
        var comps = calendar.dateComponents([.year, .month], from: monthStart)
        let safeDay = max(1, debt.dueDay)
        let daysInMonth = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30
        comps.day = min(safeDay, daysInMonth)
        return calendar.startOfDay(for: calendar.date(from: comps) ?? monthStart)
    }

    private static func debtCycleKey(from transaction: Transaction) -> DebtCycleKey? {
        guard transaction.tags.contains("auto_debt_payment") else { return nil }

        var debtId: UUID?
        var cycle: String?

        for tag in transaction.tags {
            if tag.hasPrefix("debt_cycle_") {
                cycle = String(tag.dropFirst("debt_cycle_".count))
            } else if tag.hasPrefix("debt_") {
                let raw = String(tag.dropFirst("debt_".count))
                debtId = UUID(uuidString: raw)
            }
        }

        guard let debtId, let cycle, !cycle.isEmpty else { return nil }
        return DebtCycleKey(debtId: debtId, cycle: cycle)
    }

    private static func yearMonthKey(for date: Date, calendar: Calendar) -> String {
        let comps = calendar.dateComponents([.year, .month], from: date)
        let year = comps.year ?? 2000
        let month = comps.month ?? 1
        return "\(year)-\(String(format: "%02d", month))"
    }
}
