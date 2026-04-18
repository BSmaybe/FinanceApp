import SwiftUI
import SwiftData

struct BudgetManagerView: View {
    let month: Int
    let year: Int

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Category.name) private var categories: [Category]
    @Query private var budgets: [Budget]

    @State private var settingBudgetForCategory: Category?

    private var expenseCategories: [Category] {
        categories.filter { $0.type == .expense }
    }

    private var monthLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        let date = Calendar.current.date(from: comps) ?? Date()
        return formatter.string(from: date)
    }

    private var configuredBudgetCount: Int {
        expenseCategories.filter { budget(for: $0) != nil }.count
    }

    private var unconfiguredBudgetCount: Int {
        max(expenseCategories.count - configuredBudgetCount, 0)
    }

    private var coverageLabel: String {
        guard !expenseCategories.isEmpty else { return "0%" }
        let ratio = Double(configuredBudgetCount) / Double(expenseCategories.count)
        return "\(Int((ratio * 100).rounded()))%"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.canvas
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        HeroMetricCard(
                            title: String(localized: "Budget setup"),
                            value: "\(configuredBudgetCount)",
                            supportingTitle: String(localized: "Month"),
                            supportingValue: monthLabel,
                            note: String(localized: "Monthly limits across your expense categories."),
                            badgeText: configuredBudgetCountLabel
                        )

                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12)
                            ],
                            spacing: 12
                        ) {
                            CompactSummaryCard(
                                title: String(localized: "Ready"),
                                value: "\(configuredBudgetCount)",
                                detail: String(localized: "Categories with limits"),
                                systemImage: "checkmark.seal.fill",
                                tint: AppTheme.success
                            )

                            CompactSummaryCard(
                                title: String(localized: "Open"),
                                value: "\(unconfiguredBudgetCount)",
                                detail: String(localized: "Still missing a limit"),
                                systemImage: "clock.badge.exclamationmark.fill",
                                tint: AppTheme.warning
                            )

                            CompactSummaryCard(
                                title: String(localized: "Coverage"),
                                value: coverageLabel,
                                detail: String(localized: "Current budget setup progress"),
                                systemImage: "chart.bar.fill",
                                tint: AppTheme.info
                            )

                            CompactSummaryCard(
                                title: String(localized: "Categories"),
                                value: "\(expenseCategories.count)",
                                detail: String(localized: "Expense groups available"),
                                systemImage: "square.grid.2x2.fill",
                                tint: AppTheme.primaryAccent
                            )
                        }

                        SectionShell(
                            title: String(localized: "Budget categories"),
                            subtitle: String(localized: "Choose a category and set the monthly limit you want to hold.")
                        ) {
                            if expenseCategories.isEmpty {
                                InsightCard(
                                    title: String(localized: "No expense categories"),
                                    value: String(localized: "Setup needed"),
                                    message: String(localized: "Create expense categories first, then assign budget limits here."),
                                    systemImage: "tray.fill",
                                    tint: AppTheme.info
                                )
                            } else {
                                VStack(spacing: 10) {
                                    ForEach(expenseCategories) { category in
                                        budgetCategoryRow(for: category)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle(String(localized: "Budgets"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Done")) {
                        dismiss()
                    }
                }
            }
            .sheet(item: $settingBudgetForCategory) { category in
                SetBudgetView(
                    category: category,
                    month: month,
                    year: year,
                    existing: budget(for: category)
                )
            }
            .accessibilityIdentifier("budgetManager.screen")
        }
    }

    private var configuredBudgetCountLabel: String {
        String(format: String(localized: "%lld set"), configuredBudgetCount)
    }

    private func budget(for category: Category) -> Budget? {
        budgets.first {
            $0.categoryId == category.id &&
            $0.month == month &&
            $0.year == year
        }
    }

    private func budgetCategoryRow(for category: Category) -> some View {
        let existingBudget = budget(for: category)
        let tint = Color(hex: category.colorHex)

        return Button {
            settingBudgetForCategory = category
        } label: {
            HStack(spacing: 12) {
                Image(systemName: category.iconName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(category.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(
                        existingBudget.map {
                            String(format: String(localized: "Limit %@"), CurrencyFormatter.string(from: $0.limitAmount))
                        } ?? String(localized: "No monthly limit yet")
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Text(existingBudget == nil ? String(localized: "Set") : String(localized: "Edit"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(tint.opacity(0.12))
                    .clipShape(Capsule())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cockpitSurface(cornerRadius: 20, elevated: true, compact: true)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("budgetManager.category.\(category.id.uuidString)")
    }
}
