import Foundation

// ActivityKit import is conditional — ActivityKit is only available on iOS 16.1+
// and is not present in all simulator builds.
#if canImport(ActivityKit)
import ActivityKit

@available(iOS 16.2, *)
struct DailyBudgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        enum Signal: String, Codable, Hashable {
            case noBudget
            case onTrack
            case warning
            case overBudget
        }

        enum Celebration: String, Codable, Hashable {
            case none
            case goalReached
            case debtPaidOff
            case incomeAdded
            case expenseLogged
            case budgetWarning
        }

        var spentToday: Double
        var dailyBudget: Double
        var currencySymbol: String
        var signal: Signal
        var pulseToken: Int
        var celebration: Celebration
        var celebrationAmount: Double?
        var celebrationDetail: String?

        var progress: Double {
            guard dailyBudget > 0 else { return 0 }
            return min(1.0, spentToday / dailyBudget)
        }

        var remaining: Double { max(0, dailyBudget - spentToday) }
        var isOverBudget: Bool { spentToday > dailyBudget }
    }

    var activityTitle: String
}
#endif
