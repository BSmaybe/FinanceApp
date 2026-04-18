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
                        Text(leadingPrimaryText(for: context.state))
                            .font(.title2.bold())
                            .monospacedDigit()
                            .financeNumericTransitionIfAvailable()
                    } icon: {
                        Image(systemName: displayIcon(for: context.state))
                            .financeIconEffect(for: context.state)
                    }
                    .foregroundStyle(tone)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(trailingLabel(for: context.state))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(trailingValueText(for: context.state))
                            .font(.callout.bold().monospacedDigit())
                            .financeNumericTransitionIfAvailable()
                            .foregroundStyle(trailingValueTone(for: context.state))
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(displayLabel(for: context.state))
                                .font(.caption.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(tone.opacity(0.18), in: Capsule())
                                .foregroundStyle(tone)
                            Spacer()
                            Text(bottomSummaryText(for: context.state))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .financeNumericTransitionIfAvailable()
                                .lineLimit(1)
                        }

                        ProgressView(value: context.state.progress)
                            .tint(tone)
                            .animation(.spring(response: 0.45, dampingFraction: 0.86), value: context.state.progress)
                    }
                    .padding(.horizontal)
                }
            } compactLeading: {
                Image(systemName: displayIcon(for: context.state))
                    .financeIconEffect(for: context.state)
                    .foregroundStyle(tone)
            } compactTrailing: {
                Text(compactTrailingText(for: context.state))
                    .font(.caption2.bold().monospacedDigit())
                    .financeNumericTransitionIfAvailable()
                    .foregroundStyle(tone)
                    .lineLimit(1)
            } minimal: {
                Image(systemName: displayIcon(for: context.state))
                    .financeIconEffect(for: context.state)
                    .foregroundStyle(tone)
            }
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
                Text(lockScreenPrimaryAmount(for: context.state))
                    .font(.title3.bold().monospacedDigit())
                    .financeNumericTransitionIfAvailable()
                Text(lockScreenSecondaryText(for: context.state))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(displayLabel(for: context.state))
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(tone.opacity(0.18), in: Capsule())
                    .foregroundStyle(tone)
            }
            Spacer()
            VStack(spacing: 6) {
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
                        .financeIconEffect(for: context.state)
                    Text(percentText(for: context.state))
                        .font(.caption2.bold())
                        .monospacedDigit()
                        .offset(y: 15)
                        .financeNumericTransitionIfAvailable()
                }
                .frame(width: 52, height: 52)
                Text(lockScreenTrailingText(for: context.state))
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(lockScreenTrailingTone(for: context.state))
                    .financeNumericTransitionIfAvailable()
                    .lineLimit(1)
            }
        }
        .padding(16)
    }
}

@available(iOS 16.2, *)
private func percentText(for state: DailyBudgetAttributes.ContentState) -> String {
    String(format: "%.0f%%", state.progress * 100)
}

@available(iOS 16.2, *)
private func amountText(for value: Double, currencySymbol: String) -> String {
    "\(currencySymbol)\(String(format: "%.0f", value))"
}

@available(iOS 16.2, *)
private func signedAmountText(for state: DailyBudgetAttributes.ContentState) -> String? {
    guard let amount = state.celebrationAmount else { return nil }
    let absolute = amountText(for: abs(amount), currencySymbol: state.currencySymbol)
    switch state.celebration {
    case .incomeAdded:
        return "+\(absolute)"
    case .expenseLogged:
        return "-\(absolute)"
    default:
        return nil
    }
}

@available(iOS 16.2, *)
private func detailText(for state: DailyBudgetAttributes.ContentState) -> String? {
    guard let detail = state.celebrationDetail?.trimmingCharacters(in: .whitespacesAndNewlines), !detail.isEmpty else {
        return nil
    }
    return detail
}

@available(iOS 16.2, *)
private func signalIcon(_ signal: DailyBudgetAttributes.ContentState.Signal) -> String {
    switch signal {
    case .noBudget:      return "questionmark.circle.fill"
    case .onTrack:       return "checkmark.circle.fill"
    case .warning:       return "exclamationmark.triangle.fill"
    case .overBudget:    return "flame.fill"
    }
}

@available(iOS 16.2, *)
private func signalTone(_ signal: DailyBudgetAttributes.ContentState.Signal) -> Color {
    switch signal {
    case .noBudget:   return .blue
    case .onTrack:    return .green
    case .warning:    return .orange
    case .overBudget: return .red
    }
}

@available(iOS 16.2, *)
private func signalLabel(_ signal: DailyBudgetAttributes.ContentState.Signal) -> String {
    switch signal {
    case .noBudget:   return String(localized: "No budget set")
    case .onTrack:    return String(localized: "On track")
    case .warning:    return String(localized: "Watch budget")
    case .overBudget: return String(localized: "Over budget")
    }
}

@available(iOS 16.2, *)
private func displayIcon(for state: DailyBudgetAttributes.ContentState) -> String {
    switch state.celebration {
    case .goalReached: return "sparkles"
    case .debtPaidOff: return "checkmark.seal.fill"
    case .incomeAdded: return "arrow.down.circle.fill"
    case .expenseLogged: return "arrow.up.circle.fill"
    case .budgetWarning: return "bell.badge.fill"
    case .none:        return signalIcon(state.signal)
    }
}

@available(iOS 16.2, *)
private func displayTone(for state: DailyBudgetAttributes.ContentState) -> Color {
    switch state.celebration {
    case .goalReached: return .purple
    case .debtPaidOff: return .mint
    case .incomeAdded: return .green
    case .expenseLogged: return .orange
    case .budgetWarning: return .orange
    case .none:        return signalTone(state.signal)
    }
}

