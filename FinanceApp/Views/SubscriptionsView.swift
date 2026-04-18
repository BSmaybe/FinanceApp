import SwiftUI
import SwiftData

struct SubscriptionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var subscriptions: [Subscription]
    @Query private var categories: [Category]

    @State private var showingAdd = false
    @State private var editingSubscription: Subscription? = nil

    private var activeSubscriptions: [Subscription] {
        subscriptions
            .filter { $0.isActive }
            .sorted { $0.nextBillingDate < $1.nextBillingDate }
    }

    private var cancelledSubscriptions: [Subscription] {
        subscriptions
            .filter { !$0.isActive }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var totalMonthlyCost: Decimal {
        activeSubscriptions.reduce(.zero) { $0 + $1.monthlyCost }
    }

    private var totalYearlyCost: Decimal {
        activeSubscriptions.reduce(.zero) { $0 + $1.yearlyCost }
    }

    private var dueSoonCount: Int {
        activeSubscriptions.filter { daysUntil($0.nextBillingDate) <= 7 }.count
    }

    private var statusBadge: String {
        if activeSubscriptions.isEmpty {
            return String(localized: "No active services")
        }
        if dueSoonCount > 0 {
            return String(format: String(localized: "%lld renew soon"), dueSoonCount)
        }
        return String(localized: "Recurring costs stable")
    }

    private let summaryColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.canvas
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        heroSection

                        if subscriptions.isEmpty {
                            emptyStateSection
                        } else {
                            overviewSection
                            activeSection

                            if !cancelledSubscriptions.isEmpty {
                                cancelledSection
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle(String(localized: "Subscriptions"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddEditSubscriptionView()
            }
            .sheet(item: $editingSubscription) { item in
                AddEditSubscriptionView(subscription: item)
            }
            .onAppear {
                rescheduleReminders()
            }
        }
    }

    private var heroSection: some View {
        HeroMetricCard(
            title: String(localized: "Monthly subscriptions"),
            value: CurrencyFormatter.string(from: totalMonthlyCost),
            supportingTitle: String(localized: "Yearly cost"),
            supportingValue: CurrencyFormatter.string(from: totalYearlyCost),
            note: String(localized: "Recurring services and renewals grouped in one operating view."),
            badgeText: statusBadge
        )
    }

    private var overviewSection: some View {
        LazyVGrid(columns: summaryColumns, spacing: 12) {
            CompactSummaryCard(
                title: String(localized: "Active"),
                value: "\(activeSubscriptions.count)",
                detail: String(localized: "Running services"),
                systemImage: "repeat.circle.fill",
                tint: AppTheme.primaryAccent
            )

            CompactSummaryCard(
                title: String(localized: "Due soon"),
                value: "\(dueSoonCount)",
                detail: String(localized: "Renewals in 7 days"),
                systemImage: "calendar.badge.clock",
                tint: AppTheme.warning
            )

            CompactSummaryCard(
                title: String(localized: "Cancelled"),
                value: "\(cancelledSubscriptions.count)",
                detail: String(localized: "Inactive services"),
                systemImage: "xmark.seal.fill",
                tint: AppTheme.info
            )

            CompactSummaryCard(
                title: String(localized: "Yearly cost"),
                value: CurrencyFormatter.string(from: totalYearlyCost),
                detail: String(localized: "Projected annual spend"),
                systemImage: "chart.bar.xaxis",
                tint: AppTheme.success
            )
        }
    }

    private var emptyStateSection: some View {
        SectionShell(
            title: String(localized: "Track recurring services"),
            subtitle: String(localized: "Keep streaming, apps and other automatic renewals visible before they stack up.")
        ) {
            VStack(spacing: 12) {
                InsightCard(
                    title: String(localized: "No subscriptions yet"),
                    value: String(localized: "Add your first service"),
                    message: String(localized: "Recurring charges become easier to review when renewals, categories and monthly cost sit in one place."),
                    systemImage: "repeat.circle",
                    tint: AppTheme.primaryAccent
                )

                ActionTile(
                    title: String(localized: "Add Subscription"),
                    subtitle: String(localized: "Track a recurring charge and its next renewal."),
                    systemImage: "plus.circle.fill",
                    tint: AppTheme.primaryAccent
                ) {
                    showingAdd = true
                }
            }
        }
    }

    private var activeSection: some View {
        SectionShell(
            title: String(localized: "Active services"),
            subtitle: String(localized: "Upcoming renewals and recurring commitments.")
        ) {
            VStack(spacing: 12) {
                if activeSubscriptions.isEmpty {
                    InsightCard(
                        title: String(localized: "Nothing renewing right now"),
                        value: String(localized: "No active subscriptions"),
                        message: String(localized: "Cancelled subscriptions stay below, and you can reactivate them whenever needed."),
                        systemImage: "checkmark.circle.fill",
                        tint: AppTheme.success
                    )
                } else {
                    ForEach(activeSubscriptions) { subscription in
                        Button {
                            editingSubscription = subscription
                        } label: {
                            SubscriptionCard(
                                subscription: subscription,
                                category: categories.first { $0.id == subscription.categoryId },
                                cancelled: false
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(String(localized: "Edit")) {
                                editingSubscription = subscription
                            }
                            Button(String(localized: "Cancel Subscription"), role: .destructive) {
                                cancel(subscription)
                            }
                        }
                    }
                }
            }
        }
    }

    private var cancelledSection: some View {
        SectionShell(
            title: String(localized: "Cancelled services"),
            subtitle: String(localized: "Keep inactive subscriptions for quick reactivation or cleanup.")
        ) {
            VStack(spacing: 12) {
                ForEach(cancelledSubscriptions) { subscription in
                    SubscriptionCard(
                        subscription: subscription,
                        category: categories.first { $0.id == subscription.categoryId },
                        cancelled: true
                    )
                    .contextMenu {
                        Button(String(localized: "Reactivate")) {
                            reactivate(subscription)
                        }
                        Button(String(localized: "Delete"), role: .destructive) {
                            delete(subscription)
                        }
                    }
                }
            }
        }
    }

    private func daysUntil(_ date: Date) -> Int {
        Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: date)).day ?? Int.max
    }

    private func cancel(_ subscription: Subscription) {
        subscription.isActive = false
        try? modelContext.save()
        rescheduleReminders()
    }

    private func reactivate(_ subscription: Subscription) {
        subscription.isActive = true
        try? modelContext.save()
        rescheduleReminders()
    }

    private func delete(_ subscription: Subscription) {
        modelContext.delete(subscription)
        try? modelContext.save()
        rescheduleReminders()
    }

    private func rescheduleReminders() {
        let active = subscriptions.filter { $0.isActive }
        SubscriptionNotificationHelper.scheduleReminders(subscriptions: active)
    }
}

