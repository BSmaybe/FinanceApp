import ActivityKit
import WidgetKit
import SwiftUI

@available(iOS 16.2, *)
struct DailyBudgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DailyBudgetAttributes.self) { context in
            LockScreenLiveActivityView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(String(format: "%.0f%%", context.state.progress * 100))
                            .font(.title2.bold())
                    } icon: {
                        Image(systemName: "dollarsign.circle.fill")
                    }
                    .foregroundStyle(context.state.isOverBudget ? .red : .green)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Remaining")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(context.state.currencySymbol)\(String(format: "%.0f", context.state.remaining))")
                            .font(.callout.bold().monospacedDigit())
                            .foregroundStyle(context.state.isOverBudget ? .red : .primary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(value: context.state.progress)
                        .tint(context.state.isOverBudget ? .red : .green)
                        .padding(.horizontal)
                }
            } compactLeading: {
                Image(systemName: "dollarsign.circle.fill")
                    .foregroundStyle(context.state.isOverBudget ? .red : .green)
            } compactTrailing: {
                Text(String(format: "%.0f%%", context.state.progress * 100))
                    .font(.caption2.bold().monospacedDigit())
                    .foregroundStyle(context.state.isOverBudget ? .red : .green)
            } minimal: {
                Image(systemName: context.state.isOverBudget ? "exclamationmark.circle.fill" : "dollarsign.circle.fill")
                    .foregroundStyle(context.state.isOverBudget ? .red : .green)
            }
        }
    }
}

@available(iOS 16.2, *)
struct LockScreenLiveActivityView: View {
    let context: ActivityViewContext<DailyBudgetAttributes>

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(context.attributes.activityTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(context.state.currencySymbol)\(String(format: "%.0f", context.state.spentToday))")
                    .font(.title3.bold().monospacedDigit())
                Text("of \(context.state.currencySymbol)\(String(format: "%.0f", context.state.dailyBudget))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: context.state.progress)
                    .stroke(
                        context.state.isOverBudget ? Color.red : Color.green,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Text(String(format: "%.0f%%", context.state.progress * 100))
                    .font(.caption2.bold())
            }
            .frame(width: 52, height: 52)
        }
        .padding(16)
    }
}
