import SwiftUI
import SwiftData

struct AccountsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Account.sortOrder), SortDescriptor(\Account.name)]) private var accounts: [Account]
    @Query private var transactions: [Transaction]

    @State private var showingAddAccount = false
    @State private var editingAccount: Account?
    @State private var showingCategories = false
    @State private var accountPendingDelete: Account?
    @State private var showingDeleteConfirmation = false
    @State private var editMode: EditMode = .inactive
    // C3: skeleton on first load
    @State private var isFirstLoad = true

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

    private func balance(for account: Account) -> Decimal {
        account.openingBalance + (balanceByAccountId[account.id] ?? .zero)
    }

    private var netWorth: Decimal {
        accounts.reduce(.zero) { $0 + balance(for: $1) }
    }

    private var displayedAccounts: [Account] {
        editMode == .active
            ? accounts
            : accounts.sorted { balance(for: $0) > balance(for: $1) }
    }

    // C3: Skeleton row while loading
    private var skeletonAccountRow: some View {
        HStack(spacing: 12) {
            SkeletonView()
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                SkeletonView().frame(width: 120, height: 11).clipShape(Capsule())
                SkeletonView().frame(width: 80, height: 9).clipShape(Capsule())
            }
            Spacer()
            SkeletonView().frame(width: 72, height: 13).clipShape(Capsule())
        }
        .padding(.vertical, 6)
    }

    var body: some View {
        NavigationStack {
            List {
                // Net worth summary — one compact row
                Section {
                    HStack {
                        Label(String(localized: "Net Worth"), systemImage: "chart.pie.fill")
                            .foregroundStyle(AppTheme.primaryAccent)
                        Spacer()
                        Text(CurrencyFormatter.string(from: netWorth))
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(netWorth >= 0 ? .primary : AppTheme.danger)
                    }
                }

                // Account list
                Section(String(localized: "Accounts")) {
                    if isFirstLoad && accounts.isEmpty {
                        ForEach(0..<3, id: \.self) { _ in
                            skeletonAccountRow
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    } else if accounts.isEmpty {
                        EmptyStateView(
                            icon: "creditcard.fill",
                            title: String(localized: "No Accounts"),
                            subtitle: String(localized: "Add your first account to track balances"),
                            actionTitle: String(localized: "Add Account"),
                            action: { showingAddAccount = true }
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    } else {
                        ForEach(displayedAccounts) { account in
                            NavigationLink(destination: AccountDetailView(account: account)) {
                                AccountRow(account: account, balance: balance(for: account))
                            }
                            .swipeActions(edge: .leading) {
                                Button { editingAccount = account } label: {
                                    Label(String(localized: "Edit"), systemImage: "pencil")
                                }
                                .tint(AppTheme.primaryAccent)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    accountPendingDelete = account
                                    showingDeleteConfirmation = true
                                } label: {
                                    Label(String(localized: "Delete"), systemImage: "trash")
                                }
                            }
                        }
                        .onMove { from, to in moveAccounts(from: from, to: to) }
                    }
                }

                // Utilities
                Section {
                    Button {
                        showingCategories = true
                    } label: {
                        Label(String(localized: "Manage Categories"), systemImage: "square.grid.2x2")
                    }
                }
            }
            .listStyle(.plain)
            .financeNavigationSurface()
            .accessibilityIdentifier("accounts.screen")
            .navigationTitle(String(localized: "Accounts"))
            .environment(\.editMode, $editMode)
            .onAppear {
                if isFirstLoad {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        withAnimation(.easeOut(duration: 0.3)) { isFirstLoad = false }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    HStack {
                        EditButton()
                        Button { showingAddAccount = true } label: {
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

    private func moveAccounts(from source: IndexSet, to destination: Int) {
        var reordered = displayedAccounts
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, account) in reordered.enumerated() {
            account.sortOrder = index
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

// MARK: - Account Row

private struct AccountRow: View {
    let account: Account
    let balance: Decimal

    private var tint: Color { balance >= 0 ? AppTheme.primaryAccent : AppTheme.warning }

    private var iconName: String {
        switch account.type {
        case .checking: return "building.columns.fill"
        case .savings:  return "banknote.fill"
        case .cash:     return "wallet.pass.fill"
        case .card:     return "creditcard.fill"
        case .deposit:  return "lock.shield.fill"
        case .crypto:   return "bitcoinsign.circle.fill"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 5) {
                    Text("\(account.type.localizedName) • \(account.currencyCode)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if account.interestRate > 0 {
                        Text("\(NSDecimalNumber(decimal: account.interestRate).doubleValue, specifier: "%.1f")% p.a.")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AppTheme.success)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(AppTheme.success.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
            }

            Spacer()

            Text(CurrencyFormatter.string(from: balance, currencyCode: account.currencyCode))
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(balance >= 0 ? .primary : AppTheme.danger)
        }
        .padding(.vertical, 6)
    }
}
