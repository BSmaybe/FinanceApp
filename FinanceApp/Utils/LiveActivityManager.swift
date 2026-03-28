import Foundation

#if canImport(ActivityKit)
import ActivityKit

@available(iOS 16.2, *)
@MainActor
enum LiveActivityManager {
    enum CelebrationKind {
        case goalReached
        case debtPaidOff
    }

    static func start(spentToday: Double, dailyBudget: Double, currencySymbol: String) {
        guard isEnabled else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // End any existing activity first
        stopAll()

        let attributes = DailyBudgetAttributes(activityTitle: String(localized: "Daily Budget"))
        let state = buildState(
            spentToday: spentToday,
            dailyBudget: dailyBudget,
            currencySymbol: currencySymbol,
            forcePulse: true
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
        let state = buildState(
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

    static func triggerCelebration(_ kind: CelebrationKind) {
        guard isEnabled else { return }
        let celebration: DailyBudgetAttributes.ContentState.Celebration = {
            switch kind {
            case .goalReached:
                return .goalReached
            case .debtPaidOff:
                return .debtPaidOff
            }
        }()

        Task {
            for activity in Activity<DailyBudgetAttributes>.activities {
                var pulseToken = UserDefaults.standard.integer(forKey: pulseTokenKey)
                pulseToken = max(pulseToken, activity.content.state.pulseToken) + 1
                UserDefaults.standard.set(pulseToken, forKey: pulseTokenKey)

                let state = DailyBudgetAttributes.ContentState(
                    spentToday: activity.content.state.spentToday,
                    dailyBudget: activity.content.state.dailyBudget,
                    currencySymbol: activity.content.state.currencySymbol,
                    signal: activity.content.state.signal,
                    pulseToken: pulseToken,
                    celebration: celebration
                )
                await activity.update(ActivityContent(state: state, staleDate: nil))

                try? await Task.sleep(for: .seconds(4))

                let resetState = DailyBudgetAttributes.ContentState(
                    spentToday: state.spentToday,
                    dailyBudget: state.dailyBudget,
                    currencySymbol: state.currencySymbol,
                    signal: state.signal,
                    pulseToken: state.pulseToken,
                    celebration: .none
                )
                await activity.update(ActivityContent(state: resetState, staleDate: nil))
            }
        }
    }

    static func stopAll() {
        Task {
            for activity in Activity<DailyBudgetAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: statusKey)
        defaults.removeObject(forKey: pulseTokenKey)
    }

    private static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "liveActivityEnabled")
    }

    private static let statusKey = "liveActivity.dailyBudget.signal"
    private static let pulseTokenKey = "liveActivity.dailyBudget.pulseToken"

    private static func buildState(
        spentToday: Double,
        dailyBudget: Double,
        currencySymbol: String,
        forcePulse: Bool = false
    ) -> DailyBudgetAttributes.ContentState {
        let signal = resolveSignal(spentToday: spentToday, dailyBudget: dailyBudget)
        let defaults = UserDefaults.standard
        let previousSignalRaw = defaults.string(forKey: statusKey)
        var pulseToken = defaults.integer(forKey: pulseTokenKey)

        if forcePulse || previousSignalRaw != signal.rawValue {
            pulseToken += 1
            defaults.set(pulseToken, forKey: pulseTokenKey)
        }
        defaults.set(signal.rawValue, forKey: statusKey)

        return DailyBudgetAttributes.ContentState(
            spentToday: spentToday,
            dailyBudget: dailyBudget,
            currencySymbol: currencySymbol,
            signal: signal,
            pulseToken: pulseToken,
            celebration: .none
        )
    }

    private static func resolveSignal(
        spentToday: Double,
        dailyBudget: Double
    ) -> DailyBudgetAttributes.ContentState.Signal {
        guard dailyBudget > 0 else { return .noBudget }
        let progress = spentToday / dailyBudget
        if progress > 1.0 {
            return .overBudget
        }
        if progress >= 0.8 {
            return .warning
        }
        return .onTrack
    }
}
#endif
