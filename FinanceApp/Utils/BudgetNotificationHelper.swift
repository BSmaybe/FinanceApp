import Foundation
import UserNotifications
import SwiftData

enum BudgetNotificationHelper {

    /// Request notification permission on first launch
    static func requestPermissionIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            if settings.authorizationStatus == .notDetermined {
                center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
            }
        }
    }

    /// Check budget limits after saving an expense transaction.
    /// Call this after inserting/updating an expense.
    @MainActor static func checkLimits(
        categoryId: UUID?,
        context: ModelContext
    ) {
        guard let categoryId else { return }

        let cal = Calendar.current
        let now = Date()
        let month = cal.component(.month, from: now)
        let year = cal.component(.year, from: now)

        // Find budget for this category/month
        let budgetPredicate = #Predicate<Budget> {
            $0.categoryId == categoryId &&
            $0.month == month &&
            $0.year == year
        }
        let budgetDescriptor = FetchDescriptor<Budget>(predicate: budgetPredicate)
        guard let budget = try? context.fetch(budgetDescriptor).first else { return }

        let limit = budget.limitAmount
        guard limit > 0 else { return }

        // Calculate total spent this month for this category
        let startOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: now))!
        var nextMonthComps = cal.dateComponents([.year, .month], from: now)
        nextMonthComps.month! += 1
        let startOfNextMonth = cal.date(from: nextMonthComps)!

        let expenseType = TransactionType.expense
        let expensePredicate = #Predicate<Transaction> {
            $0.type == expenseType &&
            $0.categoryId == categoryId &&
            $0.date >= startOfMonth &&
            $0.date < startOfNextMonth
        }
        let txnDescriptor = FetchDescriptor<Transaction>(predicate: expensePredicate)
        guard let transactions = try? context.fetch(txnDescriptor) else { return }

        let spent = transactions.reduce(Decimal.zero) { $0 + $1.amount }
        let ratio = NSDecimalNumber(decimal: spent / limit).doubleValue

        // Find category name
        let catPredicate = #Predicate<Category> { $0.id == categoryId }
        let catDescriptor = FetchDescriptor<Category>(predicate: catPredicate)
        let categoryName = (try? context.fetch(catDescriptor).first?.name) ?? "Category"

        if ratio >= 1.0 {
            sendNotification(
                title: String(localized: "Budget exceeded!"),
                body: String(format: String(localized: "%@ — spent %@ of %@ limit"), categoryName,
                             CurrencyFormatter.string(from: spent),
                             CurrencyFormatter.string(from: limit)),
                id: "budget-over-\(categoryId)-\(month)-\(year)"
            )
        } else if ratio >= 0.8 {
            let percent = Int(ratio * 100)
            sendNotification(
                title: String(format: String(localized: "Budget warning: %d%%"), percent),
                body: String(format: String(localized: "%@ — %@ of %@ remaining"), categoryName,
                             CurrencyFormatter.string(from: limit - spent),
                             CurrencyFormatter.string(from: limit)),
                id: "budget-warn-\(categoryId)-\(month)-\(year)"
            )
        }
    }

    private static func sendNotification(title: String, body: String, id: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        // Fire immediately (1 second delay)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("Notification error: \(error)")
            }
        }
    }
}
