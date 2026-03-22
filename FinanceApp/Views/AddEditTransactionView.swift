import SwiftUI
import SwiftData

@Observable @MainActor
final class AddEditTransactionViewModel {
    var type: TransactionType = .expense
    var amountText: String = ""
    var date: Date = Date()
    var selectedAccountId: UUID?
    var selectedToAccountId: UUID?
    var selectedCategoryId: UUID?
    var note: String = ""
    var tagsText: String = ""

    var amount: Decimal {
        Decimal(string: amountText.replacingOccurrences(of: ",", with: ".")) ?? .zero
    }

    var isValid: Bool {
        amount > 0 && selectedAccountId != nil &&
        (type != .transfer || (selectedToAccountId != nil && selectedAccountId != selectedToAccountId))
    }

    init(
        transaction: Transaction? = nil,
        prefillType: TransactionType? = nil,
        prefillAmount: Decimal? = nil,
        prefillDate: Date? = nil,
        prefillAccountId: UUID? = nil,
        prefillToAccountId: UUID? = nil,
        prefillCategoryId: UUID? = nil,
        prefillNote: String? = nil,
        prefillTagsText: String? = nil
    ) {
        guard let t = transaction else {
            type = prefillType ?? type
            if let prefillAmount, prefillAmount > 0 {
                amountText = NSDecimalNumber(decimal: prefillAmount).stringValue
            }
            date = prefillDate ?? date
            selectedAccountId = prefillAccountId
            selectedToAccountId = prefillToAccountId
            selectedCategoryId = prefillCategoryId
            note = prefillNote ?? note
            tagsText = prefillTagsText ?? tagsText
            return
        }

        type = t.type
        amountText = t.amountValue
        date = t.date
        selectedAccountId = t.accountId
        selectedToAccountId = t.toAccountId
        selectedCategoryId = t.categoryId
        note = t.note
        tagsText = t.tags.joined(separator: ", ")
    }

    var parsedTags: [String] {
        tagsText.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    func save(context: ModelContext, existing: Transaction?) {
        guard isValid, let accountId = selectedAccountId else { return }

        if let existing {
            existing.type = type
            existing.amount = amount
            existing.date = date
            existing.accountId = accountId
            existing.toAccountId = type == .transfer ? selectedToAccountId : nil
            existing.categoryId = type == .transfer ? nil : selectedCategoryId
            existing.note = note
            existing.tags = parsedTags
        } else {
            let txn = Transaction(
                date: date,
                amount: amount,
                type: type,
                accountId: accountId,
                toAccountId: type == .transfer ? selectedToAccountId : nil,
                categoryId: type == .transfer ? nil : selectedCategoryId,
                note: note,
                tags: parsedTags
            )
            context.insert(txn)
        }
        do {
            try context.save()
        } catch {
            print("Save error: \(error)")
        }
        if type == .expense {
            BudgetNotificationHelper.checkLimits(categoryId: selectedCategoryId, context: context)
        }
    }
}

struct AddEditTransactionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var accounts: [Account]
    @Query private var categories: [Category]
    @Query private var allTransactions: [Transaction]

    @State private var vm: AddEditTransactionViewModel
    @State private var categorySuggestion: Category? = nil
    @State private var suggestionDismissed = false
    @State private var showSuccessBurst = false

    let existingTransaction: Transaction?

    init(
        transaction: Transaction? = nil,
        prefillType: TransactionType? = nil,
        prefillAmount: Decimal? = nil,
        prefillDate: Date? = nil,
        prefillAccountId: UUID? = nil,
        prefillToAccountId: UUID? = nil,
        prefillCategoryId: UUID? = nil,
        prefillNote: String? = nil,
        prefillTagsText: String? = nil
    ) {
        self.existingTransaction = transaction
        self._vm = State(initialValue: AddEditTransactionViewModel(
            transaction: transaction,
            prefillType: prefillType,
            prefillAmount: prefillAmount,
            prefillDate: prefillDate,
            prefillAccountId: prefillAccountId,
            prefillToAccountId: prefillToAccountId,
            prefillCategoryId: prefillCategoryId,
            prefillNote: prefillNote,
            prefillTagsText: prefillTagsText
        ))
    }

    // Template init — pre-fills from an existing transaction but saves as new
    init(template: Transaction) {
        self.existingTransaction = nil
        let vm = AddEditTransactionViewModel(transaction: template)
        vm.date = Date()
        self._vm = State(initialValue: vm)
    }

