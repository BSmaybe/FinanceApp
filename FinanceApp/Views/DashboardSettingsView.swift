import SwiftUI

struct DashboardSettingsView: View {
    var showsDoneButton: Bool = false

    @AppStorage("dash.showOverview") private var showOverview = true
    @AppStorage("dash.showVitals") private var showVitals = true
    @AppStorage("dash.showAccounts") private var showAccounts = true
    @AppStorage("dash.showQuickActions") private var showQuickActions = true
    @AppStorage("dash.showThisMonth") private var showThisMonth = true
    @AppStorage("dash.showDebts") private var showDebts = true
    @AppStorage("dash.showCommitments") private var showCommitments = true
    @AppStorage("dash.showWeeklyBudget") private var showWeeklyBudget = true
    @AppStorage("dash.showRecentActivity") private var showRecentActivity = true
    @AppStorage("dash.showHeroCard") private var showHeroCard = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AppTheme.canvas.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    HeroMetricCard(
                        title: String(localized: "Dashboard Settings"),
                        value: "\(enabledCount)",
                        supportingTitle: String(localized: "Available Sections"),
                        supportingValue: "10",
                        note: String(localized: "Keep the dashboard glanceable. Hide sections you do not need every day."),
                        badgeText: String(localized: "Layout")
                    )

                    SectionShell(
                        title: String(localized: "Layout Actions"),
                        subtitle: String(localized: "Restore the full layout or hide everything and build it back up.")
                    ) {
                        HStack(spacing: 10) {
                            Button(String(localized: "Show all")) {
                                setAllSections(true)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(AppTheme.primaryAccent)

                            Button(String(localized: "Hide all")) {
                                setAllSections(false)
                            }
                            .buttonStyle(.bordered)
                            .tint(AppTheme.primaryAccent)
                        }
                    }

                    SectionShell(
                        title: String(localized: "Visible Sections"),
                        subtitle: String(localized: "Choose which blocks appear on the dashboard.")
                    ) {
                        VStack(spacing: 12) {
                            toggleCard(
                                title: String(localized: "Overview"),
                                subtitle: String(localized: "Top summary with available funds and the month snapshot."),
                                systemImage: "rectangle.tophalf.inset.filled",
                                tint: AppTheme.primaryAccent,
                                isOn: $showOverview
                            )
                            toggleCard(
                                title: String(localized: "Financial Vitals"),
                                subtitle: String(localized: "Readiness, pressure, reserve, runway and left to pay."),
                                systemImage: "waveform.path.ecg.rectangle",
                                tint: AppTheme.info,
                                isOn: $showVitals
                            )
                            toggleCard(
                                title: String(localized: "Accounts overview"),
                                subtitle: String(localized: "Balances and where your money is sitting."),
                                systemImage: "creditcard.and.123",
                                tint: AppTheme.sectionAccent,
                                isOn: $showAccounts
                            )
                            toggleCard(
                                title: String(localized: "Primary Actions"),
                                subtitle: String(localized: "Fast entrypoints for capture, budgets, and calendar."),
                                systemImage: "square.grid.2x2.fill",
                                tint: AppTheme.primaryAccent,
                                isOn: $showQuickActions
                            )
                            toggleCard(
                                title: String(localized: "Coach & Progress"),
                                subtitle: String(localized: "Reflective coach insight and money progress signals."),
                                systemImage: "sparkles",
                                tint: AppTheme.info,
                                isOn: $showHeroCard
                            )
                            toggleCard(
                                title: String(localized: "This Month"),
                                subtitle: String(localized: "Income, expense, net, and allowance summary."),
                                systemImage: "calendar",
                                tint: AppTheme.success,
                                isOn: $showThisMonth
                            )
                            toggleCard(
                                title: String(localized: "Debts"),
                                subtitle: String(localized: "Separate debt snapshot if you still want it pinned."),
                                systemImage: "creditcard",
                                tint: AppTheme.warning,
                                isOn: $showDebts
                            )
                            toggleCard(
                                title: String(localized: "Commitments"),
                                subtitle: String(localized: "Goals, subscriptions, and recurring obligations."),
                                systemImage: "tray.full",
                                tint: AppTheme.primaryAccent,
                                isOn: $showCommitments
                            )
                            toggleCard(
                                title: String(localized: "Weekly Budget"),
                                subtitle: String(localized: "Current week spending by category and remaining headroom."),
                                systemImage: "calendar.badge.clock",
                                tint: AppTheme.warning,
                                isOn: $showWeeklyBudget
                            )
                            toggleCard(
                                title: String(localized: "Recent Activity"),
                                subtitle: String(localized: "Latest transactions preview with jump to journal."),
                                systemImage: "clock.arrow.circlepath",
                                tint: AppTheme.chartNeutral,
                                isOn: $showRecentActivity
                            )
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .navigationTitle(String(localized: "Dashboard Settings"))
        .navigationBarTitleDisplayMode(.inline)
        .financeNavigationSurface()
        .toolbar {
            if showsDoneButton {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
        }
    }

    private var enabledCount: Int {
        [
            showOverview,
            showVitals,
            showAccounts,
            showQuickActions,
            showThisMonth,
            showDebts,
            showCommitments,
            showWeeklyBudget,
            showRecentActivity,
            showHeroCard
        ]
        .filter { $0 }
        .count
    }

    private func setAllSections(_ isVisible: Bool) {
        showOverview = isVisible
        showVitals = isVisible
        showAccounts = isVisible
        showQuickActions = isVisible
        showThisMonth = isVisible
        showDebts = isVisible
        showCommitments = isVisible
        showWeeklyBudget = isVisible
        showRecentActivity = isVisible
        showHeroCard = isVisible
    }

    private func toggleCard(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        isOn: Binding<Bool>
    ) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.headline)
                    .foregroundStyle(tint)
                    .frame(width: 40, height: 40)
                    .background(tint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .tint(tint)
        .padding(14)
        .background(AppTheme.elevatedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
