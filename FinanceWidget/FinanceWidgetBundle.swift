import WidgetKit
import SwiftUI

@main
struct FinanceWidgetBundle: WidgetBundle {
    var body: some Widget {
        FinanceWidget()
        if #available(iOS 16.2, *) {
            DailyBudgetLiveActivity()
        }
    }
}
