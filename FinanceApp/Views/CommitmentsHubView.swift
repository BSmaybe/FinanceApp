import SwiftUI
import SwiftData

struct CommitmentsHubView: View {
    @Query private var debts: [Debt]
    @Query private var subscriptions: [Subscription]
    @Query private var recurringTransactions: [RecurringTransaction]

    @State private var showingDebts = false
    @State private var showingSubscriptions = false
    @State private var showingRecurring = false

    private let summaryColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private var activeDebts: [Debt] {
        debts
            .filter { $0.remainingAmount > 0 }
            .sorted { $0.remainingAmount > $1.remainingAmount }
    }

    private var activeSubscriptions: [Subscription] {
        subscriptions
            .filter(\.isActive)
            .sorted { $0.nextBillingDate < $1.nextBillingDate }
    }

    private var activeRecurringTransactions: [RecurringTransaction] {
        recurringTransactions
            .filter(\.isActive)
            .sorted { $0.startDate < $1.startDate }
    }

    private var monthlyOutflow: Decimal {
        CommitmentsPlanner.monthlyOutflow(
            debts: activeDebts,
            subscriptions: activeSubscriptions,
            recurringTransactions: activeRecurringTransactions
        )
    }

    private var monthlyInflow: Decimal {
        CommitmentsPlanner.monthlyInflow(recurringTransactions: activeRecurringTransactions)
    }

    private var debtMonthlyLoad: Decimal {
        activeDebts.reduce(Decimal.zero) { $0 + min($1.remainingAmount, $1.minimumPayment) }
    }

    private var debtRemainingTotal: Decimal {
        activeDebts.reduce(Decimal.zero) { $0 + $1.remainingAmount }
    }

    private var subscriptionMonthlyLoad: Decimal {
        activeSubscriptions.reduce(Decimal.zero) { $0 + $1.monthlyCost }
    }

    private var recurringExpenseMonthlyLoad: Decimal {
        activeRecurringTransactions
            .filter { $0.type == .expense }
            .reduce(Decimal.zero) { $0 + CommitmentsPlanner.monthlyEquivalent(amount: $1.amount, frequency: $1.frequency) }
    }

    private var activeObligationCount: Int {
        activeDebts.count + activeSubscriptions.count + activeRecurringTransactions.count
    }

    private var upcomingItems: [CommitmentScheduleItem] {
        CommitmentsPlanner.upcomingItems(
            debts: activeDebts,
            subscriptions: activeSubscriptions,
            recurringTransactions: activeRecurringTransactions,
            limit: 10
        )
    }

    private var dueSoonItems: [CommitmentScheduleItem] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let inSevenDays = calendar.date(byAdding: .day, value: 7, to: today) ?? today

