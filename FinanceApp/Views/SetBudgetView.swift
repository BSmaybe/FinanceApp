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

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Circle()
                            .fill(Color(hex: category.colorHex))
                            .frame(width: 12, height: 12)
                        Text(category.name)
                            .font(.headline)
                    }
                    Text(monthLabel)
                        .foregroundStyle(.secondary)
                }

                Section(String(localized: "Budget Limit")) {
                    TextField(String(localized: "Amount"), text: $amountText)
                        .keyboardType(.decimalPad)
                }
            }
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
                    .disabled(Decimal(string: amountText) == nil)
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
        guard let value = Decimal(string: amountText) else { return }
        if let existing {
            existing.limitAmount = value
        } else {
            let budget = Budget(categoryId: category.id, limitAmount: value, month: month, year: year)
            modelContext.insert(budget)
        }
        do { try modelContext.save() } catch { print("Budget save error: \(error)") }
        dismiss()
    }
}
