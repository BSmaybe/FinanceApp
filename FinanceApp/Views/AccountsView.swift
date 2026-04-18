import SwiftUI
import SwiftData

struct AccountsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Account.sortOrder), SortDescriptor(\Account.name)]) private var accounts: [Account]
    @Query private var transactions: [Transaction]
    @Query private var subscriptions: [Subscription]
    @Query private var debts: [Debt]

    @State private var showingAddAccount = false
    @State private var editingAccount: Account?
    @State private var showingCategories = false
    @State private var accountPendingDelete: Account?
    @State private var showingDeleteConfirmation = false
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

    private var activeSubscriptions: [Subscription] {
        subscriptions.filter(\.isActive)
    }

    private var displayedAccounts: [Account] {
        accounts.sorted {
            let lhs = balance(for: $0)
            let rhs = balance(for: $1)
            if lhs == rhs {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return lhs > rhs
        }
    }

    private var liquidBalance: Decimal {
        accounts.filter(isLiquid).reduce(.zero) { $0 + balance(for: $1) }
    }

    private var reserveBalance: Decimal {
        accounts.filter(isReserve).reduce(.zero) { $0 + balance(for: $1) }
    }

    private var monthlyCommitments: Decimal {
        activeSubscriptions.reduce(.zero) { $0 + $1.monthlyCost } + debts.reduce(.zero) { $0 + $1.minimumPayment }
    }

    private var coverageRatio: Double {
        guard monthlyCommitments > 0 else { return 0 }
        return NSDecimalNumber(decimal: liquidBalance / monthlyCommitments).doubleValue
    }

    private var largestAccount: Account? {
        displayedAccounts.first
    }

    private var currenciesCount: Int {
        Set(accounts.map(\.currencyCode)).count
    }

    private func isLiquid(_ account: Account) -> Bool {
        switch account.type {
        case .checking, .savings, .cash:
            return true
        case .card, .deposit, .crypto:
            return false
        }
    }

    private func isReserve(_ account: Account) -> Bool {
        switch account.type {
        case .savings, .deposit:
            return true
        case .checking, .cash, .card, .crypto:
            return false
        }
    }

    private var heroNote: String {
        if accounts.isEmpty {
            return String(localized: "Add accounts to start seeing reserve and runway.")
        }
        if monthlyCommitments > 0 {
            return String(
                format: String(localized: "Covers %.1fx monthly load"),
                coverageRatio
            )
        }
        if let largestAccount {
            return String(
                format: String(localized: "Largest balance in %@"),
                largestAccount.name
            )
        }
        return String(localized: "No monthly commitments yet")
    }

    private var skeletonAccountRow: some View {
        HStack(spacing: 12) {
            SkeletonView()
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 8) {
                SkeletonView().frame(width: 120, height: 12).clipShape(Capsule())
                SkeletonView().frame(width: 92, height: 10).clipShape(Capsule())
            }
            Spacer()
            SkeletonView().frame(width: 88, height: 14).clipShape(Capsule())
        }
        .padding(14)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    accountsHeroSection

                    HStack(spacing: 10) {
                        CompactSummaryCard(
                            title: String(localized: "Liquid"),
                            value: CurrencyFormatter.string(from: liquidBalance),
                            detail: String(localized: "Ready to use"),
                            systemImage: "drop.fill",
                            tint: AppTheme.info
                        )
                        CompactSummaryCard(
                            title: String(localized: "Reserve"),
                            value: CurrencyFormatter.string(from: reserveBalance),
                            detail: String(localized: "Savings and deposits"),
                            systemImage: "shield.lefthalf.filled",
                            tint: AppTheme.success
                        )
                        CompactSummaryCard(
                            title: String(localized: "Monthly commitments"),
                            value: CurrencyFormatter.string(from: monthlyCommitments),
                            detail: String(localized: "Subscriptions and debt minimums"),
                            systemImage: "calendar.badge.clock",
                            tint: AppTheme.warning
                        )
                    }

                    accountsListSection
                    structureToolsSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 32)
            }
            .financeNavigationSurface()
            .accessibilityIdentifier("accounts.screen")
            .navigationTitle(String(localized: "Accounts"))
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(AppTheme.surface, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAddAccount = true } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(AppTheme.primaryAccent)
                    }
                    .accessibilityLabel(String(localized: "Add Account"))
                }
            }
            .onAppear {
                if isFirstLoad {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        withAnimation(.easeOut(duration: 0.3)) { isFirstLoad = false }
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

    private var accountsHeroSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Balance Hub"))
                        .font(.system(.title3, design: .rounded).weight(.bold))
                    Text(String(localized: "See where money sits, what stays liquid and what covers the month."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                if currenciesCount > 0 {
                    Text("\(currenciesCount)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.primaryAccent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AppTheme.surfaceMuted)
                        .clipShape(Capsule())
                }
            }

            HeroMetricCard(
                title: String(localized: "Total balance"),
                value: CurrencyFormatter.string(from: netWorth),
                supportingTitle: String(localized: "Liquid funds"),
                supportingValue: CurrencyFormatter.string(from: liquidBalance),
                note: heroNote,
                badgeText: accounts.isEmpty
                    ? nil
                    : String(format: String(localized: "%lld accounts"), Int64(accounts.count))
            )
        }
    }

    private var accountsListSection: some View {
        SectionShell(
            title: String(localized: "Accounts"),
            subtitle: String(localized: "Sorted by balance and account role.")
        ) {
            if isFirstLoad && accounts.isEmpty {
                VStack(spacing: 10) {
                    ForEach(0..<3, id: \.self) { _ in skeletonAccountRow }
                }
            } else if accounts.isEmpty {
                VStack(spacing: 14) {
                    EmptyStateView(
                        icon: "creditcard.fill",
                        title: String(localized: "No Accounts"),
                        subtitle: String(localized: "Add your first account to track balances"),
                        actionTitle: String(localized: "Add Account"),
                        action: { showingAddAccount = true }
                    )

                    HStack(spacing: 12) {
                        ActionTile(
                            title: String(localized: "Add Account"),
                            subtitle: String(localized: "Create a new balance source"),
                            systemImage: "plus.circle.fill",
                            tint: AppTheme.primaryAccent
                        ) {
                            showingAddAccount = true
                        }
                        ActionTile(
                            title: String(localized: "Manage Categories"),
                            subtitle: String(localized: "Set roles and spending structure"),
                            systemImage: "square.grid.2x2",
                            tint: AppTheme.info
                        ) {
                            showingCategories = true
                        }
                    }
                }
            } else {
                VStack(spacing: 10) {
                    ForEach(displayedAccounts) { account in
                        NavigationLink(destination: AccountDetailView(account: account)) {
                            AccountHubRow(account: account, balance: balance(for: account))
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                editingAccount = account
                            } label: {
                                Label(String(localized: "Edit"), systemImage: "pencil")
                            }

                            Button(role: .destructive) {
                                accountPendingDelete = account
                                showingDeleteConfirmation = true
                            } label: {
                                Label(String(localized: "Delete"), systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }

    private var structureToolsSection: some View {
        SectionShell(
            title: String(localized: "Structure Tools"),
            subtitle: String(localized: "Add accounts and keep categories organised.")
        ) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ActionTile(
                    title: String(localized: "Add Account"),
                    subtitle: String(localized: "Create a new balance source"),
                    systemImage: "plus.circle.fill",
                    tint: AppTheme.primaryAccent
                ) {
                    showingAddAccount = true
                }

                ActionTile(
                    title: String(localized: "Manage Categories"),
                    subtitle: String(localized: "Set roles and spending structure"),
                    systemImage: "square.grid.2x2.fill",
                    tint: AppTheme.info
                ) {
                    showingCategories = true
                }
            }
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

private struct AccountHubRow: View {
    let account: Account
    let balance: Decimal

    private var tint: Color {
        balance >= 0 ? AppTheme.primaryAccent : AppTheme.warning
    }

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

    private var roleLabel: String {
        switch account.type {
        case .checking, .cash, .card:
            return String(localized: "Daily spending")
        case .savings, .deposit:
            return String(localized: "Reserve")
        case .crypto:
            return String(localized: "Investments")
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 42, height: 42)
                .background(tint.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(account.name)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(CurrencyFormatter.string(from: balance, currencyCode: account.currencyCode))
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(balance >= 0 ? .primary : AppTheme.danger)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                HStack(spacing: 6) {
                    Text(roleLabel)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(tint.opacity(0.12))
                        .clipShape(Capsule())

                    Text("\(account.type.localizedName) · \(account.currencyCode)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if !account.note.isEmpty {
                    Text(account.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
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
