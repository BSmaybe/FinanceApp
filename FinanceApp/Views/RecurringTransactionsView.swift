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
            ZStack {
                AppTheme.canvas.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        HeroMetricCard(
                            title: existingRecurring == nil ? String(localized: "Add Recurring") : String(localized: "Edit Recurring"),
                            value: amount > 0 ? CurrencyFormatter.string(from: amount) : String(localized: "Set amount"),
                            supportingTitle: String(localized: "Frequency"),
                            supportingValue: frequency.localizedName,
                            note: title.isEmpty ? String(localized: "Set a recurring title, amount, and routing before saving.") : title,
                            badgeText: type.localizedName
                        )

                        SectionShell(
                            title: String(localized: "Details"),
                            subtitle: String(localized: "Set the title, type, and amount before scheduling the recurring flow.")
                        ) {
                            VStack(spacing: 14) {
                                recurringField(title: String(localized: "Title"), text: $title, prompt: String(localized: "Title"))
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(String(localized: "Type"))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Picker(String(localized: "Type"), selection: $type) {
                                        ForEach(TransactionType.allCases, id: \.self) { transactionType in
                                            Text(transactionType.localizedName).tag(transactionType)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                    .onChange(of: type) { _, _ in
                                        selectedCategoryId = nil
                                    }
                                }
                                recurringAmountField
                            }
                        }

                        SectionShell(
                            title: String(localized: type == .transfer ? "Accounts" : "Account"),
                            subtitle: String(localized: type == .transfer
                                ? "Choose source and destination accounts for the transfer."
                                : "Choose the account where this recurring transaction belongs.")
                        ) {
                            VStack(spacing: 12) {
                                if accounts.isEmpty {
                                    Text(String(localized: "No accounts. Add one in Accounts tab."))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                } else {
                                    recurringMenu(
                                        title: String(localized: "Account"),
                                        value: accounts.first(where: { $0.id == selectedAccountId })?.name ?? String(localized: "Select account"),
                                        systemImage: "creditcard",
                                        tint: AppTheme.info
                                    ) {
                                        Button(String(localized: "Select account")) { selectedAccountId = nil }
                                        ForEach(accounts) { account in
                                            Button(account.name) { selectedAccountId = account.id }
                                        }
                                    }

                                    if type == .transfer {
                                        recurringMenu(
                                            title: String(localized: "To Account"),
                                            value: accounts.first(where: { $0.id == selectedToAccountId })?.name ?? String(localized: "Select account"),
                                            systemImage: "arrow.left.arrow.right",
                                            tint: AppTheme.primaryAccent
                                        ) {
                                            Button(String(localized: "Select account")) { selectedToAccountId = nil }
                                            ForEach(accounts.filter { $0.id != selectedAccountId }) { account in
                                                Button(account.name) { selectedToAccountId = account.id }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        if type != .transfer {
                            SectionShell(
                                title: String(localized: "Category"),
                                subtitle: String(localized: "Assign the recurring transaction so budgets and analytics stay consistent.")
                            ) {
                                if filteredCategories.isEmpty {
                                    Text(String(localized: "No categories available."))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                } else {
                                    recurringMenu(
                                        title: String(localized: "Category"),
                                        value: filteredCategories.first(where: { $0.id == selectedCategoryId })?.name ?? String(localized: "None"),
                                        systemImage: filteredCategories.first(where: { $0.id == selectedCategoryId })?.iconName ?? "tag",
                                        tint: filteredCategories.first(where: { $0.id == selectedCategoryId }).map { Color(hex: $0.colorHex) } ?? AppTheme.primaryAccent
                                    ) {
                                        Button(String(localized: "None")) { selectedCategoryId = nil }
                                        ForEach(filteredCategories) { category in
                                            Button(category.name) { selectedCategoryId = category.id }
                                        }
                                    }
                                }
                            }
                        }

                        SectionShell(
                            title: String(localized: "Schedule"),
                            subtitle: String(localized: "Frequency and start date determine when new transactions are generated.")
                        ) {
                            VStack(spacing: 14) {
                                recurringMenu(
                                    title: String(localized: "Frequency"),
                                    value: frequency.localizedName,
                                    systemImage: "calendar",
                                    tint: AppTheme.success
                                ) {
                                    ForEach(RecurringFrequency.allCases, id: \.self) { value in
                                        Button(value.localizedName) { frequency = value }
                                    }
                                }

                                DatePicker(String(localized: "Start Date"), selection: $startDate, displayedComponents: .date)
                                    .datePickerStyle(.compact)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 14)
                                    .background(AppTheme.elevatedSurface)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
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

    private var recurringAmountField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Amount"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("0.00", text: $amountText)
                .financeNumericKeyboard()
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(AppTheme.elevatedSurface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func recurringField(title: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(prompt, text: text)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(AppTheme.elevatedSurface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func recurringMenu<Content: View>(
        title: String,
        value: String,
        systemImage: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(tint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(value)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(AppTheme.elevatedSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
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
