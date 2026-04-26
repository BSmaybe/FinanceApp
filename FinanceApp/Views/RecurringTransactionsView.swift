import SwiftUI
import SwiftData

struct RecurringTransactionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var recurrings: [RecurringTransaction]
    @Query private var accounts: [Account]
    @Query private var categories: [Category]

    @State private var showingAdd = false
    @State private var editingRecurring: RecurringTransaction? = nil

    private let summaryColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private var activeRecurrings: [RecurringTransaction] {
        recurrings
            .filter(\.isActive)
            .sorted { lhs, rhs in
                let leftDate = CommitmentsPlanner.nextOccurrence(for: lhs) ?? lhs.startDate
                let rightDate = CommitmentsPlanner.nextOccurrence(for: rhs) ?? rhs.startDate
                if leftDate != rightDate { return leftDate < rightDate }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    private var pausedRecurrings: [RecurringTransaction] {
        recurrings
            .filter { !$0.isActive }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private var monthlyExpenseLoad: Decimal {
        activeRecurrings
            .filter { $0.type == .expense }
            .reduce(Decimal.zero) { total, recurring in
                total + CommitmentsPlanner.monthlyEquivalent(amount: recurring.amount, frequency: recurring.frequency)
            }
    }

    private var monthlyIncomeLoad: Decimal {
        activeRecurrings
            .filter { $0.type == .income }
            .reduce(Decimal.zero) { total, recurring in
                total + CommitmentsPlanner.monthlyEquivalent(amount: recurring.amount, frequency: recurring.frequency)
            }
    }

    private var nextRunCount: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let inSevenDays = calendar.date(byAdding: .day, value: 7, to: today) ?? today

        return activeRecurrings.filter { recurring in
            guard let next = CommitmentsPlanner.nextOccurrence(for: recurring, referenceDate: today) else { return false }
            return next >= today && next <= inSevenDays
        }.count
    }

    private var statusBadge: String {
        if activeRecurrings.isEmpty {
            return String(localized: "No active obligations")
        }
        if nextRunCount > 0 {
            return String(format: String(localized: "%lld due soon"), Int64(nextRunCount))
        }
        return String(localized: "Payments in rhythm")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.canvas
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        heroSection

                        if recurrings.isEmpty {
                            emptyStateSection
                        } else {
                            overviewSection
                            activeSection

                            if !pausedRecurrings.isEmpty {
                                pausedSection
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
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
    }

    private var heroSection: some View {
        HeroMetricCard(
            title: String(localized: "Recurring Transactions"),
            value: CurrencyFormatter.string(from: monthlyExpenseLoad),
            supportingTitle: String(localized: "Planned inflow"),
            supportingValue: CurrencyFormatter.string(from: monthlyIncomeLoad),
            note: String(localized: "Automation rules for income, expenses and transfers in one operating view."),
            badgeText: statusBadge
        )
    }

    private var overviewSection: some View {
        LazyVGrid(columns: summaryColumns, spacing: 12) {
            CompactSummaryCard(
                title: String(localized: "Active"),
                value: "\(activeRecurrings.count)",
                detail: String(localized: "Rules currently generating transactions"),
                systemImage: "arrow.clockwise.circle.fill",
                tint: AppTheme.info
            )

            CompactSummaryCard(
                title: String(localized: "Due soon"),
                value: "\(nextRunCount)",
                detail: String(localized: "Next 7 days"),
                systemImage: "calendar.badge.clock",
                tint: AppTheme.warning
            )

            CompactSummaryCard(
                title: String(localized: "Expense"),
                value: CurrencyFormatter.string(from: monthlyExpenseLoad),
                detail: String(localized: "Monthly scheduled outflow"),
                systemImage: "arrow.up.circle.fill",
                tint: AppTheme.danger
            )

            CompactSummaryCard(
                title: String(localized: "Income"),
                value: CurrencyFormatter.string(from: monthlyIncomeLoad),
                detail: String(localized: "Monthly scheduled inflow"),
                systemImage: "arrow.down.circle.fill",
                tint: AppTheme.success
            )
        }
    }

    private var emptyStateSection: some View {
        SectionShell(
            title: String(localized: "Build your recurring rules"),
            subtitle: String(localized: "Keep salaries, bills and transfers running on a predictable schedule.")
        ) {
            VStack(spacing: 12) {
                InsightCard(
                    title: String(localized: "No recurring transactions yet"),
                    value: String(localized: "Add your first rule"),
                    message: String(localized: "Recurring transactions generate future entries for income, expenses or transfers without re-entering them each time."),
                    systemImage: "arrow.clockwise.circle",
                    tint: AppTheme.info
                )

                ActionTile(
                    title: String(localized: "Add Recurring"),
                    subtitle: String(localized: "Create a salary, bill, transfer, or other repeating rule."),
                    systemImage: "plus.circle.fill",
                    tint: AppTheme.info
                ) {
                    showingAdd = true
                }
            }
        }
    }

    private var activeSection: some View {
        SectionShell(
            title: String(localized: "Active rules"),
            subtitle: String(localized: "Review the next run, route and amount for each recurring rule.")
        ) {
            VStack(spacing: 12) {
                if activeRecurrings.isEmpty {
                    InsightCard(
                        title: String(localized: "No active rules"),
                        value: String(localized: "Nothing is scheduled"),
                        message: String(localized: "Paused recurring rules stay below until you reactivate them."),
                        systemImage: "pause.circle.fill",
                        tint: AppTheme.warning
                    )
                } else {
                    ForEach(activeRecurrings) { recurring in
                        recurringCard(recurring)
                    }
                }
            }
        }
    }

    private var pausedSection: some View {
        SectionShell(
            title: String(localized: "Paused rules"),
            subtitle: String(localized: "Keep inactive recurring rules for reuse instead of recreating them.")
        ) {
            VStack(spacing: 12) {
                ForEach(pausedRecurrings) { recurring in
                    recurringCard(recurring)
                }
            }
        }
    }

    private func recurringCard(_ recurring: RecurringTransaction) -> some View {
        let account = accounts.first { $0.id == recurring.accountId }
        let toAccount = recurring.toAccountId.flatMap { id in
            accounts.first { $0.id == id }
        }
        let category = categories.first { $0.id == recurring.categoryId }

        return Button {
            editingRecurring = recurring
        } label: {
            RecurringRuleCard(
                recurring: recurring,
                account: account,
                toAccount: toAccount,
                category: category,
                nextRun: CommitmentsPlanner.nextOccurrence(for: recurring),
                onToggleActive: { value in
                    setActive(recurring, isActive: value)
                }
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(String(localized: "Edit")) {
                editingRecurring = recurring
            }

            if recurring.isActive {
                Button(String(localized: "Pause")) {
                    setActive(recurring, isActive: false)
                }
            } else {
                Button(String(localized: "Activate")) {
                    setActive(recurring, isActive: true)
                }
            }

            Button(String(localized: "Delete"), role: .destructive) {
                delete(recurring)
            }
        }
    }

    private func setActive(_ recurring: RecurringTransaction, isActive: Bool) {
        recurring.isActive = isActive
        do {
            try modelContext.save()
        } catch {
            print("RecurringTransactions toggle error: \(error)")
        }
        HapticManager.impact(.light)
    }

    private func delete(_ recurring: RecurringTransaction) {
        HapticManager.impact(.medium)
        modelContext.delete(recurring)
        do {
            try modelContext.save()
        } catch {
            print("RecurringTransactions delete error: \(error)")
        }
    }
}

// MARK: - RecurringRuleCard

private struct RecurringRuleCard: View {
    let recurring: RecurringTransaction
    let account: Account?
    let toAccount: Account?
    let category: Category?
    let nextRun: Date?
    let onToggleActive: (Bool) -> Void

    private var amountColor: Color {
        switch recurring.type {
        case .income: return AppTheme.success
        case .expense: return AppTheme.danger
        case .transfer: return AppTheme.info
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: iconName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(amountColor)
                    .frame(width: 38, height: 38)
                    .background(amountColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(recurring.title.isEmpty ? recurring.type.localizedName : recurring.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    HStack(spacing: 4) {
                        Text(recurring.frequency.localizedName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(routeLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 10)

                Text(CurrencyFormatter.string(from: recurring.amount))
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(amountColor)
            }

            HStack(spacing: 8) {
                infoPill(
                    label: nextRun == nil
                        ? String(localized: "Start Date")
                        : String(localized: "Next run"),
                    value: (nextRun ?? recurring.startDate).formatted(date: .abbreviated, time: .omitted),
                    tint: AppTheme.warning
                )

                if let category, recurring.type != .transfer {
                    infoPill(
                        label: String(localized: "Category"),
                        value: category.name,
                        tint: Color(hex: category.colorHex)
                    )
                }

                Spacer(minLength: 0)

                Toggle(String(localized: "Active"), isOn: Binding(
                    get: { recurring.isActive },
                    set: onToggleActive
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .scaleEffect(0.86)
            }
        }
        .padding(14)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(AppTheme.outline.opacity(0.45), lineWidth: 0.5)
        )
    }

    private var iconName: String {
        switch recurring.type {
        case .income:
            return "arrow.down.circle.fill"
        case .expense:
            return "arrow.up.circle.fill"
        case .transfer:
            return "arrow.left.arrow.right.circle.fill"
        }
    }

    private var routeLabel: String {
        if recurring.type == .transfer {
            if let account, let toAccount {
                return "\(account.name) → \(toAccount.name)"
            }
            if let account {
                return account.name
            }
            return recurring.type.localizedName
        }
        return account?.name ?? recurring.type.localizedName
    }

    private func infoPill(label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(AppTheme.surfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
