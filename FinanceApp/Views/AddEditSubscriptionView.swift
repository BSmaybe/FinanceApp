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
        if let subscription {
            _name = State(initialValue: subscription.name)
            _amountText = State(initialValue: (subscription.amount as NSDecimalNumber).stringValue)
            _frequency = State(initialValue: subscription.frequency)
            _selectedCategoryId = State(initialValue: subscription.categoryId)
            _nextBillingDate = State(initialValue: subscription.nextBillingDate)
            _note = State(initialValue: subscription.note)
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

    private var heroAmount: Decimal {
        amount > .zero ? amount : .zero
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.canvas.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        heroSection

                        SectionShell(
                            title: String(localized: "Details"),
                            subtitle: String(localized: "Set the name, price, and billing rhythm before reminders start.")
                        ) {
                            VStack(spacing: 12) {
                                formField(title: String(localized: "Name"), text: $name, prompt: String(localized: "Subscription name"))
                                amountField
                                frequencyPicker
                            }
                        }

                        SectionShell(
                            title: String(localized: "Category"),
                            subtitle: String(localized: "Use a category so recurring costs show up in the right budget bucket.")
                        ) {
                            if expenseCategories.isEmpty {
                                Text(String(localized: "No expense categories available."))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            } else {
                                Picker(String(localized: "Category"), selection: $selectedCategoryId) {
                                    Text(String(localized: "None")).tag(Optional<UUID>.none)
                                    ForEach(expenseCategories) { category in
                                        Text(category.name).tag(Optional(category.id))
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 14)
                                .background(AppTheme.elevatedSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                        }

                        SectionShell(
                            title: String(localized: "Billing"),
                            subtitle: String(localized: "Keep the next billing date accurate so due reminders and planning stay trustworthy.")
                        ) {
                            DatePicker(
                                String(localized: "Next Billing Date"),
                                selection: $nextBillingDate,
                                displayedComponents: .date
                            )
                            .datePickerStyle(.graphical)
                            .padding(8)
                            .background(AppTheme.elevatedSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }

                        SectionShell(
                            title: String(localized: "Notes"),
                            subtitle: String(localized: "Optional context for plan, provider, or renewal terms.")
                        ) {
                            formField(title: String(localized: "Notes"), text: $note, prompt: String(localized: "Optional note"))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .keyboardDismissable()
            .financeNavigationSurface()
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
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private var heroSection: some View {
        HeroMetricCard(
            title: existingSubscription == nil ? String(localized: "Add Subscription") : String(localized: "Edit Subscription"),
            value: CurrencyFormatter.string(from: heroAmount),
            supportingTitle: String(localized: "Frequency"),
            supportingValue: frequency.localizedName,
            note: nextBillingDate.formatted(date: .abbreviated, time: .omitted),
            badgeText: existingSubscription == nil ? nil : String(localized: "Recurring")
        )
    }

    private var amountField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Amount"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("0.00", text: $amountText)
                .financeNumericKeyboard()
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(AppTheme.elevatedSurface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var frequencyPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Frequency"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Picker(String(localized: "Frequency"), selection: $frequency) {
                ForEach(RecurringFrequency.allCases, id: \.self) { value in
                    Text(value.localizedName).tag(value)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func formField(title: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(prompt, text: text)
                .textInputAutocapitalization(.words)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(AppTheme.elevatedSurface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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

        let activeDescriptor = FetchDescriptor<Subscription>()
        if let allSubscriptions = try? modelContext.fetch(activeDescriptor) {
            let active = allSubscriptions.filter { $0.isActive }
            SubscriptionNotificationHelper.scheduleReminders(subscriptions: active)
        }

        dismiss()
    }
}
