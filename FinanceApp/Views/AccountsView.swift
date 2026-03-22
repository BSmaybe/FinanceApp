import SwiftUI
import SwiftData

struct AccountsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Account.name) private var accounts: [Account]
    @Query private var transactions: [Transaction]

    @State private var showingAddAccount = false
    @State private var editingAccount: Account?
    @State private var showingCategories = false
    @State private var accountPendingDelete: Account?
    @State private var showingDeleteConfirmation = false

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

    var body: some View {
        NavigationStack {
            accountList
                .navigationTitle("Accounts")
                .toolbar { accountToolbar }
                .sheet(isPresented: $showingAddAccount) { AddEditAccountView() }
                .sheet(item: $editingAccount) { AddEditAccountView(account: $0) }
                .sheet(isPresented: $showingCategories) { CategoriesView() }
                .alert(
                    "Delete Account",
                    isPresented: $showingDeleteConfirmation,
                    presenting: accountPendingDelete
                ) { account in
                    Button("Delete", role: .destructive) { confirmDeleteAccount(account) }
                    Button("Cancel", role: .cancel) { accountPendingDelete = nil }
                } message: { _ in
                    Text("Deleting this account will also delete all its transactions.")
                }
        }
    }

    private var accountList: some View {
        List {
            Section {
                HStack {
                    Text(String(localized: "Net Worth"))
                        .font(.headline)
                    Spacer()
                    let netWorth = accounts.reduce(Decimal.zero) {
                        $0 + balanceByAccountId[$1.id, default: .zero]
                    }
                    Text(CurrencyFormatter.string(from: netWorth))
                        .font(.title3.monospacedDigit().bold())
                        .foregroundStyle(netWorth >= 0 ? Color.primary : Color.red)
                }
                .padding(.vertical, 4)
            }

            Section("Accounts") {
                if accounts.isEmpty {
                    Text("No accounts yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(accounts) { account in
                        NavigationLink(destination: AccountDetailView(account: account)) {
                            AccountRow(account: account, balance: balanceByAccountId[account.id, default: .zero])
                        }
                        .contextMenu {
                            Button("Edit") { editingAccount = account }
                        }
                    }
                    .onDelete(perform: requestDeleteAccounts)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var accountToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button("Categories") { showingCategories = true }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Button { showingAddAccount = true } label: { Image(systemName: "plus") }
        }
    }

    private func requestDeleteAccounts(at offsets: IndexSet) {
        if let index = offsets.first {
            accountPendingDelete = accounts[index]
            showingDeleteConfirmation = true
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

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .font(.body)
                Text(account.type.localizedName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(CurrencyFormatter.string(from: balance, currencyCode: account.currencyCode))
                .font(.body.monospacedDigit())
                .foregroundStyle(balance >= 0 ? Color.primary : Color.red)
        }
    }
}
