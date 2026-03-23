import Foundation

enum BalanceCalculator {
    static func isPosted(_ transaction: Transaction, asOf date: Date = Date()) -> Bool {
        transaction.date <= date
    }

    static func postedTransactions(_ transactions: [Transaction], asOf date: Date = Date()) -> [Transaction] {
        transactions.filter { isPosted($0, asOf: date) }
    }

    static func balance(for account: Account, in transactions: [Transaction], asOf date: Date = Date()) -> Decimal {
        var total: Decimal = account.openingBalance
        for txn in transactions {
            guard isPosted(txn, asOf: date) else { continue }
            if txn.accountId == account.id {
                switch txn.type {
                case .income:   total += txn.amount
                case .expense:  total -= txn.amount
                case .transfer: total -= txn.amount  // outgoing
                }
            }
            if txn.toAccountId == account.id && txn.type == .transfer {
                total += txn.amount  // incoming transfer
            }
        }
        return total
    }
}
