import ActivityKit
import Foundation

@available(iOS 16.2, *)
struct DailyBudgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var spentToday: Double
        var dailyBudget: Double
        var currencySymbol: String

        var progress: Double {
            guard dailyBudget > 0 else { return 0 }
            return min(1.0, spentToday / dailyBudget)
        }

        var remaining: Double { max(0, dailyBudget - spentToday) }
        var isOverBudget: Bool { spentToday > dailyBudget }
    }

    var activityTitle: String
}
