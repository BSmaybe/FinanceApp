import SwiftUI
import SwiftData
import Charts

struct AccountDetailView: View {
    let account: Account

    @Query private var allTransactions: [Transaction]
    @Query private var categories: [Category]

    // Transactions for this account (source or destination)
    private var accountTransactions: [Transaction] {
        allTransactions.filter {
            BalanceCalculator.isPosted($0) &&
            ($0.accountId == account.id || ($0.type == .transfer && $0.toAccountId == account.id))
        }
        .sorted { $0.date < $1.date }
    }

    private var currentBalance: Decimal {
        BalanceCalculator.balance(for: account, in: allTransactions)
    }

    // Running balance data points for chart
    private struct BalancePoint: Identifiable {
        let id: UUID
        let date: Date
        let balance: Double
    }

    private var balanceHistory: [BalancePoint] {
        var running: Decimal = 0
        return accountTransactions.map { txn -> BalancePoint in
            if txn.accountId == account.id {
                switch txn.type {
                case .income:   running += txn.amount
                case .expense:  running -= txn.amount
                case .transfer: running -= txn.amount
                }
            }
            if txn.toAccountId == account.id && txn.type == .transfer {
                running += txn.amount
            }
            return BalancePoint(
                id: txn.id,
                date: txn.date,
                balance: NSDecimalNumber(decimal: running).doubleValue
            )
        }
    }

    // Last 20 transactions (most recent first)
    private var recentTransactions: [Transaction] {
        Array(accountTransactions.reversed().prefix(20))
    }

    var body: some View {
        List {
            // Account summary header
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(account.name)
                        .font(.title2.bold())
                    Text(account.type.localizedName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(CurrencyFormatter.string(from: currentBalance, currencyCode: account.currencyCode))
                        .font(.title.monospacedDigit())
                        .foregroundStyle(currentBalance >= 0 ? Color.primary : Color.red)
                        .padding(.top, 2)
                }
                .padding(.vertical, 4)
            }

            // Balance history chart
            Section(String(localized: "Balance History")) {
                if balanceHistory.isEmpty {
                    Text(String(localized: "No data"))
                        .foregroundStyle(.secondary)
                } else {
                    Chart(balanceHistory) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Balance", point.balance)
                        )
                        .foregroundStyle(Color.accentColor)
                        .interpolationMethod(.stepEnd)

                        AreaMark(
                            x: .value("Date", point.date),
                            y: .value("Balance", point.balance)
                        )
                        .foregroundStyle(Color.accentColor.opacity(0.15))
                        .interpolationMethod(.stepEnd)
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { value in
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { _ in
                            AxisGridLine()
                            AxisValueLabel()
                        }
                    }
                    .frame(height: 200)
                    .padding(.vertical, 8)
                }
            }

            // Recent transactions
            if !recentTransactions.isEmpty {
                let total = accountTransactions.count
                let shown = recentTransactions.count
                Section(String(localized: "Recent Transactions")) {
                    ForEach(recentTransactions) { txn in
                        AccountDetailTransactionRow(
                            transaction: txn,
                            category: categories.first { $0.id == txn.categoryId },
                            isIncoming: txn.toAccountId == account.id && txn.type == .transfer
                        )
                    }
                    if total > shown {
                        Text(String(localized: "Showing \(shown) of \(total)"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(account.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AccountDetailTransactionRow: View {
    let transaction: Transaction
    let category: Category?
    let isIncoming: Bool

    private var amountColor: Color {
        switch transaction.type {
        case .income:   return .green
        case .expense:  return .red
        case .transfer: return isIncoming ? .green : .secondary
        }
    }

    private var amountPrefix: String {
        switch transaction.type {
        case .income:   return "+"
        case .expense:  return "-"
        case .transfer: return isIncoming ? "+" : ""
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(category != nil ? Color(hex: category!.colorHex) : Color.gray.opacity(0.4))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(category?.name ?? (transaction.type == .transfer
                    ? String(localized: "Transfer")
                    : String(localized: "Uncategorized")))
                    .font(.body)
                if !transaction.note.isEmpty {
                    Text(transaction.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(transaction.date, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(amountPrefix)\(CurrencyFormatter.string(from: transaction.amount))")
                .font(.body.monospacedDigit())
                .foregroundStyle(amountColor)
        }
        .padding(.vertical, 2)
    }
}
