import SwiftUI
import SwiftData

struct RecurringTransactionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var recurrings: [RecurringTransaction]
    @Query private var accounts: [Account]
    @Query private var categories: [Category]

    @State private var showingAdd = false
    @State private var editingRecurring: RecurringTransaction? = nil

    var body: some View {
        List {
            if recurrings.isEmpty {
                ContentUnavailableView(
                    String(localized: "Recurring Transactions"),
                    systemImage: "arrow.clockwise",
                    description: Text(String(localized: "Tap + to add your first transaction."))
                )
            } else {
                ForEach(recurrings) { recurring in
                    RecurringRow(
                        recurring: recurring,
                        account: accounts.first { $0.id == recurring.accountId },
                        category: categories.first { $0.id == recurring.categoryId }
                    )
                    .contextMenu {
                        Button("Edit") { editingRecurring = recurring }
                    }
                }
                .onDelete(perform: delete)
            }
        }
        .listStyle(.plain)
        .financeNavigationSurface()
        .navigationTitle(String(localized: "Recurring Transactions"))
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
            AddEditRecurringTransactionView()
        }
        .sheet(item: $editingRecurring) { item in
            AddEditRecurringTransactionView(recurring: item)
        }
    }

    private func delete(at offsets: IndexSet) {
        HapticManager.impact(.medium)
        for index in offsets {
            modelContext.delete(recurrings[index])
        }
        do {
            try modelContext.save()
        } catch {
            print("RecurringTransactions delete error: \(error)")
        }
    }
}

// MARK: - RecurringRow

private struct RecurringRow: View {
    @Bindable var recurring: RecurringTransaction
    let account: Account?
    let category: Category?

    private var amountColor: Color {
        switch recurring.type {
        case .income: return .green
        case .expense: return .red
        case .transfer: return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(recurring.title.isEmpty ? recurring.type.localizedName : recurring.title)
                    .font(.body)
                HStack(spacing: 4) {
                    Text(recurring.frequency.localizedName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let account {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(account.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(CurrencyFormatter.string(from: recurring.amount))
                    .font(.body.monospacedDigit())
                    .foregroundStyle(amountColor)
                Toggle(String(localized: "Active"), isOn: $recurring.isActive)
                    .labelsHidden()
                    .scaleEffect(0.75)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - AddEditRecurringTransactionView

struct AddEditRecurringTransactionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var accounts: [Account]
    @Query private var categories: [Category]

    let existingRecurring: RecurringTransaction?

    @State private var title: String
    @State private var type: TransactionType
    @State private var amountText: String
    @State private var selectedAccountId: UUID?
    @State private var selectedToAccountId: UUID?
    @State private var selectedCategoryId: UUID?
    @State private var frequency: RecurringFrequency
    @State private var startDate: Date

    init(recurring: RecurringTransaction? = nil) {
        self.existingRecurring = recurring
        if let r = recurring {
            _title = State(initialValue: r.title)
            _type = State(initialValue: r.type)
            _amountText = State(initialValue: (r.amount as NSDecimalNumber).stringValue)
            _selectedAccountId = State(initialValue: r.accountId)
            _selectedToAccountId = State(initialValue: r.toAccountId)
            _selectedCategoryId = State(initialValue: r.categoryId)
            _frequency = State(initialValue: r.frequency)
            _startDate = State(initialValue: r.startDate)
        } else {
            _title = State(initialValue: "")
            _type = State(initialValue: .expense)
            _amountText = State(initialValue: "")
            _selectedAccountId = State(initialValue: nil)
            _selectedToAccountId = State(initialValue: nil)
            _selectedCategoryId = State(initialValue: nil)
            _frequency = State(initialValue: .monthly)
            _startDate = State(initialValue: Date())
        }
    }

    private var filteredCategories: [Category] {
        categories.filter { $0.type == (type == .income ? .income : .expense) }
    }

    private var amount: Decimal {
        Decimal(string: amountText.replacingOccurrences(of: ",", with: ".")) ?? .zero
    }

    private var isValid: Bool {
        amount > 0 && selectedAccountId != nil &&
        (type != .transfer || (selectedToAccountId != nil && selectedAccountId != selectedToAccountId))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "Title")) {
                    TextField(String(localized: "Title"), text: $title)
                }

                Section(String(localized: "Type")) {
                    Picker(String(localized: "Type"), selection: $type) {
                        ForEach(TransactionType.allCases, id: \.self) { t in
                            Text(t.localizedName).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: type) { _, _ in
                        selectedCategoryId = nil
                    }
                }

                Section(String(localized: "Amount")) {
                    TextField("0.00", text: $amountText)
                        .financeNumericKeyboard()
                }

                Section(String(localized: "Account")) {
                    if accounts.isEmpty {
                        Text(String(localized: "No accounts. Add one in Accounts tab."))
                            .foregroundStyle(.secondary)
                    } else {
                        Picker(String(localized: "Account"), selection: $selectedAccountId) {
                            Text(String(localized: "Select account")).tag(Optional<UUID>.none)
                            ForEach(accounts) { account in
                                Text(account.name).tag(Optional(account.id))
                            }
                        }
                    }
                }

                if type == .transfer {
                    Section(String(localized: "To Account")) {
                        Picker(String(localized: "To Account"), selection: $selectedToAccountId) {
                            Text(String(localized: "Select account")).tag(Optional<UUID>.none)
                            ForEach(accounts.filter { $0.id != selectedAccountId }) { account in
                                Text(account.name).tag(Optional(account.id))
                            }
                        }
                    }
                }

                if type != .transfer {
                    Section(String(localized: "Category")) {
                        if filteredCategories.isEmpty {
                            Text(String(localized: "No categories available."))
                                .foregroundStyle(.secondary)
                        } else {
                            Picker(String(localized: "Category"), selection: $selectedCategoryId) {
                                Text(String(localized: "None")).tag(Optional<UUID>.none)
                                ForEach(filteredCategories) { cat in
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
                }

                Section(String(localized: "Frequency")) {
                    Picker(String(localized: "Frequency"), selection: $frequency) {
                        ForEach(RecurringFrequency.allCases, id: \.self) { f in
                            Text(f.localizedName).tag(f)
                        }
                    }
                }

                Section(String(localized: "Start Date")) {
                    DatePicker(String(localized: "Start Date"), selection: $startDate, displayedComponents: .date)
                }
            }
            .keyboardDismissable()
            .financeNavigationSurface()
            .navigationTitle(existingRecurring == nil ? String(localized: "Add Recurring") : String(localized: "Edit Recurring"))
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
            .onAppear {
                if selectedAccountId == nil {
                    selectedAccountId = accounts.first?.id
                }
            }
        }
    }

    private func save() {
        guard let accountId = selectedAccountId else { return }
        if let existing = existingRecurring {
            existing.title = title
            existing.amount = amount
            existing.type = type
            existing.accountId = accountId
            existing.toAccountId = type == .transfer ? selectedToAccountId : nil
            existing.categoryId = type == .transfer ? nil : selectedCategoryId
            existing.frequency = frequency
            existing.startDate = startDate
        } else {
            let recurring = RecurringTransaction(
                title: title,
                amount: amount,
                type: type,
                accountId: accountId,
                toAccountId: type == .transfer ? selectedToAccountId : nil,
                categoryId: type == .transfer ? nil : selectedCategoryId,
                frequency: frequency,
                startDate: startDate
            )
            modelContext.insert(recurring)
        }
        do { try modelContext.save() } catch { print("Save error: \(error)") }
        HapticManager.success()
        RecurringTransactionProcessor.process(context: modelContext)
        dismiss()
    }
}