        return upcomingItems.filter {
            $0.isExpense &&
            $0.date >= today &&
            $0.date <= inSevenDays
        }
    }

    private var statusBadge: String {
        if activeObligationCount == 0 {
            return String(localized: "No active obligations")
        }
        if dueSoonItems.count > 0 {
            return String(format: String(localized: "%lld due soon"), Int64(dueSoonItems.count))
        }
        return String(localized: "Payments in rhythm")
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    heroSection
                    overviewSection
                    upcomingSection
                    manageSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .financeNavigationSurface()
            .navigationTitle(String(localized: "Commitments"))
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingDebts) {
                DebtsView()
                    .presentationCornerRadius(24)
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingSubscriptions) {
                SubscriptionsView()
                    .presentationCornerRadius(24)
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingRecurring) {
                NavigationStack {
                    RecurringTransactionsView()
                }
                .presentationCornerRadius(24)
                .presentationDragIndicator(.visible)
            }
        }
    }

    private var heroSection: some View {
        HeroMetricCard(
            title: String(localized: "Commitments"),
            value: CurrencyFormatter.string(from: monthlyOutflow),
            supportingTitle: String(localized: "Planned inflow"),
            supportingValue: CurrencyFormatter.string(from: monthlyInflow),
            note: String(localized: "Debt minimums, subscriptions and recurring rules in one operating view."),
            badgeText: statusBadge
        )
    }

    private var overviewSection: some View {
        LazyVGrid(columns: summaryColumns, spacing: 12) {
            CompactSummaryCard(
                title: String(localized: "Due in 7 days"),
                value: "\(dueSoonItems.count)",
                detail: CurrencyFormatter.string(from: dueSoonItems.reduce(Decimal.zero) { $0 + $1.amount }),
                systemImage: "calendar.badge.clock",
                tint: AppTheme.warning
            )

            CompactSummaryCard(
                title: String(localized: "Debts"),
                value: "\(activeDebts.count)",
                detail: CurrencyFormatter.string(from: debtMonthlyLoad),
                systemImage: "creditcard.fill",
                tint: AppTheme.danger
            )

            CompactSummaryCard(
                title: String(localized: "Subscriptions"),
                value: "\(activeSubscriptions.count)",
                detail: CurrencyFormatter.string(from: subscriptionMonthlyLoad),
                systemImage: "repeat.circle.fill",
                tint: AppTheme.primaryAccent
            )

            CompactSummaryCard(
                title: String(localized: "Recurring"),
                value: "\(activeRecurringTransactions.count)",
                detail: CurrencyFormatter.string(from: recurringExpenseMonthlyLoad),
                systemImage: "arrow.clockwise.circle.fill",
                tint: AppTheme.info
            )
        }
    }

    private var upcomingSection: some View {
        SectionShell(
            title: String(localized: "Upcoming obligations"),
            subtitle: String(localized: "Review upcoming obligations and progress.")
        ) {
            if upcomingItems.isEmpty {
                InsightCard(
                    title: String(localized: "Nothing scheduled yet"),
                    value: String(localized: "No upcoming payments"),
                    message: String(localized: "Upcoming debt, subscription and recurring events will appear here."),
                    systemImage: "calendar.badge.exclamationmark",
                    tint: AppTheme.info
                )
            } else {
                VStack(spacing: 12) {
                    ForEach(upcomingItems) { item in
                        upcomingRow(item)
                    }
                }
            }
        }
    }

    private var manageSection: some View {
        SectionShell(title: String(localized: "Manage")) {
            VStack(spacing: 10) {
                managerRow(
                    title: String(localized: "Debts"),
                    subtitle: "\(activeDebts.count) · \(CurrencyFormatter.string(from: debtRemainingTotal))",
                    systemImage: "creditcard.fill",
                    tint: AppTheme.warning
                ) {
                    showingDebts = true
                }

                managerRow(
                    title: String(localized: "Subscriptions"),
                    subtitle: "\(activeSubscriptions.count) · \(CurrencyFormatter.string(from: subscriptionMonthlyLoad))",
                    systemImage: "repeat.circle.fill",
                    tint: AppTheme.primaryAccent
                ) {
                    showingSubscriptions = true
                }

                managerRow(
                    title: String(localized: "Recurring Transactions"),
                    subtitle: "\(activeRecurringTransactions.count) · \(CurrencyFormatter.string(from: recurringExpenseMonthlyLoad))",
                    systemImage: "arrow.clockwise.circle.fill",
                    tint: AppTheme.info
                ) {
                    showingRecurring = true
                }
            }
        }
    }

    private func upcomingRow(_ item: CommitmentScheduleItem) -> some View {
        let tint = itemTint(for: item)

        return HStack(spacing: 12) {
            Image(systemName: itemIcon(for: item))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text("\(sourceLabel(for: item.source)) · \(item.date.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 10)

            Text(CurrencyFormatter.string(from: item.amount))
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(tint)
                .multilineTextAlignment(.trailing)
        }
        .padding(14)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppTheme.outline.opacity(0.45), lineWidth: 0.5)
        )
    }

    private func managerRow(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 38, height: 38)
                    .background(tint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Spacer(minLength: 10)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(AppTheme.outline.opacity(0.45), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func itemTint(for item: CommitmentScheduleItem) -> Color {
        switch item.source {
        case .debt:
            return AppTheme.warning
        case .subscription:
            return AppTheme.primaryAccent
        case .recurring:
            switch item.transactionType {
            case .income:
                return AppTheme.success
            case .expense:
                return AppTheme.danger
            case .transfer:
                return AppTheme.info
            }
        }
    }

    private func itemIcon(for item: CommitmentScheduleItem) -> String {
        switch item.source {
        case .debt:
            return "creditcard.fill"
        case .subscription:
            return "repeat.circle.fill"
        case .recurring:
            switch item.transactionType {
            case .income:
                return "arrow.down.circle.fill"
            case .expense:
                return "arrow.up.circle.fill"
            case .transfer:
                return "arrow.left.arrow.right.circle.fill"
            }
        }
    }

    private func sourceLabel(for source: CommitmentScheduleSource) -> String {
        switch source {
        case .debt:
            return String(localized: "Debts")
        case .subscription:
            return String(localized: "Subscriptions")
        case .recurring:
            return String(localized: "Recurring")
        }
    }
}
