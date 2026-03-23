import SwiftUI

struct FeaturesSettingsView: View {
    @AppStorage("feature.transactions") private var featureTransactions = true
    @AppStorage("feature.analytics")    private var featureAnalytics = true
    @AppStorage("feature.budgets")      private var featureBudgets = true
    @AppStorage("feature.goals")        private var featureGoals = true
    @AppStorage("feature.debts")        private var featureDebts = true
    @AppStorage("feature.subscriptions") private var featureSubscriptions = true

    var body: some View {
        Form {
            Section {
                featureRow(
                    icon: "creditcard.and.123",
                    color: Color(red: 0.92, green: 0.75, blue: 0.20),
                    title: String(localized: "Accounts & Balances"),
                    subtitle: String(localized: "Always enabled"),
                    isOn: .constant(true)
                )
                .disabled(true)
            } header: {
                Text(String(localized: "Core"))
            }

            Section {
                featureRow(
                    icon: "arrow.up.arrow.down.circle.fill",
                    color: Color(red: 0.18, green: 0.72, blue: 0.56),
                    title: String(localized: "Income & Expenses"),
                    subtitle: String(localized: "Transactions tab"),
                    isOn: $featureTransactions
                )
                featureRow(
                    icon: "chart.bar.fill",
                    color: Color(red: 0.24, green: 0.48, blue: 0.98),
                    title: String(localized: "Analytics"),
                    subtitle: String(localized: "Charts and spending insights"),
                    isOn: $featureAnalytics
                )
                featureRow(
                    icon: "gauge.with.needle.fill",
                    color: Color(red: 0.92, green: 0.55, blue: 0.20),
                    title: String(localized: "Budgets"),
                    subtitle: String(localized: "Monthly category limits"),
                    isOn: $featureBudgets
                )
                featureRow(
                    icon: "target",
                    color: Color(red: 0.62, green: 0.35, blue: 0.95),
                    title: String(localized: "Savings Goals"),
                    subtitle: String(localized: "Track progress to targets"),
                    isOn: $featureGoals
                )
                featureRow(
                    icon: "creditcard.fill",
                    color: Color(red: 0.90, green: 0.28, blue: 0.30),
                    title: String(localized: "Debts & Subscriptions"),
                    subtitle: String(localized: "Loans and recurring bills"),
                    isOn: Binding(
                        get: { featureDebts },
                        set: { v in featureDebts = v; featureSubscriptions = v }
                    )
                )
            } header: {
                Text(String(localized: "Optional Features"))
            } footer: {
                Text(String(localized: "You can turn features on or off at any time."))
            }
        }
        .navigationTitle(String(localized: "Features"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func featureRow(
        icon: String,
        color: Color,
        title: String,
        subtitle: String,
        isOn: Binding<Bool>
    ) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(color.opacity(0.15))
                        .frame(width: 34, height: 34)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .tint(color)
    }
}
