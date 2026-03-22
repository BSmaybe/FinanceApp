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

                    if filteredTransactions.isEmpty {
                        ContentUnavailableView(
                            transactions.isEmpty ? String(localized: "No Transactions") : String(localized: "No results"),
                            systemImage: "tray",
                            description: Text(transactions.isEmpty
                                ? String(localized: "Tap + to add your first transaction.")
                                : String(localized: "Try changing your search or filters."))
                        )
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("transactions.emptyState")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List {
                            ForEach(groupedTransactions, id: \.0) { date, txns in
                                Section {
                                    ForEach(Array(txns.enumerated()), id: \.element.id) { _, txn in
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
                                        .accessibilityIdentifier("transactions.row.\(txn.id.uuidString)")
                                        .listRowBackground(Color.clear)
                                        .listRowSeparator(.hidden)
                                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                        .swipeActions(edge: .leading) {
                                            Button {
                                                repeatingTransaction = txn
                                            } label: {
                                                Label(String(localized: "Repeat"), systemImage: "doc.on.doc")
                                            }
                                            .tint(AppTheme.primaryAccent)
                                        }
                                    }
                                    .onDelete { offsets in
                                        deleteTxns(from: txns, at: offsets)
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
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        showingRecurring = true
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .foregroundStyle(AppTheme.primaryAccent)

                    Button {
                        showingExport = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .foregroundStyle(AppTheme.primaryAccent)
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
        }
    }

    private var controlsHeader: some View {
        VStack(spacing: 12) {
            searchBar
            summaryStrip
            filterStrip
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

    private func deleteTxns(from txns: [Transaction], at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(txns[index])
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
            Form {
                Section(String(localized: "Account")) {
                    Picker(String(localized: "Account"), selection: $draftAccountId) {
                        Text(String(localized: "All Accounts")).tag(UUID?.none)
                        ForEach(accounts) { acc in
                            Text(acc.name).tag(UUID?.some(acc.id))
                        }
                    }
                }

                Section(String(localized: "Type")) {
                    Picker(String(localized: "Type"), selection: $draftType) {
                        Text(String(localized: "All Types")).tag(TransactionType?.none)
                        ForEach(TransactionType.allCases, id: \.self) { type in
                            Text(type.localizedName).tag(TransactionType?.some(type))
                        }
                    }
                }

                Section(String(localized: "Category")) {
                    Picker(String(localized: "Category"), selection: $draftCategoryId) {
                        Text(String(localized: "All Categories")).tag(UUID?.none)
                        ForEach(categories) { category in
                            Text(category.name).tag(UUID?.some(category.id))
                        }
                    }
                }

                Section {
                    Button(String(localized: "Clear Filters"), role: .destructive) {
                        draftAccountId = nil
                        draftType = nil
                        draftCategoryId = nil
                    }
                }
            }
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
}

private struct TagChipsView: View {
    let tags: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
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

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 12)
                    Text("\(amountPrefix)\(CurrencyFormatter.string(from: transaction.amount))")
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(amountColor)
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(transaction.date.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if !transaction.tags.isEmpty {
                    TagChipsView(tags: transaction.tags)
                }
            }
        }
        .cockpitSurface(cornerRadius: 20, elevated: true, compact: true)
    }
}
