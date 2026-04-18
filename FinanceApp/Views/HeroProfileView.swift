import SwiftUI
import SwiftData

struct HeroProfileView: View {
    let stats: HeroStats

    @AppStorage("heroName") private var heroName = "You"
    @AppStorage("unlockedAchievements") private var unlockedAchievements = ""

    @Query private var accounts: [Account]
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query private var categories: [Category]
    @Query private var budgets: [Budget]
    @Query(sort: \Goal.createdDate, order: .reverse) private var goals: [Goal]
    @Query private var debts: [Debt]
    @Query(filter: #Predicate<Subscription> { $0.isActive == true }) private var activeSubscriptions: [Subscription]

    @Environment(\.dismiss) private var dismiss

    @State private var editingName = false
    @State private var nameInput = ""

    private var unlockedSet: Set<String> {
        Set(unlockedAchievements.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
    }

    private var currentMonth: Int {
        Calendar.current.component(.month, from: Date())
    }

    private var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    private var summary: CoachProgressSummary {
        CoachAdviceEngine.progressSummary(
            transactions: transactions,
            categories: categories,
            budgets: budgets,
            goals: goals,
            debts: debts,
            month: currentMonth,
            year: currentYear
        )
    }

    private var vitals: FinancialVitals {
        FinancialVitalsEngine.compute(
            accounts: accounts,
            transactions: transactions,
            categories: categories,
            budgets: budgets,
            debts: debts,
            subscriptions: activeSubscriptions,
            month: currentMonth,
            year: currentYear
        )
    }

    private var adviceHistory: [CoachAdvice] {
        CoachAdviceEngine.recommendations(
            transactions: transactions,
            categories: categories,
            budgets: budgets,
            goals: goals,
            debts: debts,
            subscriptions: activeSubscriptions,
            month: currentMonth,
            year: currentYear
        )
    }

    private var unlockedAchievementsList: [Achievement] {
        AchievementStore.all.filter { unlockedSet.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    profileHeader
                    thisWeekSection
                    progressSection
                    milestonesSection
                    adviceHistorySection
                }
                .padding(16)
            }
            .background(AppTheme.canvas)
            .navigationTitle(String(localized: "Coach & Progress"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(String(localized: "Done")) { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private var profileHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryAccent)
                    .frame(width: 58, height: 58)
                    .background(AppTheme.primaryAccent.opacity(0.14))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    if editingName {
                        nameEditField
                    } else {
                        nameDisplay
                    }
                    Text(stats.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "Current focus"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.primaryAccent)
                    .textCase(.uppercase)
                Text(String(localized: "Progress is measured by consistency, healthy planning and calmer decisions."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .cockpitSurface()
    }

    private var nameDisplay: some View {
        HStack(spacing: 6) {
            Text(heroName)
                .font(.title3.weight(.bold))
            Button {
                nameInput = heroName
                editingName = true
            } label: {
                Image(systemName: "pencil.circle.fill")
                    .foregroundStyle(AppTheme.primaryAccent)
            }
            .buttonStyle(.plain)
        }
    }

    private var nameEditField: some View {
        HStack(spacing: 8) {
            TextField(String(localized: "Your name"), text: $nameInput)
                .textFieldStyle(.roundedBorder)
            Button(String(localized: "Save")) {
                let trimmed = nameInput.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    heroName = trimmed
                }
                editingName = false
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.primaryAccent)
        }
    }

    private var thisWeekSection: some View {
        let leadAdvice = adviceHistory.first

        return sectionShell(title: String(localized: "This Week"), systemImage: "calendar") {
            VStack(alignment: .leading, spacing: 10) {
                if let leadAdvice {
                    Text(leadAdvice.title)
                        .font(.headline.weight(.semibold))
                    Text(leadAdvice.message)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Divider()
                    detailRow(label: String(localized: "Why it matters"), value: leadAdvice.reason)
                    detailRow(label: String(localized: "Safer option"), value: leadAdvice.alternative)
                    detailRow(label: String(localized: "Next step"), value: leadAdvice.cta.title)
                } else {
                    Text(String(localized: "No sharp intervention today. Stay on plan and keep capture clean."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var progressSection: some View {
        sectionShell(title: String(localized: "Progress"), systemImage: "chart.line.uptrend.xyaxis") {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    progressMetric(
                        metric: .readiness,
                        score: vitals.readiness
                    )
                    progressMetric(
                        metric: .pressure,
                        score: vitals.pressure
                    )
                    progressMetric(
                        metric: .reserve,
                        score: vitals.reserve
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(String(localized: "Runway"))
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(String(format: String(localized: "%d days"), vitals.runwayDays))
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(AppTheme.primaryAccent)
                    }
                    ProgressView(value: Double(min(vitals.runwayDays, 30)), total: 30)
                        .tint(AppTheme.primaryAccent)
                    HStack {
                        Text(String(localized: "Left to pay"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(CurrencyFormatter.string(from: vitals.leftToPayNext7Days))
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.primary)
                    }
                    HStack {
                        Text(String(localized: "Budget stability"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(vitals.budgetStability)%")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
    }

    private func progressMetric(metric: FinancialVitalMetric, score: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(metric.title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(score)")
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(.primary)
            Text("\(metric.stateLabel(for: score)) · \(metric.directionLabel)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppTheme.surfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var milestonesSection: some View {
        sectionShell(title: String(localized: "Milestones"), systemImage: "checkmark.seal") {
            if unlockedAchievementsList.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "No milestones yet"))
                        .font(.subheadline.weight(.semibold))
                    Text(String(localized: "Milestones will appear as you build healthy habits."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 10) {
                    ForEach(unlockedAchievementsList) { achievement in
                        HStack(spacing: 12) {
                            Image(systemName: achievement.symbolName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.primaryAccent)
                                .frame(width: 36, height: 36)
                                .background(AppTheme.primaryAccent.opacity(0.12))
                                .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 3) {
                                Text(achievement.title)
                                    .font(.subheadline.weight(.semibold))
                                Text(achievement.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(AppTheme.surfaceMuted)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
            }
        }
    }

    private var adviceHistorySection: some View {
        sectionShell(title: String(localized: "Advice History"), systemImage: "text.bubble") {
            VStack(spacing: 10) {
                ForEach(adviceHistory.prefix(3)) { advice in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(advice.title)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(advice.cta.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.primaryAccent)
                        }
                        Text(advice.message)
                            .font(.subheadline)
                        Text(advice.reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(advice.alternative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(AppTheme.surfaceMuted)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
    }

    private func sectionShell<Content: View>(title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline.weight(.semibold))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .cockpitSurface()
    }

    private func detailRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
    }
}
