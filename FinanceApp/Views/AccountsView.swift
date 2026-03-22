import SwiftUI
import SwiftData

struct AccountsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Account.sortOrder), SortDescriptor(\Account.name)]) private var accounts: [Account]
    @Query(sort: \Category.name) private var categories: [Category]
    @Query private var transactions: [Transaction]

    @State private var showingAddAccount = false
    @State private var editingAccount: Account?
    @State private var showingCategories = false
    @State private var accountPendingDelete: Account?
    @State private var showingDeleteConfirmation = false
    @State private var editMode: EditMode = .inactive

    private struct AccountSnapshot: Identifiable {
        let account: Account
        let balance: Decimal

        var id: UUID { account.id }
    }

    private var balanceByAccountId: [UUID: Decimal] {
        var result: [UUID: Decimal] = [:]
        for txn in transactions {
            guard BalanceCalculator.isPosted(txn) else { continue }
            switch txn.type {
            case .income:
                result[txn.accountId, default: .zero] += txn.amount
            case .expense:
                result[txn.accountId, default: .zero] -= txn.amount
            case .transfer:
                result[txn.accountId, default: .zero] -= txn.amount
                if let toId = txn.toAccountId {
                    result[toId, default: .zero] += txn.amount
                }
            }
        }
        return result
    }

    private var rankedAccounts: [AccountSnapshot] {
        accounts
            .map { AccountSnapshot(account: $0, balance: balanceByAccountId[$0.id, default: .zero]) }
            .sorted { lhs, rhs in
                let lhsMagnitude = decimalMagnitude(lhs.balance)
                let rhsMagnitude = decimalMagnitude(rhs.balance)
                if lhsMagnitude != rhsMagnitude {
                    return lhsMagnitude > rhsMagnitude
                }
                if lhs.balance != rhs.balance {
                    return lhs.balance > rhs.balance
                }
                return lhs.account.name.localizedCaseInsensitiveCompare(rhs.account.name) == .orderedAscending
            }
    }

    private var netWorth: Decimal {
        rankedAccounts.reduce(.zero) { $0 + $1.balance }
    }

    private var negativeBalancesCount: Int {
        rankedAccounts.filter { $0.balance < 0 }.count
    }

    private var expenseCategoryCount: Int {
        categories.filter { $0.type == .expense }.count
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.canvas
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        heroSection
                        summarySection
                        structureToolsSection
                        accountListSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 28)
                }
            }
            .accessibilityIdentifier("accounts.screen")
            .navigationTitle(String(localized: "Accounts"))
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(AppTheme.surface, for: .navigationBar)
            .environment(\.editMode, $editMode)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    HStack {
                        EditButton()
                        Button {
                            showingAddAccount = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingAddAccount) { AddEditAccountView() }
            .sheet(item: $editingAccount) { AddEditAccountView(account: $0) }
            .sheet(isPresented: $showingCategories) { CategoriesView() }
            .alert(
                String(localized: "Delete Account"),
                isPresented: $showingDeleteConfirmation,
                presenting: accountPendingDelete
            ) { account in
                Button(String(localized: "Delete"), role: .destructive) { confirmDeleteAccount(account) }
                Button(String(localized: "Cancel"), role: .cancel) { accountPendingDelete = nil }
            } message: { _ in
                Text(String(localized: "Deleting this account will also delete all its transactions."))
            }
        }
    }

    private var heroSection: some View {
        HeroMetricCard(
            title: String(localized: "Net Worth"),
            value: CurrencyFormatter.string(from: netWorth),
            supportingTitle: String(localized: "Accounts"),
            supportingValue: "\(accounts.count)",
            note: String(format: String(localized: "%lld categories"), Int64(categories.count)),
            badgeText: negativeBalancesCount > 0
                ? String(format: String(localized: "%lld need attention"), Int64(negativeBalancesCount))
                : String(localized: "Stable")
        )
    }

    private var summarySection: some View {
        HStack(spacing: 12) {
            CompactSummaryCard(
                title: String(localized: "Accounts"),
                value: "\(accounts.count)",
                detail: String(localized: "Tracked balances"),
                systemImage: "creditcard",
                tint: AppTheme.primaryAccent
            )
            CompactSummaryCard(
                title: String(localized: "Categories"),
                value: "\(expenseCategoryCount)",
                detail: String(localized: "Expense buckets"),
                systemImage: "square.grid.2x2",
                tint: AppTheme.secondaryAccent
            )
            CompactSummaryCard(
                title: String(localized: "Attention"),
                value: "\(negativeBalancesCount)",
                detail: negativeBalancesCount == 0
                    ? String(localized: "No negative balances")
                    : String(localized: "Negative balances"),
                systemImage: "exclamationmark.triangle.fill",
                tint: negativeBalancesCount == 0 ? AppTheme.success : AppTheme.warning
            )
        }
    }

    private var structureToolsSection: some View {
        SectionShell(
            title: String(localized: "Structure Tools"),
            subtitle: String(localized: "Manage account setup and category structure")
        ) {
            HStack(spacing: 12) {
                ActionTile(
                    title: String(localized: "Manage Categories"),
                    subtitle: String(localized: "Shape your income and expense buckets"),
                    systemImage: "square.grid.2x2",
                    tint: AppTheme.secondaryAccent
                ) {
                    showingCategories = true
                }
                .accessibilityIdentifier("accounts.manageCategories")

                ActionTile(
                    title: String(localized: "Add Account"),
                    subtitle: String(localized: "Create a new balance source"),
                    systemImage: "plus.circle.fill",
                    tint: AppTheme.primaryAccent
                ) {
                    showingAddAccount = true
                }
            }
        }
    }

    private var displayedAccounts: [AccountSnapshot] {
        editMode == .active ? accounts.map { AccountSnapshot(account: $0, balance: balanceByAccountId[$0.id, default: .zero]) } : rankedAccounts
    }

    private var accountListSection: some View {
        SectionShell(
            title: String(localized: "Account List"),
            subtitle: editMode == .active
                ? String(localized: "Drag to reorder")
                : String(localized: "Sorted by balance significance")
        ) {
            if rankedAccounts.isEmpty {
                EmptyStateView(
                    icon: "creditcard.fill",
                    title: String(localized: "No Accounts"),
                    subtitle: String(localized: "Add your first account to track balances"),
                    actionTitle: String(localized: "Add Account"),
                    action: { showingAddAccount = true }
                )
            } else {
                List {
                    ForEach(displayedAccounts) { snapshot in
                        NavigationLink(destination: AccountDetailView(account: snapshot.account)) {
                            AccountRow(
                                account: snapshot.account,
                                balance: snapshot.balance,
                                sparkline: sparklineValues(for: snapshot.account)
                            )
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                accountPendingDelete = snapshot.account
                                showingDeleteConfirmation = true
                            } label: {
                                Label(String(localized: "Delete"), systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button(String(localized: "Edit")) { editingAccount = snapshot.account }
                            Button(String(localized: "Delete"), role: .destructive) {
                                accountPendingDelete = snapshot.account
                                showingDeleteConfirmation = true
                            }
                        }
                    }
                    .onMove { from, to in
                        moveAccounts(from: from, to: to)
                    }
                }
                .listStyle(.plain)
                .scrollDisabled(true)
                .scrollContentBackground(.hidden)
                .frame(minHeight: CGFloat(displayedAccounts.count) * 120)
            }
        }
    }

    private func decimalMagnitude(_ value: Decimal) -> Decimal {
        value < 0 ? -value : value
    }

    private func sparklineValues(for account: Account) -> [Double] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<30).reversed().map { daysAgo -> Double in
            guard let day = cal.date(byAdding: .day, value: -daysAgo, to: today),
                  let endOfDay = cal.date(byAdding: .second, value: 86399, to: day) else { return 0 }
            let balance = BalanceCalculator.balance(for: account, in: transactions, asOf: endOfDay)
            return NSDecimalNumber(decimal: balance).doubleValue
        }
    }

    private func moveAccounts(from source: IndexSet, to destination: Int) {
        var reordered = displayedAccounts
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, snapshot) in reordered.enumerated() {
            snapshot.account.sortOrder = index
        }
    }

    private func confirmDeleteAccount(_ account: Account) {
        for txn in transactions where txn.accountId == account.id || txn.toAccountId == account.id {
            modelContext.delete(txn)
        }
        modelContext.delete(account)
        do {
            try modelContext.save()
        } catch {
            print("Save error: \(error)")
        }
        accountPendingDelete = nil
    }
}

private struct AccountRow: View {
    let account: Account
    let balance: Decimal
    let sparkline: [Double]

    private var tint: Color {
        balance >= 0 ? AppTheme.primaryAccent : AppTheme.warning
    }

    private var iconName: String {
        switch account.type {
        case .checking: return "building.columns.fill"
        case .savings: return "banknote.fill"
        case .cash: return "wallet.pass.fill"
        case .card: return "creditcard.fill"
        case .deposit: return "lock.shield.fill"
        case .crypto: return "bitcoinsign.circle.fill"
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 14) {
                Image(systemName: iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 40, height: 40)
                    .background(tint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(account.name)
                        .font(.subheadline.weight(.semibold))
                    Text("\(account.type.localizedName) • \(account.currencyCode)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(CurrencyFormatter.string(from: balance, currencyCode: account.currencyCode))
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(balance >= 0 ? .primary : AppTheme.danger)
                    Text(balance >= 0 ? String(localized: "Available") : String(localized: "Below zero"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            SparklineView(values: sparkline, tint: tint)
                .frame(height: 36)
                .opacity(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cockpitSurface(cornerRadius: 20, elevated: true, compact: true)
    }
}
