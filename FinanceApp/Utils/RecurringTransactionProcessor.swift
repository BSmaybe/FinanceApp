import Foundation
import SwiftData

enum RecurringTransactionProcessor {

    private static func cap(for frequency: RecurringFrequency) -> Int {
        switch frequency {
        case .daily:   return 30
        case .weekly:  return 52
        case .monthly: return 12
        case .yearly:  return 3
        }
    }

    static func process(context: ModelContext) {
        let descriptor = FetchDescriptor<RecurringTransaction>(
            predicate: #Predicate { $0.isActive == true }
        )
        guard let recurrings = try? context.fetch(descriptor) else { return }

        let today = Calendar.current.startOfDay(for: Date())
        let calendar = Calendar.current

        for recurring in recurrings {
            // Guard: if startDate is more than 1 year ago and we've never generated,
            // jump lastGeneratedDate to (now - 1 year) to avoid a huge backfill.
            if recurring.lastGeneratedDate == nil {
                let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: today) ?? today
                let start = calendar.startOfDay(for: recurring.startDate)
                if start < oneYearAgo {
                    recurring.lastGeneratedDate = oneYearAgo
                }
            }

            let firstDate: Date
            let startDate = calendar.startOfDay(for: recurring.startDate)
            if let last = recurring.lastGeneratedDate {
                let nextAfterLast = nextDate(after: last, frequency: recurring.frequency) ?? last
                firstDate = max(startDate, calendar.startOfDay(for: nextAfterLast))
            } else {
                firstDate = startDate
            }
            generateOccurrences(recurring: recurring, firstDate: firstDate, upTo: today, context: context)
        }

        do {
            try context.save()
        } catch {
            print("RecurringTransactionProcessor save error: \(error)")
        }
    }

    private static func generateOccurrences(
        recurring: RecurringTransaction,
        firstDate: Date,
        upTo today: Date,
        context: ModelContext
    ) {
        let maxCount = cap(for: recurring.frequency)
        var current: Date? = firstDate
        var count = 0
        var lastGenerated: Date? = nil

        while let date = current, date <= today, count < maxCount {
            let txn = Transaction(
                date: date,
                amount: recurring.amount,
                type: recurring.type,
                accountId: recurring.accountId,
                toAccountId: recurring.toAccountId,
                categoryId: recurring.categoryId,
                note: recurring.title.isEmpty ? recurring.note : recurring.title
            )
            context.insert(txn)
            lastGenerated = date
            count += 1
            current = nextDate(after: date, frequency: recurring.frequency)
        }

        if let lastGenerated {
            recurring.lastGeneratedDate = lastGenerated
        }
    }

    private static func nextDate(after date: Date, frequency: RecurringFrequency) -> Date? {
        let calendar = Calendar.current
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
