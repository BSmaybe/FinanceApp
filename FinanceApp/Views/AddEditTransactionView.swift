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
        guard let transaction else {
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

        type = transaction.type
        amountText = transaction.amountValue
        date = transaction.date
        selectedAccountId = transaction.accountId
        selectedToAccountId = transaction.toAccountId
        selectedCategoryId = transaction.categoryId
        note = transaction.note
        tagsText = transaction.tags.joined(separator: ", ")
    }

    var parsedTags: [String] {
        tagsText.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    func save(context: ModelContext, existing: Transaction?) {
        guard isValid, let accountId = selectedAccountId else { return }
        let isNewTransaction = existing == nil

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
            let transaction = Transaction(
                date: date,
                amount: amount,
                type: type,
                accountId: accountId,
                toAccountId: type == .transfer ? selectedToAccountId : nil,
                categoryId: type == .transfer ? nil : selectedCategoryId,
                note: note,
                tags: parsedTags
            )
            context.insert(transaction)
        }

        do {
            try context.save()
#if canImport(ActivityKit)
            if isNewTransaction, type != .transfer {
                let detail = note.trimmingCharacters(in: .whitespacesAndNewlines)
                let amountValue = NSDecimalNumber(decimal: amount).doubleValue
                if #available(iOS 16.2, *) {
                    switch type {
                    case .income:
                        LiveActivityManager.triggerCelebration(
                            .incomeAdded,
                            amount: amountValue,
                            detail: detail.isEmpty ? nil : detail
                        )
                    case .expense:
                        LiveActivityManager.triggerCelebration(
                            .expenseLogged,
                            amount: amountValue,
                            detail: detail.isEmpty ? nil : detail
                        )
                    case .transfer:
                        break
                    }
                }
            }
#endif
            if type == .expense {
                BudgetNotificationHelper.checkLimits(categoryId: selectedCategoryId, context: context)
            }
        } catch {
            print("Save error: \(error)")
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

    init(template: Transaction) {
        self.existingTransaction = nil
        let viewModel = AddEditTransactionViewModel(transaction: template)
        viewModel.date = Date()
        self._vm = State(initialValue: viewModel)
    }

    private var filteredCategories: [Category] {
        categories.filter { $0.type == (vm.type == .income ? .income : .expense) }
    }

    private var localDecimalSeparator: String {
        Locale.current.decimalSeparator ?? "."
    }

    private var displayAmount: String {
        guard !vm.amountText.isEmpty else { return "0" }
        let normalized = vm.amountText.replacingOccurrences(of: localDecimalSeparator, with: ".")
        guard let decimal = Decimal(string: normalized) else { return vm.amountText }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.locale = Locale.current
        return formatter.string(from: decimal as NSDecimalNumber) ?? vm.amountText
    }

    private var heroNote: String {
        var parts: [String] = []
        if let accountName = accountName(vm.selectedAccountId) {
            parts.append(accountName)
        }
        if vm.type == .transfer, let toAccountName = accountName(vm.selectedToAccountId) {
            parts.append(String(format: String(localized: "to %@"), toAccountName))
        } else if let categoryName = categoryName(vm.selectedCategoryId) {
            parts.append(categoryName)
        }
        return parts.isEmpty ? String(localized: "Set amount, account, and context before saving.") : parts.joined(separator: " • ")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.canvas.ignoresSafeArea()

                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 18) {
                            heroSection
                            detailsSection
                            accountSection
                            if vm.type != .transfer {
                                categorySection
                            }
                            contextSection
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
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
                }
            }
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
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("addEditTransaction.saveButton")
                }
            }
            .onAppear {
                if vm.selectedAccountId == nil {
                    vm.selectedAccountId = accounts.first?.id
                }
                if vm.type != .transfer, vm.selectedCategoryId == nil {
                    vm.selectedCategoryId = filteredCategories.first?.id
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
            .onChange(of: vm.type) { _, newType in
                if newType == .transfer {
                    vm.selectedCategoryId = nil
                } else if vm.selectedCategoryId == nil {
                    vm.selectedCategoryId = filteredCategories.first?.id
                }
            }
        }
        .financeNavigationSurface()
        .overlay(alignment: .center) { SuccessBurst(isShowing: $showSuccessBurst) }
        .modalEntrance()
    }

    private var heroSection: some View {
        HeroMetricCard(
            title: existingTransaction == nil ? String(localized: "Add Transaction") : String(localized: "Edit Transaction"),
            value: displayAmount,
            supportingTitle: String(localized: "Date"),
            supportingValue: vm.date.formatted(date: .abbreviated, time: .omitted),
            note: heroNote,
            badgeText: vm.type.localizedName
        )
    }

    private var detailsSection: some View {
        SectionShell(
            title: String(localized: "Details"),
            subtitle: String(localized: "Set the type and date before assigning the transaction.")
        ) {
            VStack(spacing: 14) {
                Picker(String(localized: "Type"), selection: $vm.type) {
                    ForEach(TransactionType.allCases, id: \.self) { value in
                        Text(value.localizedName).tag(value)
                    }
                }
                .pickerStyle(.segmented)

                DatePicker(
                    String(localized: "Date"),
                    selection: $vm.date,
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(AppTheme.elevatedSurface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private var accountSection: some View {
        SectionShell(
            title: String(localized: vm.type == .transfer ? "Accounts" : "Account"),
            subtitle: String(localized: vm.type == .transfer
                ? "Choose the source and destination accounts for the transfer."
                : "Choose where the transaction should be booked.")
        ) {
            VStack(spacing: 12) {
                if accounts.isEmpty {
                    Text(String(localized: "No accounts. Add one in Accounts tab."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    selectionMenu(
                        title: String(localized: "From Account"),
                        value: accountName(vm.selectedAccountId) ?? String(localized: "Select account"),
                        systemImage: "creditcard",
                        tint: AppTheme.info
                    ) {
                        Button(String(localized: "Select account")) { vm.selectedAccountId = nil }
                        ForEach(accounts) { account in
                            Button(account.name) { vm.selectedAccountId = account.id }
                        }
                    }

                    if vm.type == .transfer {
                        selectionMenu(
                            title: String(localized: "To Account"),
                            value: accountName(vm.selectedToAccountId) ?? String(localized: "Select account"),
                            systemImage: "arrow.left.arrow.right",
                            tint: AppTheme.primaryAccent
                        ) {
                            Button(String(localized: "Select account")) { vm.selectedToAccountId = nil }
                            ForEach(accounts.filter { $0.id != vm.selectedAccountId }) { account in
                                Button(account.name) { vm.selectedToAccountId = account.id }
                            }
                        }
                    }
                }
            }
        }
    }

    private var categorySection: some View {
        SectionShell(
            title: String(localized: "Category"),
            subtitle: String(localized: "Assign the transaction so budgets and analytics stay accurate.")
        ) {
            VStack(spacing: 12) {
                if let suggestion = categorySuggestion, !suggestionDismissed, vm.selectedCategoryId == nil {
                    Button {
                        vm.selectedCategoryId = suggestion.id
                        suggestionDismissed = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: suggestion.iconName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color(hex: suggestion.colorHex))
                                .frame(width: 28, height: 28)
                                .background(Color(hex: suggestion.colorHex).opacity(0.14))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(String(format: String(localized: "Suggested: %@"), suggestion.name))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(String(localized: "Tap to apply"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .background(AppTheme.primaryAccent.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                if filteredCategories.isEmpty {
                    Text(String(localized: "No categories available."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    selectionMenu(
                        title: String(localized: "Category"),
                        value: categoryName(vm.selectedCategoryId) ?? String(localized: "None"),
                        systemImage: categorySystemImage(vm.selectedCategoryId),
                        tint: categoryTint(vm.selectedCategoryId)
                    ) {
                        Button(String(localized: "None")) { vm.selectedCategoryId = nil }
                        ForEach(filteredCategories) { category in
                            Button(category.name) { vm.selectedCategoryId = category.id }
                        }
                    }
                }
            }
        }
    }

    private var contextSection: some View {
        SectionShell(
            title: String(localized: "Context"),
            subtitle: String(localized: "Keep notes and tags short so search and suggestions remain useful.")
        ) {
            VStack(spacing: 12) {
                textField(
                    title: String(localized: "Note"),
                    text: $vm.note,
                    prompt: String(localized: "Optional note")
                )

                textField(
                    title: String(localized: "Tags"),
                    text: $vm.tagsText,
                    prompt: String(localized: "Add tags...")
                )
                .autocorrectionDisabled()
            }
        }
    }

    private func textField(title: String, text: Binding<String>, prompt: String) -> some View {
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

    private func selectionMenu<Content: View>(
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

    private func accountName(_ id: UUID?) -> String? {
        guard let id, let account = accounts.first(where: { $0.id == id }) else { return nil }
        return account.name
    }

    private func categoryName(_ id: UUID?) -> String? {
        guard let id, let category = categories.first(where: { $0.id == id }) else { return nil }
        return category.name
    }

    private func categorySystemImage(_ id: UUID?) -> String {
        guard let id, let category = categories.first(where: { $0.id == id }) else { return "tag" }
        return category.iconName
    }

    private func categoryTint(_ id: UUID?) -> Color {
        guard let id, let category = categories.first(where: { $0.id == id }) else { return AppTheme.primaryAccent }
        return Color(hex: category.colorHex)
    }
}
