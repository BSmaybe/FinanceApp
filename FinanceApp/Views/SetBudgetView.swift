import SwiftUI
import SwiftData

struct SetBudgetView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let category: Category
    let month: Int
    let year: Int
    let existing: Budget?

    @State private var amountText: String = ""

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

    private var tint: Color {
        Color(hex: category.colorHex)
    }

    private var enteredAmount: Decimal? {
        Decimal(string: amountText.replacingOccurrences(of: ",", with: "."))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.canvas
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        HeroMetricCard(
                            title: category.name,
                            value: enteredAmount.map(CurrencyFormatter.string(from:)) ?? (existing.map { CurrencyFormatter.string(from: $0.limitAmount) } ?? "0"),
                            supportingTitle: String(localized: "Month"),
                            supportingValue: monthLabel,
                            note: String(localized: "Set a monthly limit for this category and keep it visible in your dashboard and analytics."),
                            badgeText: existing == nil ? String(localized: "New limit") : String(localized: "Editing limit")
                        )

                        SectionShell(
                            title: String(localized: "Budget limit"),
                            subtitle: String(localized: "This value becomes the monthly ceiling for the selected category.")
                        ) {
                            VStack(alignment: .leading, spacing: 14) {
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
                                        Text(monthLabel)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer(minLength: 8)
                                }

                                VStack(alignment: .leading, spacing: 8) {
                                    Text(String(localized: "Amount"))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)

                                    TextField(String(localized: "Amount"), text: $amountText)
                                        .font(.system(size: 28, weight: .bold, design: .rounded))
                                        .monospacedDigit()
                                        .financeNumericKeyboard()
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 14)
                                        .background(
                                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                .fill(AppTheme.elevatedSurface)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                        .stroke(AppTheme.outline.opacity(0.6), lineWidth: 1)
                                                )
                                        )
                                }

                                if let existing {
                                    InsightCard(
                                        title: String(localized: "Current limit"),
                                        value: CurrencyFormatter.string(from: existing.limitAmount),
                                        message: String(localized: "Update the amount if this category now needs more or less monthly room."),
                                        systemImage: "chart.bar.fill",
                                        tint: tint
                                    )
                                } else {
                                    InsightCard(
                                        title: String(localized: "No limit yet"),
                                        value: String(localized: "Add one clear ceiling"),
                                        message: String(localized: "A budget limit helps dashboard signals and monthly analytics stay meaningful."),
                                        systemImage: "plus.circle.fill",
                                        tint: tint
                                    )
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .keyboardDismissable()
            .financeNavigationSurface()
            .accessibilityIdentifier("setBudget.screen")
            .navigationTitle(String(localized: "Set Budget"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) {
                        save()
                    }
                    .disabled(enteredAmount == nil)
                }
            }
            .onAppear {
                if let existing {
                    amountText = (existing.limitAmount as NSDecimalNumber).stringValue
                }
            }
        }
    }

    private func save() {
        guard let value = enteredAmount else { return }
        if let existing {
            existing.limitAmount = value
        } else {
            let budget = Budget(categoryId: category.id, limitAmount: value, month: month, year: year)
            modelContext.insert(budget)
        }
        do { try modelContext.save() } catch { print("Budget save error: \(error)") }
        HapticManager.success()
        dismiss()
    }
}
