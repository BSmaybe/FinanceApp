import SwiftUI
import SwiftData

struct SubscriptionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var subscriptions: [Subscription]
    @Query private var categories: [Category]

    @State private var showingAdd = false
    @State private var editingSubscription: Subscription? = nil

    private var activeSubscriptions: [Subscription] {
        subscriptions.filter { $0.isActive }
    }

    private var cancelledSubscriptions: [Subscription] {
        subscriptions.filter { !$0.isActive }
    }

    private var totalMonthlyCost: Decimal {
        activeSubscriptions.reduce(.zero) { $0 + $1.monthlyCost }
    }

    private var totalYearlyCost: Decimal {
        activeSubscriptions.reduce(.zero) { $0 + $1.yearlyCost }
    }

    var body: some View {
        NavigationStack {
            List {
                if subscriptions.isEmpty {
                    ContentUnavailableView(
                        String(localized: "No Subscriptions"),
                        systemImage: "repeat.circle",
                        description: Text(String(localized: "Tap + to add your first subscription."))
                    )
                } else {
                    // Summary header
                    Section {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(String(localized: "Monthly"))
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.primaryAccent)
                                Text(CurrencyFormatter.string(from: totalMonthlyCost))
                                    .font(.title3.bold().monospacedDigit())
                                    .foregroundStyle(.primary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(String(localized: "Yearly"))
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.primaryAccent)
                                Text(CurrencyFormatter.string(from: totalYearlyCost))
                                    .font(.title3.bold().monospacedDigit())
                                    .foregroundStyle(.primary)
                            }
                        }
                        .padding(.vertical, 4)
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(AppTheme.subscriptionGradient)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                        )
                    }

                    // Active subscriptions
                    if !activeSubscriptions.isEmpty {
                        Section(String(localized: "Active")) {
                            ForEach(activeSubscriptions) { subscription in
                                SubscriptionRow(
                                    subscription: subscription,
                                    category: categories.first { $0.id == subscription.categoryId }
                                )
                                .swipeActions(edge: .trailing) {
                                    Button {
                                        subscription.isActive = false
                                        try? modelContext.save()
                                    } label: {
                                        Label(String(localized: "Cancel"), systemImage: "xmark.circle")
                                    }
                                    .tint(.orange)
                                }
                                .contextMenu {
                                    Button(String(localized: "Edit")) { editingSubscription = subscription }
                                    Button(String(localized: "Cancel Subscription"), role: .destructive) {
                                        subscription.isActive = false
                                        try? modelContext.save()
                                    }
                                }
                            }
                            .onDelete(perform: deleteActive)
                        }
                    }

                    // Cancelled subscriptions
                    if !cancelledSubscriptions.isEmpty {
                        Section(String(localized: "Cancelled")) {
                            ForEach(cancelledSubscriptions) { subscription in
                                SubscriptionRow(
                                    subscription: subscription,
                                    category: categories.first { $0.id == subscription.categoryId }
                                )
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        modelContext.delete(subscription)
                                        try? modelContext.save()
                                    } label: {
                                        Label(String(localized: "Delete"), systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .leading) {
                                    Button {
                                        subscription.isActive = true
                                        try? modelContext.save()
                                    } label: {
                                        Label(String(localized: "Reactivate"), systemImage: "arrow.uturn.left")
                                    }
                                    .tint(.green)
                                }
                                .contextMenu {
                                    Button(String(localized: "Reactivate")) {
                                        subscription.isActive = true
                                        try? modelContext.save()
                                    }
                                    Button(String(localized: "Delete"), role: .destructive) {
                                        modelContext.delete(subscription)
                                        try? modelContext.save()
                                    }
                                }
                            }
                            .onDelete(perform: deleteCancelled)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .financeNavigationSurface()
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
                SubscriptionNotificationHelper.scheduleReminders(subscriptions: activeSubscriptions)
            }
        } // NavigationStack
    }

    private func deleteActive(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(activeSubscriptions[index])
        }
        try? modelContext.save()
    }

    private func deleteCancelled(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(cancelledSubscriptions[index])
        }
        try? modelContext.save()
    }
}

// MARK: - SubscriptionRow

private struct SubscriptionRow: View {
    let subscription: Subscription
    let category: Category?

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(subscription.name)
                    .font(.body)
                    .strikethrough(!subscription.isActive)
                    .foregroundStyle(subscription.isActive ? .primary : .secondary)
                HStack(spacing: 4) {
                    Text(subscription.frequency.localizedName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let category {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Circle()
                            .fill(Color(hex: category.colorHex))
                            .frame(width: 6, height: 6)
                        Text(category.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if subscription.isActive {
                    Text(String(localized: "Next: \(Self.dateFormatter.string(from: subscription.nextBillingDate))"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(CurrencyFormatter.string(from: subscription.amount))
                    .font(.body.monospacedDigit())
                    .foregroundStyle(subscription.isActive ? .primary : .secondary)
                Text(CurrencyFormatter.string(from: subscription.monthlyCost) + String(localized: "/mo"))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