private struct SubscriptionCard: View {
    let subscription: Subscription
    let category: Category?
    let cancelled: Bool

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private var tint: Color {
        category.map { Color(hex: $0.colorHex) } ?? AppTheme.primaryAccent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(subscription.name)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(cancelled ? .secondary : .primary)
                        .strikethrough(cancelled)

                    HStack(spacing: 6) {
                        SubscriptionTag(label: subscription.frequency.localizedName, tint: tint)
                        if let category {
                            SubscriptionTag(label: category.name, tint: Color(hex: category.colorHex))
                        }
                    }
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(CurrencyFormatter.string(from: subscription.amount))
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(cancelled ? .secondary : .primary)
                        .contentTransition(.numericText())
                    Text(CurrencyFormatter.string(from: subscription.monthlyCost) + String(localized: "/mo"))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                subscriptionMetric(
                    title: String(localized: "Next billing"),
                    value: Self.dateFormatter.string(from: subscription.nextBillingDate)
                )

                Spacer(minLength: 0)

                subscriptionMetric(
                    title: String(localized: "Yearly"),
                    value: CurrencyFormatter.string(from: subscription.yearlyCost)
                )

                Spacer(minLength: 0)

                subscriptionMetric(
                    title: String(localized: "Status"),
                    value: cancelled ? String(localized: "Cancelled") : String(localized: "Active"),
                    tint: cancelled ? .secondary : AppTheme.success
                )
            }

            if !subscription.note.isEmpty {
                Text(subscription.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cockpitSurface(cornerRadius: 24, elevated: true)
    }

    private func subscriptionMetric(title: String, value: String, tint: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .contentTransition(.numericText())
        }
    }
}

private struct SubscriptionTag: View {
    let label: String
    let tint: Color

    var body: some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
    }
}
