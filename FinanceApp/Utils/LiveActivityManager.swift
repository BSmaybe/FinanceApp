import Foundation

#if canImport(ActivityKit)
import ActivityKit

@available(iOS 16.2, *)
@MainActor
enum LiveActivityManager {

    static func start(spentToday: Double, dailyBudget: Double, currencySymbol: String) {
        guard isEnabled else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // End any existing activity first
        stopAll()

        let attributes = DailyBudgetAttributes(activityTitle: String(localized: "Daily Budget"))
        let state = DailyBudgetAttributes.ContentState(
            spentToday: spentToday,
            dailyBudget: dailyBudget,
            currencySymbol: currencySymbol
        )

        do {
            let nextMidnight = Calendar.current.startOfDay(for: Date().addingTimeInterval(86400))
            let content = ActivityContent(state: state, staleDate: nextMidnight)
            _ = try Activity.request(attributes: attributes, content: content)
        } catch {
            // Silently ignore — Live Activities not available in simulator or when disabled
        }
    }

    static func update(spentToday: Double, dailyBudget: Double, currencySymbol: String) {
        guard isEnabled else { return }
        let state = DailyBudgetAttributes.ContentState(
            spentToday: spentToday,
            dailyBudget: dailyBudget,
            currencySymbol: currencySymbol
        )
        Task {
            for activity in Activity<DailyBudgetAttributes>.activities {
                await activity.update(ActivityContent(state: state, staleDate: nil))
            }
        }
    }

    static func stopAll() {
        Task {
            for activity in Activity<DailyBudgetAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    private static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "liveActivityEnabled")
    }
}
#endif
