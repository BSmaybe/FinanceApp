import ActivityKit
import WidgetKit
import SwiftUI

@available(iOS 16.2, *)
struct DailyBudgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DailyBudgetAttributes.self) { context in
            LockScreenLiveActivityView(context: context)
        } dynamicIsland: { context in
            let tone = displayTone(for: context.state)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(percentText(for: context.state))
                            .font(.title2.bold())
                            .monospacedDigit()
                            .financeNumericTransitionIfAvailable()
                    } icon: {
                        Image(systemName: displayIcon(for: context.state))
                            .financePulseIfAvailable(trigger: context.state.pulseToken)
                    }
                    .foregroundStyle(tone)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Remaining")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(amountText(for: context.state.remaining, currencySymbol: context.state.currencySymbol))
                            .font(.callout.bold().monospacedDigit())
                            .financeNumericTransitionIfAvailable()
                            .foregroundStyle(context.state.signal == .overBudget ? .red : .primary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(displayLabel(for: context.state))
                                .font(.caption.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(tone.opacity(0.18), in: Capsule())
                                .foregroundStyle(tone)
                            Spacer()
                            Text("\(String(localized: "Spent")) \(amountText(for: context.state.spentToday, currencySymbol: context.state.currencySymbol))")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .financeNumericTransitionIfAvailable()
                        }
                        ProgressView(value: context.state.progress)
                            .tint(tone)
                            .animation(.spring(response: 0.45, dampingFraction: 0.86), value: context.state.progress)
                    }
                    .padding(.horizontal)
                }
            } compactLeading: {
                Image(systemName: displayIcon(for: context.state))
                    .financePulseIfAvailable(trigger: context.state.pulseToken)
                    .foregroundStyle(tone)
            } compactTrailing: {
                Text(percentText(for: context.state))
                    .font(.caption2.bold().monospacedDigit())
                    .financeNumericTransitionIfAvailable()
                    .foregroundStyle(tone)
            } minimal: {
                Image(systemName: displayIcon(for: context.state))
                    .financePulseIfAvailable(trigger: context.state.pulseToken)
                    .foregroundStyle(tone)
            }
        }
    }

    private func percentText(for state: DailyBudgetAttributes.ContentState) -> String {
        String(format: "%.0f%%", state.progress * 100)
    }

    private func amountText(for value: Double, currencySymbol: String) -> String {
        "\(currencySymbol)\(String(format: "%.0f", value))"
    }

    private func signalIcon(_ signal: DailyBudgetAttributes.ContentState.Signal) -> String {
        switch signal {
        case .noBudget:
            return "questionmark.circle.fill"
        case .onTrack:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .overBudget:
            return "flame.fill"
        }
    }

    private func signalTone(_ signal: DailyBudgetAttributes.ContentState.Signal) -> Color {
        switch signal {
        case .noBudget:
            return .blue
        case .onTrack:
            return .green
        case .warning:
            return .orange
        case .overBudget:
            return .red
        }
    }

    private func displayIcon(for state: DailyBudgetAttributes.ContentState) -> String {
        switch state.celebration {
        case .goalReached:
            return "sparkles"
        case .debtPaidOff:
            return "checkmark.seal.fill"
        case .none:
            return signalIcon(state.signal)
        }
    }

    private func displayTone(for state: DailyBudgetAttributes.ContentState) -> Color {
        switch state.celebration {
        case .goalReached:
            return .purple
        case .debtPaidOff:
            return .mint
        case .none:
            return signalTone(state.signal)
        }
    }

    private func displayLabel(for state: DailyBudgetAttributes.ContentState) -> String {
        switch state.celebration {
        case .goalReached:
            return String(localized: "Goal reached")
        case .debtPaidOff:
            return String(localized: "Debt paid off")
        case .none:
            return signalLabel(state.signal)
        }
    }

    private func signalLabel(_ signal: DailyBudgetAttributes.ContentState.Signal) -> String {
        switch signal {
        case .noBudget:
            return String(localized: "No budget set")
        case .onTrack:
            return String(localized: "On track")
        case .warning:
            return String(localized: "Watch budget")
        case .overBudget:
            return String(localized: "Over budget")
        }
    }
}

