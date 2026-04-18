import SwiftUI

struct FeaturesSettingsView: View {
    @AppStorage("feature.transactions") private var featureTransactions = true
    @AppStorage("feature.analytics") private var featureAnalytics = true
    @AppStorage("feature.budgets") private var featureBudgets = true
    @AppStorage("feature.goals") private var featureGoals = true
    @AppStorage("feature.debts") private var featureDebts = true
    @AppStorage("feature.subscriptions") private var featureSubscriptions = true

    var body: some View {
        ZStack {
            AppTheme.canvas.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    HeroMetricCard(
                        title: String(localized: "Features"),
                        value: "\(enabledCount)",
                        supportingTitle: String(localized: "Available Modules"),
                        supportingValue: "6",
                        note: String(localized: "Keep only the product layers you actively use. Core balances remain always on."),
                        badgeText: String(localized: "Control")
                    )

                    SectionShell(
                        title: String(localized: "Core"),
                        subtitle: String(localized: "Balances and account structure stay available for the whole product.")
                    ) {
                        featureCard(
                            icon: "creditcard.and.123",
                            color: Color(red: 0.92, green: 0.75, blue: 0.20),
                            title: String(localized: "Accounts & Balances"),
                            subtitle: String(localized: "Always enabled"),
                            isOn: .constant(true),
                            disabled: true
                        )
                    }

                    SectionShell(
                        title: String(localized: "Optional Features"),
                        subtitle: String(localized: "Turn modules on or off without affecting the underlying data.")
                    ) {
                        VStack(spacing: 12) {
                            featureCard(
                                icon: "arrow.up.arrow.down.circle.fill",
                                color: Color(red: 0.18, green: 0.72, blue: 0.56),
                                title: String(localized: "Income & Expenses"),
                                subtitle: String(localized: "Transactions tab"),
                                isOn: $featureTransactions
                            )
                            featureCard(
                                icon: "chart.bar.fill",
                                color: Color(red: 0.24, green: 0.48, blue: 0.98),
                                title: String(localized: "Analytics"),
                                subtitle: String(localized: "Charts and spending insights"),
                                isOn: $featureAnalytics
                            )
                            featureCard(
                                icon: "gauge.with.needle.fill",
                                color: Color(red: 0.92, green: 0.55, blue: 0.20),
                                title: String(localized: "Budgets"),
                                subtitle: String(localized: "Monthly category limits"),
                                isOn: $featureBudgets
                            )
                            featureCard(
                                icon: "target",
                                color: Color(red: 0.62, green: 0.35, blue: 0.95),
                                title: String(localized: "Savings Goals"),
                                subtitle: String(localized: "Track progress to targets"),
                                isOn: $featureGoals
                            )
                            featureCard(
                                icon: "creditcard.fill",
                                color: Color(red: 0.90, green: 0.28, blue: 0.30),
                                title: String(localized: "Debts & Subscriptions"),
                                subtitle: String(localized: "Loans and recurring bills"),
                                isOn: Binding(
                                    get: { featureDebts },
                                    set: { value in
                                        featureDebts = value
                                        featureSubscriptions = value
                                    }
                                )
                            )
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .navigationTitle(String(localized: "Features"))
        .navigationBarTitleDisplayMode(.inline)
        .financeNavigationSurface()
    }

    private var enabledCount: Int {
        [true, featureTransactions, featureAnalytics, featureBudgets, featureGoals, featureDebts]
            .filter { $0 }
            .count
    }

    private func featureCard(
        icon: String,
        color: Color,
        title: String,
        subtitle: String,
        isOn: Binding<Bool>,
        disabled: Bool = false
    ) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(color.opacity(0.15))
                        .frame(width: 42, height: 42)
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(color)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .disabled(disabled)
        .tint(color)
        .padding(14)
        .background(AppTheme.elevatedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .opacity(disabled ? 0.9 : 1)
    }
}