    private var filteredCategories: [Category] {
        categories.filter { $0.type == (vm.type == .income ? .income : .expense) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
            Form {
                Section(String(localized: "Type")) {
                    Picker(String(localized: "Type"), selection: $vm.type) {
                        ForEach(TransactionType.allCases, id: \.self) { t in
                            Text(t.localizedName).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section(String(localized: "Amount")) {
                    Text(vm.amountText.isEmpty ? "0" : vm.amountText)
                        .font(.title2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(vm.amountText.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .accessibilityIdentifier("addEditTransaction.amountField")
                }

                Section(String(localized: "Date")) {
                    DatePicker(String(localized: "Date"), selection: $vm.date, displayedComponents: .date)
                }

                Section(String(localized: "Account")) {
                    if accounts.isEmpty {
                        Text(String(localized: "No accounts. Add one in Accounts tab."))
                            .foregroundStyle(.secondary)
                    } else {
                        Picker(String(localized: "From Account"), selection: $vm.selectedAccountId) {
                            Text(String(localized: "Select account")).tag(Optional<UUID>.none)
                            ForEach(accounts) { account in
                                Text(account.name).tag(Optional(account.id))
                            }
                        }
                    }
                }

                if vm.type == .transfer {
                    Section(String(localized: "To Account")) {
                        Picker(String(localized: "To Account"), selection: $vm.selectedToAccountId) {
                            Text(String(localized: "Select account")).tag(Optional<UUID>.none)
                            ForEach(accounts.filter { $0.id != vm.selectedAccountId }) { account in
                                Text(account.name).tag(Optional(account.id))
                            }
                        }
                    }
                }

                if vm.type != .transfer {
                    if let suggestion = categorySuggestion, !suggestionDismissed, vm.selectedCategoryId == nil {
                        Button {
                            vm.selectedCategoryId = suggestion.id
                            suggestionDismissed = true
                        } label: {
                            HStack(spacing: 6) {
                                Text(String(format: String(localized: "Suggested: %@"), suggestion.name))
                                    .font(.caption)
                                Spacer()
                                Text(String(localized: "Tap to apply"))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(AppTheme.primaryAccent.opacity(0.12))
                            .foregroundStyle(AppTheme.primaryAccent)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }

                    Section(String(localized: "Category")) {
                        if filteredCategories.isEmpty {
                            Text(String(localized: "No categories available."))
                                .foregroundStyle(.secondary)
                        } else {
                            Picker(String(localized: "Category"), selection: $vm.selectedCategoryId) {
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

                Section(String(localized: "Note")) {
                    TextField(String(localized: "Optional note"), text: $vm.note)
                }

                Section(String(localized: "Tags")) {
                    TextField(String(localized: "Add tags..."), text: $vm.tagsText)
                        .autocorrectionDisabled()
                }
            }
            .keyboardDismissable()
            .accessibilityIdentifier("addEditTransaction.screen")

            VStack(spacing: 0) {
                Divider()
                AmountNumpad(text: $vm.amountText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(AppTheme.canvas)
            }
            } // end outer VStack
            .navigationTitle(existingTransaction == nil ? String(localized: "Add Transaction") : String(localized: "Edit Transaction"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                        .accessibilityIdentifier("addEditTransaction.cancelButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) {
                        HapticManager.success()
                        showSuccessBurst = true
                        vm.save(context: modelContext, existing: existingTransaction)
                        dismiss()
                    }
                    .disabled(!vm.isValid)
                    .accessibilityIdentifier("addEditTransaction.saveButton")
                }
            }
            .onAppear {
                // Pre-select first account if none selected
                if vm.selectedAccountId == nil {
                    vm.selectedAccountId = accounts.first?.id
                }
            }
            .onChange(of: vm.note) { _, newValue in
                suggestionDismissed = false
                categorySuggestion = CategorySuggester.suggest(
                    for: newValue,
                    transactions: allTransactions,
                    categories: categories
                )
            }
            .onChange(of: vm.selectedCategoryId) {
                if vm.selectedCategoryId != nil {
                    suggestionDismissed = true
                }
            }
        }
        .accessibilityIdentifier("addEditTransaction.screen")
        .overlay(alignment: .center) { SuccessBurst(isShowing: $showSuccessBurst) }
    }

}
