import SwiftUI
import SwiftData
import Charts

// MARK: - Private Models

private enum CashFlowPeriod: String, CaseIterable {
    case month, year

    var label: String {
        switch self {
        case .month: return String(localized: "Month")
        case .year:  return String(localized: "Year")
        }
    }
}

private struct CashFlowSlice: Identifiable {
    let id = UUID()
    let label: String
    let amount: Decimal
    let color: Color
}

private struct MonthPoint: Identifiable {
    let id = UUID()
    let date: Date
    let income: Double
    let expense: Double
    let transfer: Double
}

private struct ChartSeriesPoint: Identifiable {
    let id = UUID()
    let date: Date
    let amount: Double
    let series: String
}

private extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        let comps = dateComponents([.year, .month], from: date)
        return self.date(from: comps) ?? date
    }
}

// MARK: - TransactionsView

struct TransactionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query private var accounts: [Account]
    @Query private var categories: [Category]

    // History list state
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
    @State private var isFirstLoad = true

    // Cash Flows state
    @State private var cashFlowPeriod: CashFlowPeriod = .month
    @State private var selectedDate: Date = Calendar.current.startOfMonth(for: Date())
    @State private var showingHistory = false

    // Chart palette
    private let incomeColor  = Color(red: 0.76, green: 0.96, blue: 0.18)
    private let expenseColor = Color(red: 0.93, green: 0.38, blue: 0.38)
    private let transferColor = Color(red: 0.99, green: 0.68, blue: 0.28)

    // MARK: Lookups
    private var accountById: [UUID: Account] {
        Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
    }
    private var categoryById: [UUID: Category] {
        Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
    }

    // MARK: Period data
    private var periodRange: Range<Date> {
        let cal = Calendar.current
        switch cashFlowPeriod {
        case .month:
            let start = cal.startOfMonth(for: selectedDate)
            return start ..< (cal.date(byAdding: .month, value: 1, to: start) ?? start)
        case .year:
            let comps = cal.dateComponents([.year], from: selectedDate)
            let start = cal.date(from: comps) ?? selectedDate
            return start ..< (cal.date(byAdding: .year, value: 1, to: start) ?? start)
        }
    }

    private var periodTransactions: [Transaction] {
        transactions.filter { periodRange.contains($0.date) }
    }

    private var pieSlices: [CashFlowSlice] {
        let inc = periodTransactions.filter { $0.type == .income  }.reduce(Decimal.zero) { $0 + $1.amount }
        let exp = periodTransactions.filter { $0.type == .expense }.reduce(Decimal.zero) { $0 + $1.amount }
        let trn = periodTransactions.filter { $0.type == .transfer }.reduce(Decimal.zero) { $0 + $1.amount }
        return [
            inc > 0 ? CashFlowSlice(label: String(localized: "Income"),    amount: inc, color: incomeColor)   : nil,
            exp > 0 ? CashFlowSlice(label: String(localized: "Expenses"),  amount: exp, color: expenseColor)  : nil,
            trn > 0 ? CashFlowSlice(label: String(localized: "Transfers"), amount: trn, color: transferColor) : nil,
        ].compactMap { $0 }
    }

    private var monthlyPoints: [MonthPoint] {
        let cal = Calendar.current
        let origin = cal.startOfMonth(for: Date())
        return (0 ..< 7).reversed().compactMap { offset -> MonthPoint? in
            guard let start = cal.date(byAdding: .month, value: -offset, to: origin),
                  let end   = cal.date(byAdding: .month, value:  1,      to: start) else { return nil }
            let txns = transactions.filter { start ..< end ~= $0.date }
            let inc  = txns.filter { $0.type == .income  }.reduce(Decimal.zero) { $0 + $1.amount }
            let exp  = txns.filter { $0.type == .expense }.reduce(Decimal.zero) { $0 + $1.amount }
            let trn  = txns.filter { $0.type == .transfer }.reduce(Decimal.zero) { $0 + $1.amount }
            return MonthPoint(
                date:     start,
                income:   NSDecimalNumber(decimal: inc).doubleValue,
                expense:  NSDecimalNumber(decimal: exp).doubleValue,
                transfer: NSDecimalNumber(decimal: trn).doubleValue
            )
        }
    }

    // MARK: History list data
    private var filtersActive: Bool {
        filterAccountId != nil || filterType != nil || filterCategoryId != nil
    }

    private var filteredTransactions: [Transaction] {
        transactions.filter { txn in
            if !searchText.isEmpty {
                let q    = searchText.lowercased()
                let note = txn.note.lowercased().contains(q)
                let tag  = txn.tags.contains { $0.lowercased().contains(q) }
                let cat  = categoryById[txn.categoryId ?? UUID()]?.name.lowercased().contains(q) ?? false
                if !note && !tag && !cat { return false }
            }
            if let id = filterAccountId,  txn.accountId  != id { return false }
            if let t  = filterType,        txn.type       != t  { return false }
            if let c  = filterCategoryId,  txn.categoryId != c  { return false }
            return true
        }
    }

    private var groupedTransactions: [(Date, [Transaction])] {
        let grouped = Dictionary(grouping: filteredTransactions) {
            Calendar.current.startOfDay(for: $0.date)
        }
        return grouped.sorted { $0.key > $1.key }
    }

    private var summary: (income: Decimal, expense: Decimal, net: Decimal) {
        let inc = filteredTransactions.filter { $0.type == .income  }.reduce(Decimal.zero) { $0 + $1.amount }
        let exp = filteredTransactions.filter { $0.type == .expense }.reduce(Decimal.zero) { $0 + $1.amount }
        return (inc, exp, inc - exp)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                AppTheme.canvas.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 24) {
                        periodPicker.padding(.top, 4)
                        monthNavigator
                        if pieSlices.isEmpty {
                            emptyChartState
                        } else {
                            CashFlowPieSection(slices: pieSlices)
                        }
                        CashFlowLineSection(points: monthlyPoints)
                        historyButton
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 96)
                }
                fabButton
            }
            .navigationTitle(String(localized: "Cash Flows"))
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(AppTheme.surface, for: .navigationBar)
            .toolbar { toolbarMenu }
            .sheet(isPresented: $showingHistory) { historySheet }
            .sheet(isPresented: $showingExport)  { ExportView() }
            .sheet(isPresented: $showingRecurring) {
                NavigationStack { RecurringTransactionsView() }
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
                    prefillType:       draft.type,
                    prefillAmount:     draft.amount,
                    prefillDate:       draft.date,
                    prefillAccountId:  draft.accountId,
                    prefillCategoryId: draft.categoryId,
                    prefillNote:       draft.note
                )
            }
            .sheet(item: $repeatingTransaction) { AddEditTransactionView(template: $0) }
            .onAppear {
                if isFirstLoad {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        withAnimation(.easeOut(duration: 0.3)) { isFirstLoad = false }
                    }
                }
            }
        }
    }

    // MARK: - Cash Flows sub-views

    @ToolbarContentBuilder
    private var toolbarMenu: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button { showingRecurring = true } label: {
                    Label(String(localized: "Recurring"), systemImage: "arrow.clockwise")
                }
                Button { showingExport = true } label: {
                    Label(String(localized: "Export"), systemImage: "square.and.arrow.up")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(AppTheme.primaryAccent)
            }
        }
    }

    private var periodPicker: some View {
        HStack(spacing: 0) {
            ForEach(CashFlowPeriod.allCases, id: \.self) { p in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { cashFlowPeriod = p }
                } label: {
                    Text(p.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(cashFlowPeriod == p ? AppTheme.canvas : .primary)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(cashFlowPeriod == p ? AppTheme.primaryAccent : Color.clear))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(AppTheme.surface, in: Capsule())
        .overlay(Capsule().stroke(AppTheme.outline.opacity(0.5), lineWidth: 1))
    }

    private var monthNavigator: some View {
        HStack {
            Button { navigate(-1) } label: {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.semibold))
                    .frame(width: 40, height: 40)
                    .background(AppTheme.surface, in: Circle())
                    .overlay(Circle().stroke(AppTheme.outline.opacity(0.5), lineWidth: 1))
            }
            .buttonStyle(.plain)
            Spacer()
            Text(periodTitle)
                .font(.title2.weight(.bold))
                .animation(.none, value: selectedDate)
            Spacer()
            Button { navigate(1) } label: {
                Image(systemName: "chevron.right")
                    .font(.headline.weight(.semibold))
                    .frame(width: 40, height: 40)
                    .background(AppTheme.surface, in: Circle())
                    .overlay(Circle().stroke(AppTheme.outline.opacity(0.5), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private var periodTitle: String {
        switch cashFlowPeriod {
        case .month: return selectedDate.formatted(.dateTime.month(.wide).year())
        case .year:  return selectedDate.formatted(.dateTime.year())
        }
    }

    private var emptyChartState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.pie")
                .font(.system(size: 52))
                .foregroundStyle(AppTheme.outline)
            Text(String(localized: "No Transactions"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(height: 220)
    }

    private var historyButton: some View {
        Button { showingHistory = true } label: {
            Text(String(localized: "History"))
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(AppTheme.surface, in: Capsule())
                .overlay(Capsule().stroke(AppTheme.outline.opacity(0.6), lineWidth: 1))
                .shadow(color: AppTheme.shadowSoft, radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("transactions.historyButton")
    }

    private var fabButton: some View {
        Button { showingQuickAdd = true } label: {
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

    private func navigate(_ direction: Int) {
        let component: Calendar.Component = cashFlowPeriod == .month ? .month : .year
        withAnimation(.easeInOut(duration: 0.22)) {
            selectedDate = Calendar.current.date(byAdding: component, value: direction, to: selectedDate) ?? selectedDate
        }
    }

    // MARK: - History Sheet

    private var historySheet: some View {
        NavigationStack {
            ZStack {
                AppTheme.canvas.ignoresSafeArea()
                VStack(spacing: 12) {
                    controlsHeader
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    if isFirstLoad && transactions.isEmpty {
                        skeletonList.frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if filteredTransactions.isEmpty {
                        historyEmptyState.frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        transactionList
                    }
                }
            }
            .navigationTitle(String(localized: "Transactions"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(AppTheme.surface, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Done")) { showingHistory = false }
                }
            }
            .sheet(item: $editingTransaction) { AddEditTransactionView(transaction: $0) }
            .sheet(isPresented: $showingFilter) {
                FilterSheet(
                    accounts: accounts,
                    categories: categories,
                    filterAccountId: $filterAccountId,
                    filterType: $filterType,
                    filterCategoryId: $filterCategoryId
                )
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

    // MARK: - History list sub-views

    private var controlsHeader: some View {
        VStack(spacing: 12) {
            searchBar
            filterStrip
            summaryStrip
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(String(localized: "Search transactions"), text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cockpitSurface(cornerRadius: 20, elevated: true, compact: true)
    }

    private var summaryStrip: some View {
        HStack(spacing: 12) {
            summaryTile(title: String(localized: "Income"),  value: summary.income,  tint: AppTheme.success, icon: "arrow.down.circle.fill")
            summaryTile(title: String(localized: "Expense"), value: summary.expense, tint: AppTheme.danger,  icon: "arrow.up.circle.fill")
            summaryTile(title: String(localized: "Net"),     value: summary.net,
                        tint: summary.net >= 0 ? AppTheme.success : AppTheme.danger, icon: "equal.circle.fill")
        }
    }

    private func summaryTile(title: String, value: Decimal, tint: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.caption.weight(.semibold)).foregroundStyle(tint)
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
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
                FilterChip(label: String(localized: "All"), selected: filterType == nil, tint: AppTheme.primaryAccent) {
                    filterType = nil
                }
                ForEach(TransactionType.allCases, id: \.self) { type in
                    FilterChip(label: type.localizedName, selected: filterType == type, tint: tintForType(type)) {
                        filterType = filterType == type ? nil : type
                    }
                }
                if let account = filterAccountId.flatMap({ accountById[$0] }) {
                    FilterChip(label: account.name, systemImage: "creditcard", selected: true, tint: AppTheme.info) {
                        filterAccountId = nil
                    }
                }
                if let category = filterCategoryId.flatMap({ categoryById[$0] }) {
                    FilterChip(label: category.name, systemImage: category.iconName, selected: true,
                               tint: Color(hex: category.colorHex)) {
                        filterCategoryId = nil
                    }
                }
                FilterChip(label: String(localized: "More Filters"), systemImage: "line.3.horizontal.decrease.circle",
                           selected: filtersActive, tint: AppTheme.primaryAccent) {
                    showingFilter = true
                }
                if filtersActive || !searchText.isEmpty {
                    FilterChip(label: String(localized: "Clear"), systemImage: "xmark", selected: false,
                               tint: AppTheme.warning) {
                        clearAllFilters()
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func tintForType(_ type: TransactionType) -> Color {
        switch type {
        case .income:   return AppTheme.success
        case .expense:  return AppTheme.danger
        case .transfer: return AppTheme.info
        }
    }

    private var transactionList: some View {
        List {
            ForEach(groupedTransactions, id: \.0) { date, txns in
                Section {
                    ForEach(Array(txns.enumerated()), id: \.element.id) { _, txn in
                        Button { editingTransaction = txn } label: {
                            TransactionJournalRow(
                                transaction: txn,
                                account:     accountById[txn.accountId],
                                category:    categoryById[txn.categoryId ?? UUID()],
                                toAccount:   txn.toAccountId.flatMap { accountById[$0] }
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("transactions.row.\(txn.id.uuidString)")
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button { duplicateTransaction(txn) } label: {
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

    private var skeletonList: some View {
        List {
            ForEach(0 ..< 5, id: \.self) { _ in
                HStack(spacing: 12) {
                    SkeletonView().frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 6) {
                        SkeletonView().frame(width: 140, height: 11).clipShape(Capsule())
                        SkeletonView().frame(width: 90, height: 9).clipShape(Capsule())
                    }
                    Spacer()
                    SkeletonView().frame(width: 68, height: 13).clipShape(Capsule())
                }
                .padding(.vertical, 6)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .allowsHitTesting(false)
    }

    private var historyEmptyState: some View {
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

    private func journalDayHeader(date: Date, transactions txns: [Transaction]) -> some View {
        let income  = txns.filter { $0.type == .income  }.reduce(Decimal.zero) { $0 + $1.amount }
        let expense = txns.filter { $0.type == .expense }.reduce(Decimal.zero) { $0 + $1.amount }
        let net = income - expense
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(date, format: .dateTime.weekday(.wide).day().month(.abbreviated))
                    .font(.subheadline.weight(.semibold))
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
        searchText      = ""
        filterAccountId  = nil
        filterType       = nil
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
            date: Date(), amount: txn.amount, type: txn.type,
            accountId: txn.accountId, toAccountId: txn.toAccountId,
            categoryId: txn.categoryId, note: txn.note, tags: txn.tags
        )
        modelContext.insert(copy)
    }
}

// MARK: - CashFlowPieSection

private struct CashFlowPieSection: View {
    let slices: [CashFlowSlice]

    var body: some View {
        VStack(spacing: 20) {
            Chart(slices) { slice in
                SectorMark(
                    angle: .value(slice.label, NSDecimalNumber(decimal: slice.amount).doubleValue),
                    angularInset: 5
                )
                .cornerRadius(16)
                .foregroundStyle(slice.color)
            }
            .frame(height: 230)
            .padding(.horizontal, 16)

            legendGrid
        }
    }

    private var legendGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
            ForEach(slices) { slice in
                HStack(spacing: 8) {
                    Circle().fill(slice.color).frame(width: 10, height: 10)
                    Text(slice.label)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(NumberAbbreviator.string(from: slice.amount))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                }
            }
        }
    }
}

// MARK: - CashFlowLineSection

private struct CashFlowLineSection: View {
    let points: [MonthPoint]

    private let incomeColor   = Color(red: 0.76, green: 0.96, blue: 0.18)
    private let expenseColor  = Color(red: 0.93, green: 0.38, blue: 0.38)
    private let transferColor = Color(red: 0.99, green: 0.68, blue: 0.28)

    private var hasTransfers: Bool { points.contains { $0.transfer > 0 } }

    private var chartData: [ChartSeriesPoint] {
        var data: [ChartSeriesPoint] = []
        for pt in points {
            data.append(ChartSeriesPoint(date: pt.date, amount: pt.income,  series: "income"))
            data.append(ChartSeriesPoint(date: pt.date, amount: pt.expense, series: "expenses"))
            if hasTransfers {
                data.append(ChartSeriesPoint(date: pt.date, amount: pt.transfer, series: "transfers"))
            }
        }
        return data
    }

    var body: some View {
        Chart(chartData) { point in
            LineMark(
                x: .value("Month", point.date, unit: .month),
                y: .value("Amount", point.amount)
            )
            .foregroundStyle(by: .value("Series", point.series))
            .interpolationMethod(.catmullRom)
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
        }
        .chartForegroundStyleScale([
            "income":    incomeColor,
            "expenses":  expenseColor,
            "transfers": transferColor,
        ])
        .chartLegend(.hidden)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { value in
                if let date = value.as(Date.self) {
                    AxisValueLabel {
                        Text(date, format: .dateTime.month(.abbreviated))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(height: 140)
        .padding(.top, 4)
    }
}

// MARK: - FilterSheet

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
                        ForEach(categories) { cat in
                            Text(cat.name).tag(UUID?.some(cat.id))
                        }
                    }
                }
                Section {
                    Button(String(localized: "Clear Filters"), role: .destructive) {
                        draftAccountId  = nil
                        draftType       = nil
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
                        filterAccountId  = draftAccountId
                        filterType       = draftType
                        filterCategoryId = draftCategoryId
                        dismiss()
                    }
                }
            }
            .onAppear {
                draftAccountId  = filterAccountId
                draftType       = filterType
                draftCategoryId = filterCategoryId
            }
        }
    }
}

// MARK: - TransactionJournalRow

private struct TransactionJournalRow: View {
    let transaction: Transaction
    let account: Account?
    let category: Category?
    let toAccount: Account?

    private var amountColor: Color {
        switch transaction.type {
        case .income:   return AppTheme.success
        case .expense:  return AppTheme.danger
        case .transfer: return AppTheme.info
        }
    }

    private var amountPrefix: String {
        switch transaction.type {
        case .income:   return "+"
        case .expense:  return "-"
        case .transfer: return ""
        }
    }

    private var title: String {
        if !transaction.note.isEmpty { return transaction.note }
        if let category { return category.name }
        return transaction.type == .transfer
            ? String(localized: "Transfer")
            : String(localized: "Uncategorized")
    }

    private var subtitle: String {
        switch transaction.type {
        case .transfer:
            let from = account?.name ?? String(localized: "Unknown")
            let to   = toAccount?.name ?? String(localized: "Unknown")
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
            }
        }
        .cockpitSurface(cornerRadius: 20, elevated: true, compact: true)
    }
}
