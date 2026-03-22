import UserNotifications

enum NotificationService {

    // MARK: - Permission

    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            return granted
        }
        return settings.authorizationStatus == .authorized
    }

    // MARK: - Budget notifications

    static func scheduleBudgetNotifications(
        budgets: [Budget],
        spentByCategory: [UUID: Decimal],
        categoryById: [UUID: Category]
    ) {
        let center = UNUserNotificationCenter.current()

        Task {
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized else { return }

            let cal = Calendar.current
            let now = Date()
            let currentMonth = cal.component(.month, from: now)
            let currentYear = cal.component(.year, from: now)

            let currentBudgets = budgets.filter { $0.month == currentMonth && $0.year == currentYear }

            for budget in currentBudgets {
                let categoryId = budget.categoryId
                let limit = budget.limitAmount
                guard limit > 0 else { continue }

                let spent = spentByCategory[categoryId, default: .zero]
                let ratio = NSDecimalNumber(decimal: spent / limit).doubleValue
                let categoryName = categoryById[categoryId]?.name ?? String(localized: "Category")

                if ratio >= 1.0 {
                    let identifier = "budget_\(categoryId.uuidString)_100"
                    scheduleImmediate(
                        identifier: identifier,
                        title: String(localized: "Budget exceeded!"),
                        body: categoryName,
                        center: center
                    )
                } else if ratio >= 0.8 {
                    let identifier = "budget_\(categoryId.uuidString)_80"
                    let percent = Int(ratio * 100)
                    scheduleImmediate(
                        identifier: identifier,
                        title: String(format: String(localized: "Budget warning: %d%%"), percent),
                        body: categoryName,
                        center: center
                    )
                }
            }
        }
    }

    // MARK: - Subscription reminders

    @MainActor
    static func scheduleSubscriptionReminders(subscriptions: [Subscription]) {
        let subsData = subscriptions
            .filter { $0.isActive }
            .map { sub -> (id: UUID, name: String, amountString: String, billingDate: Date) in
                (id: sub.id, name: sub.name, amountString: CurrencyFormatter.string(from: sub.amount), billingDate: sub.nextBillingDate)
            }

        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized else { return }

            let pending = await center.pendingNotificationRequests()
            let oldIds = pending
                .filter { $0.identifier.hasPrefix("subscription_") }
                .map(\.identifier)
            center.removePendingNotificationRequests(withIdentifiers: oldIds)

            let cal = Calendar.current
            let now = Date()

            for sub in subsData {
                guard let reminderDate = cal.date(byAdding: .day, value: -1, to: sub.billingDate) else { continue }
                guard reminderDate > now else { continue }

                let content = UNMutableNotificationContent()
                content.title = String(localized: "Subscription reminder")
                content.body = String(
                    format: String(localized: "Tomorrow: %@ — %@"),
                    sub.name,
                    sub.amountString
                )
                content.sound = .default

                var dateComps = cal.dateComponents([.year, .month, .day], from: reminderDate)
                dateComps.hour = 9
                dateComps.minute = 0

                let trigger = UNCalendarNotificationTrigger(dateMatching: dateComps, repeats: false)
                let request = UNNotificationRequest(
                    identifier: "subscription_\(sub.id.uuidString)",
                    content: content,
                    trigger: trigger
                )
                await add(request, to: center)
            }
        }
    }

    // MARK: - Debt payment reminders

    @MainActor
    static func scheduleDebtReminders(debts: [Debt]) {
        let debtsData = debts
            .filter { $0.remainingAmount > 0 && $0.dueDay > 0 }
            .map { debt -> (id: UUID, name: String, paymentString: String, dueDay: Int) in
                (id: debt.id, name: debt.name, paymentString: CurrencyFormatter.string(from: debt.minimumPayment), dueDay: debt.dueDay)
            }

        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized else { return }

            let pending = await center.pendingNotificationRequests()
            let oldIds = pending
                .filter { $0.identifier.hasPrefix("debt_") }
                .map(\.identifier)
            center.removePendingNotificationRequests(withIdentifiers: oldIds)

            let cal = Calendar.current
            let now = Date()
            let currentComps = cal.dateComponents([.year, .month], from: now)
            guard let currentYear = currentComps.year, let currentMonth = currentComps.month else { return }

            for debt in debtsData {
                // Build the due date for this month; if already past, use next month
                var dueDateComps = DateComponents()
                dueDateComps.year = currentYear
                dueDateComps.month = currentMonth
                dueDateComps.day = debt.dueDay
                dueDateComps.hour = 9
                dueDateComps.minute = 0

                guard let dueDate = cal.date(from: dueDateComps) else { continue }

                let targetDue: Date
                if dueDate > now {
                    targetDue = dueDate
                } else {
                    // Move to next month
                    var nextComps = dueDateComps
                    nextComps.month = currentMonth + 1
                    guard let nextDue = cal.date(from: nextComps) else { continue }
                    targetDue = nextDue
                }

                guard let reminderDate = cal.date(byAdding: .day, value: -3, to: targetDue) else { continue }
                guard reminderDate > now else { continue }

                let content = UNMutableNotificationContent()
                content.title = debt.name
                content.body = String(
                    format: String(localized: "Payment due in 3 days: %@"),
                    debt.paymentString
                )
                content.sound = .default

                let triggerComps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: reminderDate)
                let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComps, repeats: false)
                let request = UNNotificationRequest(
                    identifier: "debt_\(debt.id.uuidString)",
                    content: content,
                    trigger: trigger
                )
                await add(request, to: center)
            }
        }
    }

    // MARK: - Reschedule all

    @MainActor
    static func rescheduleAll(
        subscriptions: [Subscription],
        debts: [Debt],
        budgets: [Budget],
        spentByCategory: [UUID: Decimal],
        categoryById: [UUID: Category]
    ) {
        scheduleSubscriptionReminders(subscriptions: subscriptions)
        scheduleDebtReminders(debts: debts)
        scheduleBudgetNotifications(
            budgets: budgets,
            spentByCategory: spentByCategory,
            categoryById: categoryById
        )
    }

    // MARK: - Private helpers

    private static func scheduleImmediate(
        identifier: String,
        title: String,
        body: String,
        center: UNUserNotificationCenter
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        Task {
            await add(request, to: center)
        }
    }

    private static func add(_ request: UNNotificationRequest, to center: UNUserNotificationCenter) async {
        do {
            try await center.add(request)
        } catch {
            // Fire-and-forget; errors are non-critical
        }
    }
}
