import SwiftUI
import SwiftData

struct TransactionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query private var accounts: [Account]
    @Query private var categories: [Category]

    @State private var showingQuickAdd = false
    @State private var detailedDraft: QuickAddDetailedDraft?
    @State private var pendingDetailedDraft: QuickAddDetailedDraft?
    @State private var editingTransaction: Transaction?
    @State private var repeatingTransaction: Transaction?
    @State private var showingRecurring = false
    @State private var showingExport = false
    @State private var searchText = ""
    @State private var showingFilter = false

    @State private var filterAccountId: UUID? = nil
    @State private var filterType: TransactionType? = nil
    @State private var filterCategoryId: UUID? = nil

    @State private var transactionToDelete: Transaction?
    @State private var showingDeleteConfirmation = false

    // C3: skeleton on first load
    @State private var isFirstLoad = true

    private var accountById: [UUID: Account] {
        Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
    }

    private var categoryById: [UUID: Category] {
        Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
    }

    private var filtersActive: Bool {
        filterAccountId != nil || filterType != nil || filterCategoryId != nil
    }

    private var filteredTransactions: [Transaction] {
        transactions.filter { txn in
            if !searchText.isEmpty {
                let query = searchText.lowercased()
                let noteMatch = txn.note.lowercased().contains(query)
                let tagMatch = txn.tags.contains { $0.lowercased().contains(query) }
                let categoryMatch = categoryById[txn.categoryId ?? UUID()]?.name.lowercased().contains(query) ?? false
                if !noteMatch && !tagMatch && !categoryMatch { return false }
            }
            if let filterAccountId, txn.accountId != filterAccountId { return false }
            if let filterType, txn.type != filterType { return false }
            if let filterCategoryId, txn.categoryId != filterCategoryId { return false }
            return true
        }
    }

    private var groupedTransactions: [(Date, [Transaction])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredTransactions) { txn in
            calendar.startOfDay(for: txn.date)
        }
        return grouped.sorted { $0.key > $1.key }
    }

    private var summary: (income: Decimal, expense: Decimal, net: Decimal) {
        let income = filteredTransactions.filter { $0.type == .income }.reduce(Decimal.zero) { $0 + $1.amount }
        let expense = filteredTransactions.filter { $0.type == .expense }.reduce(Decimal.zero) { $0 + $1.amount }
        return (income, expense, income - expense)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                AppTheme.canvas
                    .ignoresSafeArea()

                VStack(spacing: 12) {
                    controlsHeader
                        .padding(.horizontal, 16)
                        .padding(.top, 12)

                    if isFirstLoad && transactions.isEmpty {
                        skeletonList
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if filteredTransactions.isEmpty {
                        emptyStateView
                            .accessibilityIdentifier("transactions.emptyState")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List {
                            ForEach(groupedTransactions, id: \.0) { date, txns in
                                Section {
                                    ForEach(Array(txns.enumerated()), id: \.element.id) { idx, txn in
                                        AnimatedTransactionRow(delay: Double(idx) * 0.04) {
                                            Button {
                                                editingTransaction = txn
                                            } label: {
                                                TransactionJournalRow(
                                                    transaction: txn,
                                                    account: accountById[txn.accountId],
                                                    category: categoryById[txn.categoryId ?? UUID()],
                                                    toAccount: txn.toAccountId.flatMap { accountById[$0] }
                                                )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        .accessibilityIdentifier("transactions.row.\(txn.id.uuidString)")
                                        .listRowBackground(Color.clear)
                                        .listRowSeparator(.hidden)
                                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                            Button {
                                                duplicateTransaction(txn)
                                            } label: {
                                                Label(String(localized: "Duplicate"), systemImage: "doc.on.doc")
                                            }
                                            .tint(AppTheme.info)
                                        }
                                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                            Button(role: .destructive) {
                                                transactionToDelete = txn
                                                showingDeleteConfirmation = true
                                            } label: {
                                                Label(String(localized: "Delete"), systemImage: "trash")
                                            }
                                        }
                                    }
                                } header: {
                                    journalDayHeader(date: date, transactions: txns)
                                }
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .accessibilityIdentifier("transactions.list")
                    }
                }

                Button {
                    showingQuickAdd = true
                } label: {
                    Image(systemName: "plus")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .frame(width: 58, height: 58)
                        .background(AppTheme.fabGradient)
                        .clipShape(Circle())
                        .shadow(color: AppTheme.shadowStrong, radius: 18, x: 0, y: 10)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Quick Add"))
                .accessibilityIdentifier("transactions.quickAddFab")
                .padding(.trailing, 20)
                .padding(.bottom, 12)
            }
            .navigationTitle(String(localized: "Transactions"))
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(AppTheme.surface, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showingRecurring = true
                        } label: {
                            Label(String(localized: "Recurring"), systemImage: "arrow.clockwise")
                        }

                        Button {
                            showingExport = true
                        } label: {
                            Label(String(localized: "Export"), systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(AppTheme.primaryAccent)
                    }
                }
            }
            .sheet(isPresented: $showingFilter) {
                FilterSheet(
                    accounts: accounts,
                    categories: categories,
                    filterAccountId: $filterAccountId,
                    filterType: $filterType,
                    filterCategoryId: $filterCategoryId
                )
            }
            .sheet(isPresented: $showingExport) {
                ExportView()
            }
            .sheet(isPresented: $showingRecurring) {
                NavigationStack {
                    RecurringTransactionsView()
                }
            }
            .sheet(isPresented: $showingQuickAdd, onDismiss: openPendingDetailedDraftIfNeeded) {
                QuickAddView { draft in
                    pendingDetailedDraft = draft
                    showingQuickAdd = false
                }
                .presentationDetents([.large])
            }
            .sheet(item: $detailedDraft) { draft in
                AddEditTransactionView(
                    prefillType: draft.type,
                    prefillAmount: draft.amount,
                    prefillDate: draft.date,
                    prefillAccountId: draft.accountId,
                    prefillCategoryId: draft.categoryId,
                    prefillNote: draft.note
                )
            }
            .sheet(item: $editingTransaction) { txn in
                AddEditTransactionView(transaction: txn)
            }
            .sheet(item: $repeatingTransaction) { txn in
                AddEditTransactionView(template: txn)
            }
            .onAppear {
                if isFirstLoad {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        withAnimation(.easeOut(duration: 0.3)) { isFirstLoad = false }
                    }
                }
            }
            .alert(
                String(localized: "Delete Transaction?"),
                isPresented: $showingDeleteConfirmation,
                presenting: transactionToDelete
            ) { txn in
                Button(String(localized: "Delete"), role: .destructive) {
                    modelContext.delete(txn)
                    transactionToDelete = nil
                }
                Button(String(localized: "Cancel"), role: .cancel) {
                    transactionToDelete = nil
                }
            } message: { _ in
                Text(String(localized: "This cannot be undone."))
            }
        }
    }

    private var controlsHeader: some View {
        VStack(spacing: 12) {
            transactionsOverviewHeader
            searchBar
            filterStrip
            summaryStrip
        }
    }

    private var transactionsOverviewHeader: some View {
        let total = filteredTransactions.count
        let subtitle = filtersActive || !searchText.isEmpty
            ? String(localized: "Search, filter and capture in one place.")
            : String(localized: "Your journal for fast review and clean capture.")

        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "Money Journal"))
                    .font(.system(.title3, design: .rounded).weight(.bold))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(total)")
                    .font(.headline.monospacedDigit().weight(.bold))
                    .foregroundStyle(.primary)
                Text(String(localized: "visible"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .cockpitSurface(cornerRadius: 22, elevated: true, compact: true)
    }

    // C3: Skeleton loading rows
    private var skeletonList: some View {
        List {
            ForEach(0..<5, id: \.self) { _ in
                skeletonTransactionRow
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .allowsHitTesting(false)
    }

    private var skeletonTransactionRow: some View {
        HStack(spacing: 12) {
            SkeletonView()
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                SkeletonView().frame(width: 140, height: 11).clipShape(Capsule())
                SkeletonView().frame(width: 90, height: 9).clipShape(Capsule())
            }
            Spacer()
            SkeletonView().frame(width: 68, height: 13).clipShape(Capsule())
        }
        .padding(.vertical, 6)
    }

    private var emptyStateView: some View {
        Group {
            if transactions.isEmpty {
                EmptyStateView(
                    icon: "arrow.left.arrow.right.circle.fill",
                    title: String(localized: "No Transactions"),
                    subtitle: String(localized: "Add your first income or expense to get started"),
                    actionTitle: String(localized: "Add Transaction"),
                    action: { showingQuickAdd = true }
                )
            } else {
                EmptyStateView(
                    icon: "line.3.horizontal.decrease.circle",
                    title: String(localized: "No results"),
                    subtitle: String(localized: "Adjust search or clear active filters to widen the journal."),
                    actionTitle: String(localized: "Clear Filters"),
                    action: { clearAllFilters() }
                )
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(String(localized: "Search transactions"), text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cockpitSurface(cornerRadius: 20, elevated: true, compact: true)
    }

    private var summaryStrip: some View {
        HStack(spacing: 12) {
            summaryTile(
                title: String(localized: "Income"),
                value: summary.income,
                tint: AppTheme.success,
                icon: "arrow.down.circle.fill"
            )
            summaryTile(
                title: String(localized: "Expense"),
                value: summary.expense,
                tint: AppTheme.danger,
                icon: "arrow.up.circle.fill"
            )
            summaryTile(
                title: String(localized: "Net"),
                value: summary.net,
                tint: summary.net >= 0 ? AppTheme.success : AppTheme.danger,
                icon: "equal.circle.fill"
            )
        }
    }

    private func summaryTile(title: String, value: Decimal, tint: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(CurrencyFormatter.string(from: value))
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cockpitSurface(cornerRadius: 18, elevated: true, compact: true)
    }

    private var filterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(
                    label: String(localized: "All"),
                    selected: filterType == nil,
                    tint: AppTheme.primaryAccent
                ) {
                    filterType = nil
                }
                ForEach(TransactionType.allCases, id: \.self) { type in
                    FilterChip(
                        label: type.localizedName,
                        selected: filterType == type,
                        tint: tint(for: type)
                    ) {
                        filterType = filterType == type ? nil : type
                    }
                }
                if let account = filterAccountId.flatMap({ accountById[$0] }) {
                    FilterChip(
                        label: account.name,
                        systemImage: "creditcard",
                        selected: true,
                        tint: AppTheme.info
                    ) {
                        filterAccountId = nil
                    }
                }
                if let category = filterCategoryId.flatMap({ categoryById[$0] }) {
                    FilterChip(
                        label: category.name,
                        systemImage: category.iconName,
                        selected: true,
                        tint: Color(hex: category.colorHex)
                    ) {
                        filterCategoryId = nil
                    }
                }
                FilterChip(
                    label: String(localized: "More Filters"),
                    systemImage: "line.3.horizontal.decrease.circle",
                    selected: filtersActive,
                    tint: AppTheme.primaryAccent
                ) {
                    showingFilter = true
                }
                if filtersActive || !searchText.isEmpty {
                    FilterChip(
                        label: String(localized: "Clear"),
                        systemImage: "xmark",
                        selected: false,
                        tint: AppTheme.warning
                    ) {
                        clearAllFilters()
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func tint(for type: TransactionType) -> Color {
        switch type {
        case .income:
            return AppTheme.success
        case .expense:
            return AppTheme.danger
        case .transfer:
            return AppTheme.info
        }
    }

    private func journalDayHeader(date: Date, transactions txns: [Transaction]) -> some View {
        let income = txns.filter { $0.type == .income }.reduce(Decimal.zero) { $0 + $1.amount }
        let expense = txns.filter { $0.type == .expense }.reduce(Decimal.zero) { $0 + $1.amount }
        let net = income - expense

        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(date, format: .dateTime.weekday(.wide).day().month(.abbreviated))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(String(format: String(localized: "%lld entries"), txns.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(CurrencyFormatter.string(from: net))
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(net >= 0 ? AppTheme.success : AppTheme.danger)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background((net >= 0 ? AppTheme.success : AppTheme.danger).opacity(0.12))
                .clipShape(Capsule())
        }
        .textCase(nil)
    }

    private func clearAllFilters() {
        searchText = ""
        filterAccountId = nil
        filterType = nil
        filterCategoryId = nil
    }

    private func openPendingDetailedDraftIfNeeded() {
        guard let pendingDetailedDraft else { return }
        self.pendingDetailedDraft = nil
        detailedDraft = pendingDetailedDraft
    }

    private func duplicateTransaction(_ txn: Transaction) {
        HapticManager.impact(.medium)
        let copy = Transaction(
            date: Date(),
            amount: txn.amount,
            type: txn.type,
            accountId: txn.accountId,
            toAccountId: txn.toAccountId,
            categoryId: txn.categoryId,
            note: txn.note,
            tags: txn.tags
        )
        modelContext.insert(copy)
        do {
            try modelContext.save()
#if canImport(ActivityKit)
            if #available(iOS 16.2, *), txn.type != .transfer {
                let detail = txn.note.trimmingCharacters(in: .whitespacesAndNewlines)
                let amountValue = NSDecimalNumber(decimal: txn.amount).doubleValue
                switch txn.type {
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
                    BudgetNotificationHelper.checkLimits(categoryId: txn.categoryId, context: modelContext)
                case .transfer:
                    break
                }
            }
#endif
        } catch {
            print("Duplicate transaction save error: \(error)")
        }
    }
}

private struct FilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    let accounts: [Account]
    let categories: [Category]

    @Binding var filterAccountId: UUID?
    @Binding var filterType: TransactionType?
    @Binding var filterCategoryId: UUID?

    @State private var draftAccountId: UUID?
    @State private var draftType: TransactionType?
    @State private var draftCategoryId: UUID?

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.canvas.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        HeroMetricCard(
                            title: String(localized: "Filter"),
                            value: "\(activeFilterCount)",
                            supportingTitle: String(localized: "Available Groups"),
                            supportingValue: "3",
                            note: String(localized: "Use only the filters you need, then jump back to the journal."),
                            badgeText: String(localized: "Active")
                        )

                        SectionShell(
                            title: String(localized: "Account"),
                            subtitle: String(localized: "Limit the journal to one account or keep all accounts visible.")
                        ) {
                            filterMenu(
                                title: String(localized: "Account"),
                                value: accounts.first(where: { $0.id == draftAccountId })?.name ?? String(localized: "All Accounts"),
                                systemImage: "creditcard",
                                tint: AppTheme.info
                            ) {
                                Button(String(localized: "All Accounts")) { draftAccountId = nil }
                                ForEach(accounts) { account in
                                    Button(account.name) { draftAccountId = account.id }
                                }
                            }
                        }

                        SectionShell(
                            title: String(localized: "Type"),
                            subtitle: String(localized: "Focus on income, expense, or transfers only when needed.")
                        ) {
                            filterMenu(
                                title: String(localized: "Type"),
                                value: draftType?.localizedName ?? String(localized: "All Types"),
                                systemImage: "arrow.up.arrow.down",
                                tint: AppTheme.primaryAccent
                            ) {
                                Button(String(localized: "All Types")) { draftType = nil }
                                ForEach(TransactionType.allCases, id: \.self) { type in
                                    Button(type.localizedName) { draftType = type }
                                }
                            }
                        }

                        SectionShell(
                            title: String(localized: "Category"),
                            subtitle: String(localized: "Filter the journal down to one category when reviewing spend.")
                        ) {
                            filterMenu(
                                title: String(localized: "Category"),
                                value: categories.first(where: { $0.id == draftCategoryId })?.name ?? String(localized: "All Categories"),
                                systemImage: "tag",
                                tint: AppTheme.success
                            ) {
                                Button(String(localized: "All Categories")) { draftCategoryId = nil }
                                ForEach(categories) { category in
                                    Button(category.name) { draftCategoryId = category.id }
                                }
                            }
                        }

                        Button(String(localized: "Clear Filters"), role: .destructive) {
                            draftAccountId = nil
                            draftType = nil
                            draftCategoryId = nil
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .financeNavigationSurface()
            .navigationTitle(String(localized: "Filter"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Apply")) {
                        filterAccountId = draftAccountId
                        filterType = draftType
                        filterCategoryId = draftCategoryId
                        dismiss()
                    }
                }
            }
            .onAppear {
                draftAccountId = filterAccountId
                draftType = filterType
                draftCategoryId = filterCategoryId
            }
        }
    }

    private var activeFilterCount: Int {
        [draftAccountId != nil, draftType != nil, draftCategoryId != nil]
            .filter { $0 }
            .count
    }

    private func filterMenu<Content: View>(
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
}

private struct TagChipsView: View {
    let tags: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption2)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(AppTheme.surfaceMuted)
                        .foregroundStyle(AppTheme.primaryAccent)
                        .clipShape(Capsule())
                }
            }
        }
    }
}

