import SwiftUI
import SwiftData

struct AddEditSubscriptionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var categories: [Category]

    let existingSubscription: Subscription?

    @State private var name: String
    @State private var amountText: String
    @State private var frequency: RecurringFrequency
    @State private var selectedCategoryId: UUID?
    @State private var nextBillingDate: Date
    @State private var note: String

    init(subscription: Subscription? = nil) {
        self.existingSubscription = subscription
        if let s = subscription {
            _name = State(initialValue: s.name)
            _amountText = State(initialValue: (s.amount as NSDecimalNumber).stringValue)
            _frequency = State(initialValue: s.frequency)
            _selectedCategoryId = State(initialValue: s.categoryId)
            _nextBillingDate = State(initialValue: s.nextBillingDate)
            _note = State(initialValue: s.note)
        } else {
            _name = State(initialValue: "")
            _amountText = State(initialValue: "")
            _frequency = State(initialValue: .monthly)
            _selectedCategoryId = State(initialValue: nil)
            _nextBillingDate = State(initialValue: Date())
            _note = State(initialValue: "")
        }
    }

    private var expenseCategories: [Category] {
        categories.filter { $0.type == .expense }
    }

    private var amount: Decimal {
        Decimal(string: amountText.replacingOccurrences(of: ",", with: ".")) ?? .zero
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && amount > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "Name")) {
                    TextField(String(localized: "Subscription name"), text: $name)
                }

                Section(String(localized: "Amount")) {
                    TextField("0.00", text: $amountText)
                        .financeNumericKeyboard()
                }

                Section(String(localized: "Frequency")) {
                    Picker(String(localized: "Frequency"), selection: $frequency) {
                        ForEach(RecurringFrequency.allCases, id: \.self) { f in
                            Text(f.localizedName).tag(f)
                        }
                    }
                }

                Section(String(localized: "Category")) {
                    if expenseCategories.isEmpty {
                        Text(String(localized: "No expense categories available."))
                            .foregroundStyle(.secondary)
                    } else {
                        Picker(String(localized: "Category"), selection: $selectedCategoryId) {
                            Text(String(localized: "None")).tag(Optional<UUID>.none)
                            ForEach(expenseCategories) { cat in
                                HStack {
                                    Circle()
                                        .fill(Color(hex: cat.colorHex))
                                        .frame(width: 10, height: 10)
                                    Text(cat.name)
                                }
                                .tag(Optional(cat.id))
                            }
                        }
                    }
                }

                Section(String(localized: "Next Billing Date")) {
                    DatePicker(String(localized: "Next Billing Date"), selection: $nextBillingDate, displayedComponents: .date)
                }

                Section(String(localized: "Notes")) {
                    TextField(String(localized: "Notes"), text: $note)
                }
            }
            .keyboardDismissable()
            .navigationTitle(existingSubscription == nil ? String(localized: "Add Subscription") : String(localized: "Edit Subscription"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) {
                        save()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        if let existing = existingSubscription {
            existing.name = trimmedName
            existing.amount = amount
            existing.frequency = frequency
            existing.categoryId = selectedCategoryId
            existing.nextBillingDate = nextBillingDate
            existing.note = note
        } else {
            let subscription = Subscription(
                name: trimmedName,
                amount: amount,
                frequency: frequency,
                categoryId: selectedCategoryId,
                nextBillingDate: nextBillingDate,
                note: note
            )
            modelContext.insert(subscription)
        }
        do { try modelContext.save() } catch { print("Subscription save error: \(error)") }
        HapticManager.success()

        // Re-schedule subscription reminders
        let activeDescriptor = FetchDescriptor<Subscription>()
        if let allSubs = try? modelContext.fetch(activeDescriptor) {
            let active = allSubs.filter { $0.isActive }
            SubscriptionNotificationHelper.scheduleReminders(subscriptions: active)
        }

        dismiss()
    }
}
