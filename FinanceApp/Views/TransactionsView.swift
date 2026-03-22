import SwiftUI
import SwiftData

struct TransactionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query private var accounts: [Account]
    @Query private var categories: [Category]

    @State private var showingQuickAdd = false
    @State private var showingAdd = false
    @State private var editingTransaction: Transaction?
    @State private var repeatingTransaction: Transaction?
    @State private var showingRecurring = false
    @State private var showingExport = false
    @State private var searchText = ""
    @State private var showingFilter = false

    // Filter state
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
            // Search text
            if !searchText.isEmpty {
                let q = searchText.lowercased()
                let noteMatch = txn.note.lowercased().contains(q)
                let tagMatch = txn.tags.contains { $0.lowercased().contains(q) }
                let cat = categoryById[txn.categoryId ?? UUID()]
                let catMatch = cat?.name.lowercased().contains(q) ?? false
                if !noteMatch && !tagMatch && !catMatch { return false }
            }
            // Account filter
            if let aid = filterAccountId, txn.accountId != aid { return false }
            // Type filter
            if let type = filterType, txn.type != type { return false }
            // Category filter
            if let cid = filterCategoryId, txn.categoryId != cid { return false }
            return true
        }
    }

    private var groupedTransactions: [(Date, [Transaction])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredTransactions) { transaction in
            calendar.startOfDay(for: transaction.date)
        }
        return grouped.sorted { $0.key > $1.key }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                AppTheme.canvas
                    .ignoresSafeArea()

                if filteredTransactions.isEmpty {
                    ContentUnavailableView(
                        transactions.isEmpty ? "No Transactions" : String(localized: "No results"),
                        systemImage: "tray",
                        description: Text(transactions.isEmpty
                            ? "Tap + to add your first transaction."
                            : String(localized: "Try changing your search or filters."))
                    )
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("transactions.emptyState")
                } else {
                    List {
                        ForEach(groupedTransactions, id: \.0) { date, txns in
                            Section {
                                ForEach(Array(txns.enumerated()), id: \.element.id) { index, txn in
                                    Button {
                                        editingTransaction = txn
                                    } label: {
                                        TransactionRow(
                                            transaction: txn,
                                            account: accountById[txn.accountId],
                                            category: categoryById[txn.categoryId ?? UUID()],
                                            toAccount: txn.toAccountId.flatMap { accountById[$0] },
                                            isFirstInGroup: index == 0,
                                            isLastInGroup: index == txns.count - 1
                                        )
                                        .contentShape(Rectangle())
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
                                timelineDayHeader(date: date, transactions: txns)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .accessibilityIdentifier("transactions.list")
                }

                // FAB
                Button {
                    showingQuickAdd = true
                } label: {
                    Image(systemName: "plus")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .frame(width: 58, height: 58)
                        .background(AppTheme.fabGradient)
                        .clipShape(Circle())
                        .shadow(color: AppTheme.primaryAccent.opacity(0.28), radius: 12, x: 0, y: 8)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(localized: "Quick Add"))
                .accessibilityIdentifier("transactions.quickAddFab")
                .padding(.trailing, 20)
                .padding(.bottom, 12)
            }
            .accessibilityIdentifier("transactions.screen")
            .navigationTitle("Transactions")
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(AppTheme.surface, for: .navigationBar)
            .searchable(text: $searchText, prompt: String(localized: "Search transactions"))
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showingFilter = true
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                            if filtersActive {
                                Circle()
                                    .fill(AppTheme.primaryAccent)
                                    .frame(width: 8, height: 8)
                                    .offset(x: 4, y: -4)
                            }
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 16) {
                        Button {
                            showingQuickAdd = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                        .foregroundStyle(AppTheme.primaryAccent)
                        .accessibilityLabel(String(localized: "Quick Add"))
                        .accessibilityIdentifier("transactions.quickAddFab")

                        Button {
                            showingExport = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .foregroundStyle(AppTheme.primaryAccent)
                        Button {
                            showingRecurring = true
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
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
            .sheet(isPresented: $showingQuickAdd) {
                QuickAddView {
                    showingAdd = true
                }
                .presentationDetents([.large])
            }
            .sheet(isPresented: $showingAdd) {
                AddEditTransactionView()
            }
            .sheet(item: $editingTransaction) { txn in
                AddEditTransactionView(transaction: txn)
            }
            .sheet(item: $repeatingTransaction) { txn in
                AddEditTransactionView(template: txn)
            }
        }
    }

    private func timelineDayHeader(date: Date, transactions txns: [Transaction]) -> some View {
        let income = txns.filter { $0.type == .income }.reduce(Decimal.zero) { $0 + $1.amount }
        let expense = txns.filter { $0.type == .expense }.reduce(Decimal.zero) { $0 + $1.amount }
        let net = income - expense

        return HStack(alignment: .firstTextBaseline) {
            Text(date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer()
            Text(CurrencyFormatter.string(from: net))
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(net >= 0 ? Color.green : Color.red)
        }
        .textCase(nil)
    }

    private func deleteTxns(from txns: [Transaction], at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(txns[index])
        }
    }
}

// MARK: - Filter Sheet

private struct FilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    let accounts: [Account]
    let categories: [Category]

    @Binding var filterAccountId: UUID?
    @Binding var filterType: TransactionType?
    @Binding var filterCategoryId: UUID?

    // Local draft state so changes only apply on "Apply"
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
                        ForEach(TransactionType.allCases, id: \.self) { t in
                            Text(t.localizedName).tag(TransactionType?.some(t))
                        }
                    }
                }

                Section(String(localized: "Category")) {
                    Picker(String(localized: "Category"), selection: $draftCategoryId) {
                        Text(String(localized: "All Categories")).tag(UUID?.none)
                        ForEach(categories) { cat in
                            Text(cat.name).tag(UUID?.some(cat.id))
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

// MARK: - Supporting views

private struct TagChipsView: View {
    let tags: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppTheme.primaryAccent.opacity(0.14))
                        .foregroundStyle(AppTheme.primaryAccent)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.top, 2)
    }
}

private struct TransactionRow: View {
    let transaction: Transaction
    let account: Account?
    let category: Category?
    let toAccount: Account?
    let isFirstInGroup: Bool
    let isLastInGroup: Bool

    private var amountColor: Color {
        switch transaction.type {
        case .income: return .green
        case .expense: return .red
        case .transfer: return .secondary
        }
    }

    private var amountPrefix: String {
        switch transaction.type {
        case .income: return "+"
        case .expense: return "-"
        case .transfer: return ""
        }
    }

    private var subtitle: String {
        switch transaction.type {
        case .transfer:
            let from = account?.name ?? String(localized: "Unknown")
            let to = toAccount?.name ?? String(localized: "Unknown")
            return String(format: String(localized: "Transfer: %@ → %@"), from, to)
        default:
            return account?.name ?? String(localized: "Unknown account")
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(AppTheme.timelineLine)
                    .frame(width: 2, height: 10)
                    .opacity(isFirstInGroup ? 0 : 1)
                Circle()
                    .fill(transaction.type == .expense ? Color.red : (transaction.type == .income ? Color.green : AppTheme.timelineDot))
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle()
                            .stroke(AppTheme.surface, lineWidth: 2)
                    )
                Rectangle()
                    .fill(AppTheme.timelineLine)
                    .frame(width: 2, height: 44)
                    .opacity(isLastInGroup ? 0 : 1)
            }
            .frame(width: 12)

            HStack(spacing: 12) {
                if let cat = category {
                    Image(systemName: cat.iconName)
                        .font(.callout)
                        .foregroundStyle(Color(hex: cat.colorHex))
                        .frame(width: 34, height: 34)
                        .background(Color(hex: cat.colorHex).opacity(0.16))
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                } else {
                    Image(systemName: transaction.type == .transfer ? "arrow.left.arrow.right" : "questionmark")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(width: 34, height: 34)
                        .background(Color.gray.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(category?.name ?? (transaction.type == .transfer ? String(localized: "Transfer") : String(localized: "Uncategorized")))
                        .font(.body.weight(.medium))
                    if !transaction.note.isEmpty {
                        Text(transaction.note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !transaction.tags.isEmpty {
                        TagChipsView(tags: transaction.tags)
                    }
                }

                Spacer()

                Text("\(amountPrefix)\(CurrencyFormatter.string(from: transaction.amount))")
                    .font(.body.monospacedDigit().weight(.semibold))
                    .foregroundStyle(amountColor)
            }
            .padding(12)
            .background(AppTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(AppTheme.outline.opacity(0.45), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
}
