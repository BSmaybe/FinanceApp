import Foundation
import UserNotifications

enum SubscriptionNotificationHelper {

    /// Schedule reminders for all active subscriptions.
    /// Removes old subscription reminders and re-schedules.
    @MainActor
    static func scheduleReminders(subscriptions: [Subscription]) {
        // Collect Sendable data before leaving MainActor
        let subsData = subscriptions
            .filter { $0.isActive }
            .map { (name: $0.name, amount: ($0.amount as NSDecimalNumber).stringValue, id: $0.id.uuidString, billingDate: $0.nextBillingDate) }

        Task.detached {
            let center = UNUserNotificationCenter.current()
            let pending = await center.pendingNotificationRequests()
            let oldIds = pending
                .filter { $0.identifier.hasPrefix("sub-reminder-") }
                .map(\.identifier)
            center.removePendingNotificationRequests(withIdentifiers: oldIds)

            for sub in subsData {
                scheduleReminder(name: sub.name, amountStr: sub.amount, idString: sub.id, billingDate: sub.billingDate)
            }
        }
    }

    /// Schedule a single reminder 1 day before the next billing date.
    private static func scheduleReminder(name: String, amountStr: String, idString: String, billingDate: Date) {
        let cal = Calendar.current

        guard let reminderDate = cal.date(byAdding: .day, value: -1, to: billingDate) else { return }
        guard reminderDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Subscription reminder")
        content.body = String(
            format: String(localized: "Tomorrow: %@ — %@"),
            name,
            amountStr
        )
        content.sound = .default

        var dateComps = cal.dateComponents([.year, .month, .day], from: reminderDate)
        dateComps.hour = 10
        dateComps.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComps, repeats: false)
        let request = UNNotificationRequest(identifier: "sub-reminder-\(idString)", content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("Subscription notification error: \(error)")
            }
        }
    }
}