private struct TransactionJournalRow: View {
    let transaction: Transaction
    let account: Account?
    let category: Category?
    let toAccount: Account?

    private var amountColor: Color {
        switch transaction.type {
        case .income: return AppTheme.success
        case .expense: return AppTheme.danger
        case .transfer: return AppTheme.info
        }
    }

    private var amountPrefix: String {
        switch transaction.type {
        case .income: return "+"
        case .expense: return "-"
        case .transfer: return ""
        }
    }

    private var title: String {
        if !transaction.note.isEmpty { return transaction.note }
        if let category { return category.name }
        return transaction.type == .transfer ? String(localized: "Transfer") : String(localized: "Uncategorized")
    }

    private var subtitle: String {
        switch transaction.type {
        case .transfer:
            let from = account?.name ?? String(localized: "Unknown")
            let to = toAccount?.name ?? String(localized: "Unknown")
            return String(format: String(localized: "%@ → %@"), from, to)
        default:
            return account?.name ?? String(localized: "Unknown account")
        }
    }

    private var roleLabel: String {
        if let category {
            return category.name
        }
        switch transaction.type {
        case .income:
            return String(localized: "Income")
        case .expense:
            return String(localized: "Expense")
        case .transfer:
            return String(localized: "Transfer")
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if let category {
                    Image(systemName: category.iconName)
                        .foregroundStyle(Color(hex: category.colorHex))
                        .background(Color(hex: category.colorHex).opacity(0.15))
                } else {
                    Image(systemName: transaction.type == .transfer ? "arrow.left.arrow.right" : "questionmark")
                        .foregroundStyle(amountColor)
                        .background(amountColor.opacity(0.12))
                }
            }
            .font(.caption.weight(.semibold))
            .frame(width: 36, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 10) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 12)
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("\(amountPrefix)\(CurrencyFormatter.string(from: transaction.amount))")
                            .font(.headline.monospacedDigit().weight(.bold))
                            .foregroundStyle(amountColor)
                            .lineLimit(1)
                        Text(transaction.date.formatted(date: .omitted, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 6) {
                    Text(roleLabel)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(amountColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(amountColor.opacity(0.12))
                        .clipShape(Capsule())

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if !transaction.tags.isEmpty {
                    TagChipsView(tags: Array(transaction.tags.prefix(3)))
                }
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
}

private struct AnimatedTransactionRow<Content: View>: View {
    let delay: Double
    @ViewBuilder let content: () -> Content
    @State private var appeared = false

    var body: some View {
        content()
            .opacity(appeared ? 1 : 0)
            .offset(x: appeared ? 0 : -18)
            .onAppear {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82).delay(delay)) {
                    appeared = true
                }
            }
    }
}