@available(iOS 16.2, *)
struct LockScreenLiveActivityView: View {
    let context: ActivityViewContext<DailyBudgetAttributes>

    var body: some View {
        let tone = displayTone(for: context.state)
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(context.attributes.activityTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(amountText(for: context.state.spentToday, currencySymbol: context.state.currencySymbol))
                    .font(.title3.bold().monospacedDigit())
                    .financeNumericTransitionIfAvailable()
                Text("of \(amountText(for: context.state.dailyBudget, currencySymbol: context.state.currencySymbol))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(displayLabel(for: context.state))
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(tone.opacity(0.18), in: Capsule())
                    .foregroundStyle(tone)
            }
            Spacer()
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: context.state.progress)
                    .stroke(
                        tone,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.45, dampingFraction: 0.86), value: context.state.progress)
                Image(systemName: displayIcon(for: context.state))
                    .font(.caption.bold())
                    .foregroundStyle(tone)
                    .financePulseIfAvailable(trigger: context.state.pulseToken)
                Text(String(format: "%.0f%%", context.state.progress * 100))
                    .font(.caption2.bold())
                    .monospacedDigit()
                    .offset(y: 15)
                    .financeNumericTransitionIfAvailable()
            }
            .frame(width: 52, height: 52)
        }
        .padding(16)
    }

    private func amountText(for value: Double, currencySymbol: String) -> String {
        "\(currencySymbol)\(String(format: "%.0f", value))"
    }

    private func signalIcon(_ signal: DailyBudgetAttributes.ContentState.Signal) -> String {
        switch signal {
        case .noBudget:
            return "questionmark.circle.fill"
        case .onTrack:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .overBudget:
            return "flame.fill"
        }
    }

    private func signalTone(_ signal: DailyBudgetAttributes.ContentState.Signal) -> Color {
        switch signal {
        case .noBudget:
            return .blue
        case .onTrack:
            return .green
        case .warning:
            return .orange
        case .overBudget:
            return .red
        }
    }

    private func displayIcon(for state: DailyBudgetAttributes.ContentState) -> String {
        switch state.celebration {
        case .goalReached:
            return "sparkles"
        case .debtPaidOff:
            return "checkmark.seal.fill"
        case .none:
            return signalIcon(state.signal)
        }
    }

    private func displayTone(for state: DailyBudgetAttributes.ContentState) -> Color {
        switch state.celebration {
        case .goalReached:
            return .purple
        case .debtPaidOff:
            return .mint
        case .none:
            return signalTone(state.signal)
        }
    }

    private func displayLabel(for state: DailyBudgetAttributes.ContentState) -> String {
        switch state.celebration {
        case .goalReached:
            return String(localized: "Goal reached")
        case .debtPaidOff:
            return String(localized: "Debt paid off")
        case .none:
            return signalLabel(state.signal)
        }
    }

    private func signalLabel(_ signal: DailyBudgetAttributes.ContentState.Signal) -> String {
        switch signal {
        case .noBudget:
            return String(localized: "No budget set")
        case .onTrack:
            return String(localized: "On track")
        case .warning:
            return String(localized: "Watch budget")
        case .overBudget:
            return String(localized: "Over budget")
        }
    }
}

private extension View {
    @ViewBuilder
    func financeNumericTransitionIfAvailable() -> some View {
        if #available(iOS 17.0, *) {
            contentTransition(.numericText())
        } else {
            self
        }
    }

    @ViewBuilder
    func financePulseIfAvailable(trigger: Int) -> some View {
        if #available(iOS 17.0, *) {
            symbolEffect(.bounce, value: trigger)
        } else {
            self
        }
    }
}
