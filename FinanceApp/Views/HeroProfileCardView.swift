import SwiftUI
import SwiftData

struct HeroProfileCardView: View {
    let stats: HeroStats
    let onCTA: (CoachAdviceCTA) -> Void

    @Query private var accounts: [Account]
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query private var categories: [Category]
    @Query private var budgets: [Budget]
    @Query(sort: \Goal.createdDate, order: .reverse) private var goals: [Goal]
    @Query private var debts: [Debt]
    @Query(filter: #Predicate<Subscription> { $0.isActive == true }) private var activeSubscriptions: [Subscription]

    @AppStorage("heroName") private var heroName = "You"
    @State private var showingProfile = false

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

    private var adviceList: [CoachAdvice] {
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

    private var primaryAdvice: CoachAdvice {
        adviceList.first ?? CoachAdvice(
            id: "steady",
            kind: .steadyState,
            priority: .low,
            title: String(localized: "Hold course"),
            message: String(localized: "No sharp intervention today. Stay on plan and keep capture clean."),
            reason: String(localized: "Your current signals do not call for a heavy adjustment."),
            alternative: String(localized: "Use planning time for one thoughtful change instead of many reactive ones."),
            cta: .transactions
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            adviceBlock
            progressStrip
            actionsRow
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .cockpitSurface()
        .sheet(isPresented: $showingProfile) {
            HeroProfileView(stats: stats)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.primaryAccent)
                .frame(width: 42, height: 42)
                .background(AppTheme.primaryAccent.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Coach & Progress"))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("\(heroName) · \(stats.title)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                showingProfile = true
            } label: {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(AppTheme.surfaceMuted)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("dashboard.coach.open")
        }
    }

    private var adviceBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(primaryAdvice.title)
                .font(.caption.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(AppTheme.primaryAccent)
                .textCase(.uppercase)

            Text(primaryAdvice.message)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)

            Text(primaryAdvice.alternative)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Text("\(String(localized: "Runway")) \(vitals.runwayDays)d")
                Text("\(String(localized: "Readiness")) \(vitals.readiness)")
                Text("\(String(localized: "Left to pay")) \(CurrencyFormatter.string(from: vitals.leftToPayNext7Days))")
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }

    private var progressStrip: some View {
        HStack(spacing: 8) {
            progressPill(metric: .readiness, score: vitals.readiness)
            progressPill(metric: .pressure, score: vitals.pressure)
            progressPill(metric: .reserve, score: vitals.reserve)
        }
    }

    private func progressPill(metric: FinancialVitalMetric, score: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(metric.title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text("\(score)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(metric.directionLabel)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(AppTheme.surfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var actionsRow: some View {
        HStack(spacing: 10) {
            Button(primaryAdvice.cta.title) {
                onCTA(primaryAdvice.cta)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.primaryAccent)

            Button(String(localized: "Open coach")) {
                showingProfile = true
            }
            .buttonStyle(.bordered)
            .tint(AppTheme.primaryAccent)
        }
        .font(.subheadline.weight(.semibold))
    }
}
