import UserNotifications

enum NotificationService {
    private static var isUITestMode: Bool {
        ProcessInfo.processInfo.arguments.contains("UITEST_RESET")
    }

    // MARK: - Permission

    static func requestPermission() async -> Bool {
        guard !isUITestMode else { return false }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            return granted
        }
        return settings.authorizationStatus == .authorized
    }

    // MARK: - Schedule all (primary entry point)

    /// Schedule all notification types from current data.
    /// `debtReminderDays`: how many days before dueDay to fire the debt reminder.
    @MainActor
    static func scheduleAll(
        subscriptions: [Subscription],
        debts: [Debt],
        budgets: [Budget],
        spentByCategory: [UUID: Decimal],
        categoryById: [UUID: Category],
        debtReminderDays: Int = 3
    ) {
        scheduleSubscriptionReminders(subscriptions: subscriptions)
        scheduleDebtReminders(debts: debts, reminderDays: debtReminderDays)
        scheduleBudgetNotifications(
            budgets: budgets,
            spentByCategory: spentByCategory,
            categoryById: categoryById
        )
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
                    let identifier = "budget_over_\(categoryId.uuidString)"
                    scheduleImmediate(
                        identifier: identifier,
                        title: String(localized: "Budget Exceeded"),
                        body: String(format: String(localized: "Category %@: limit reached"), categoryName),
                        center: center
                    )
                } else if ratio >= 0.8 {
                    let identifier = "budget_warn_\(categoryId.uuidString)"
                    scheduleImmediate(
                        identifier: identifier,
                        title: String(localized: "Budget Warning"),
                        body: String(format: String(localized: "Category %@: 80%% of limit spent"), categoryName),
                        center: center
                    )
                }
            }
        }
    }

    // MARK: - Check budget after transaction save

    /// Called after a budget-affecting transaction is saved.
    /// Fires an immediate notification if 80% or 100% threshold was crossed.
    static func checkBudget(
        categoryId: UUID?,
        budgets: [Budget],
        spentByCategory: [UUID: Decimal],
        categoryById: [UUID: Category]
    ) {
        guard let categoryId else { return }

        let cal = Calendar.current
        let now = Date()
        let currentMonth = cal.component(.month, from: now)
        let currentYear = cal.component(.year, from: now)

        guard let budget = budgets.first(where: {
            $0.categoryId == categoryId && $0.month == currentMonth && $0.year == currentYear
        }) else { return }

        let limit = budget.limitAmount
        guard limit > 0 else { return }

        let spent = spentByCategory[categoryId, default: .zero]
        let ratio = NSDecimalNumber(decimal: spent / limit).doubleValue
        let categoryName = categoryById[categoryId]?.name ?? String(localized: "Category")
        let center = UNUserNotificationCenter.current()

        if ratio >= 1.0 {
            scheduleImmediate(
                identifier: "budget_over_\(categoryId.uuidString)",
                title: String(localized: "Budget Exceeded"),
                body: String(format: String(localized: "Category %@: limit reached"), categoryName),
                center: center
            )
        } else if ratio >= 0.8 {
            scheduleImmediate(
                identifier: "budget_warn_\(categoryId.uuidString)",
                title: String(localized: "Budget Warning"),
                body: String(format: String(localized: "Category %@: 80%% of limit spent"), categoryName),
                center: center
            )
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
                content.title = String(localized: "Subscription Renewal Tomorrow")
                content.body = String(
                    format: String(localized: "%@ — %@"),
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

    // MARK: - Debt payment reminders (grouped by reminder date → 1 push per day)

    @MainActor
    static func scheduleDebtReminders(debts: [Debt], reminderDays: Int = 3) {
        struct DebtInfo {
            let name: String
            let dueDay: Int
        }
        let activeDebts = debts
            .filter { $0.remainingAmount > 0 && $0.dueDay > 0 }
            .map { DebtInfo(name: $0.name, dueDay: $0.dueDay) }
        let days = reminderDays

        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized else { return }

            // Remove all old grouped debt notifications
            let pending = await center.pendingNotificationRequests()
            let oldIds = pending
                .filter { $0.identifier.hasPrefix("debts_group_") }
                .map(\.identifier)
            center.removePendingNotificationRequests(withIdentifiers: oldIds)

            let cal = Calendar.current
            let now = Date()
            let currentComps = cal.dateComponents([.year, .month], from: now)
            guard let currentYear = currentComps.year, let currentMonth = currentComps.month else { return }

            // Calculate reminder date for each debt, group by day-of-year
            var groups: [String: (reminderDate: Date, names: [String], daysUntilDue: Int)] = [:]

            for debt in activeDebts {
                var dueDateComps = DateComponents()
                dueDateComps.year = currentYear
                dueDateComps.month = currentMonth
                dueDateComps.day = debt.dueDay
                guard let dueDate = cal.date(from: dueDateComps) else { continue }

                let targetDue = dueDate > now ? dueDate : {
                    var next = dueDateComps
                    next.month = currentMonth + 1
                    return cal.date(from: next) ?? dueDate
                }()

                guard let reminderDate = cal.date(byAdding: .day, value: -days, to: targetDue),
                      reminderDate > now else { continue }

                // Key = "YYYY-MM-DD" of reminder date
                let key = cal.dateComponents([.year, .month, .day], from: reminderDate)
                let keyStr = "\(key.year ?? 0)-\(key.month ?? 0)-\(key.day ?? 0)"

                if groups[keyStr] == nil {
                    groups[keyStr] = (reminderDate: reminderDate, names: [], daysUntilDue: days)
                }
                groups[keyStr]?.names.append(debt.name)
            }

            // One notification per group
            for (key, group) in groups {
                let content = UNMutableNotificationContent()
                let count = group.names.count

                if count == 1 {
                    content.title = String(localized: "Payment Due Soon")
                    content.body = String(
                        format: String(localized: "%@ — due in %lld days"),
                        group.names[0],
                        Int64(group.daysUntilDue)
                    )
                } else {
                    content.title = String(
                        format: String(localized: "%lld payments due in %lld days"),
                        Int64(count),
                        Int64(group.daysUntilDue)
                    )
                    // Show up to 3 names, then "+N more"
                    let shown = group.names.prefix(3).joined(separator: ", ")
                    let extra = count > 3 ? String(format: String(localized: " +%lld more"), Int64(count - 3)) : ""
                    content.body = shown + extra
                }
                content.sound = .default

                let triggerComps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: group.reminderDate)
                let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComps, repeats: false)
                let request = UNNotificationRequest(
                    identifier: "debts_group_\(key)",
                    content: content,
                    trigger: trigger
                )
                await add(request, to: center)
            }
        }
    }

    // MARK: - Reschedule all (legacy, used by DashboardView)

    @MainActor
    static func rescheduleAll(
        subscriptions: [Subscription],
        debts: [Debt],
        budgets: [Budget],
        spentByCategory: [UUID: Decimal],
        categoryById: [UUID: Category],
        debtReminderDays: Int = 3
    ) {
        scheduleAll(
            subscriptions: subscriptions,
            debts: debts,
            budgets: budgets,
            spentByCategory: spentByCategory,
            categoryById: categoryById,
            debtReminderDays: debtReminderDays
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