@available(iOS 16.2, *)
private func displayLabel(for state: DailyBudgetAttributes.ContentState) -> String {
    switch state.celebration {
    case .goalReached: return String(localized: "Goal reached")
    case .debtPaidOff: return String(localized: "Debt paid off")
    case .incomeAdded: return String(localized: "Income added")
    case .expenseLogged: return String(localized: "Expense logged")
    case .budgetWarning: return String(localized: "Budget alert")
    case .none:        return signalLabel(state.signal)
    }
}

@available(iOS 16.2, *)
private func leadingPrimaryText(for state: DailyBudgetAttributes.ContentState) -> String {
    signedAmountText(for: state) ?? percentText(for: state)
}

@available(iOS 16.2, *)
private func trailingLabel(for state: DailyBudgetAttributes.ContentState) -> String {
    switch state.celebration {
    case .goalReached, .debtPaidOff:
        return String(localized: "Status")
    case .incomeAdded, .expenseLogged:
        return String(localized: "Latest")
    case .budgetWarning:
        return String(localized: "Update")
    case .none:
        return String(localized: "Remaining")
    }
}

@available(iOS 16.2, *)
private func trailingValueText(for state: DailyBudgetAttributes.ContentState) -> String {
    switch state.celebration {
    case .goalReached, .debtPaidOff:
        return displayLabel(for: state)
    case .incomeAdded, .expenseLogged:
        return signedAmountText(for: state) ?? amountText(for: state.remaining, currencySymbol: state.currencySymbol)
    case .budgetWarning:
        return detailText(for: state) ?? percentText(for: state)
    case .none:
        return amountText(for: state.remaining, currencySymbol: state.currencySymbol)
    }
}

@available(iOS 16.2, *)
private func trailingValueTone(for state: DailyBudgetAttributes.ContentState) -> Color {
    switch state.celebration {
    case .goalReached, .debtPaidOff, .incomeAdded, .expenseLogged, .budgetWarning:
        return displayTone(for: state)
    case .none:
        return state.signal == .overBudget ? .red : .primary
    }
}

@available(iOS 16.2, *)
private func compactTrailingText(for state: DailyBudgetAttributes.ContentState) -> String {
    switch state.celebration {
    case .incomeAdded, .expenseLogged:
        return signedAmountText(for: state) ?? percentText(for: state)
    case .budgetWarning:
        return "!"
    case .goalReached, .debtPaidOff:
        return "OK"
    case .none:
        return percentText(for: state)
    }
}

@available(iOS 16.2, *)
private func bottomSummaryText(for state: DailyBudgetAttributes.ContentState) -> String {
    switch state.celebration {
    case .none:
        return "\(amountText(for: state.spentToday, currencySymbol: state.currencySymbol)) / \(amountText(for: state.dailyBudget, currencySymbol: state.currencySymbol))"
    default:
        return detailText(for: state) ?? trailingValueText(for: state)
    }
}

@available(iOS 16.2, *)
private func lockScreenPrimaryAmount(for state: DailyBudgetAttributes.ContentState) -> String {
    signedAmountText(for: state) ?? amountText(for: state.spentToday, currencySymbol: state.currencySymbol)
}

@available(iOS 16.2, *)
private func lockScreenSecondaryText(for state: DailyBudgetAttributes.ContentState) -> String {
    switch state.celebration {
    case .none:
        return "of \(amountText(for: state.dailyBudget, currencySymbol: state.dailyBudget > 0 ? state.currencySymbol : ""))"
    default:
        return detailText(for: state) ?? bottomSummaryText(for: state)
    }
}

@available(iOS 16.2, *)
private func lockScreenTrailingText(for state: DailyBudgetAttributes.ContentState) -> String {
    switch state.celebration {
    case .budgetWarning:
        return detailText(for: state) ?? percentText(for: state)
    case .incomeAdded, .expenseLogged:
        return signedAmountText(for: state) ?? amountText(for: state.remaining, currencySymbol: state.currencySymbol)
    case .goalReached, .debtPaidOff:
        return displayLabel(for: state)
    case .none:
        return amountText(for: state.remaining, currencySymbol: state.currencySymbol)
    }
}

@available(iOS 16.2, *)
private func lockScreenTrailingTone(for state: DailyBudgetAttributes.ContentState) -> Color {
    switch state.celebration {
    case .none:
        return state.signal == .overBudget ? .red : .secondary
    default:
        return displayTone(for: state)
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
    func financeIconEffect(for state: DailyBudgetAttributes.ContentState) -> some View {
        if #available(iOS 17.0, *) {
            switch state.celebration {
            case .goalReached, .debtPaidOff, .incomeAdded:
                self.symbolEffect(.bounce, value: state.pulseToken)
            case .expenseLogged, .budgetWarning:
                self.symbolEffect(.pulse.wholeSymbol, options: .repeat(2), value: state.pulseToken)
            case .none:
                switch state.signal {
                case .overBudget:
                    self.symbolEffect(.variableColor.iterative.reversing,
                                      options: .repeat(3), value: state.pulseToken)
                case .warning:
                    self.symbolEffect(.pulse.wholeSymbol,
                                      options: .repeat(2), value: state.pulseToken)
                case .onTrack, .noBudget:
                    self.symbolEffect(.bounce, value: state.pulseToken)
                }
            }
        } else {
            self
        }
    }
}
