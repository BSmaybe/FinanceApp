import Foundation
import SwiftData

enum TransactionType: String, Codable, CaseIterable {
    case income = "Income"
    case expense = "Expense"
    case transfer = "Transfer"

    var localizedName: String {
        String(localized: String.LocalizationValue(rawValue))
    }
}

@Model
final class Transaction {
    var id: UUID
    var date: Date
    var amountValue: String  // stored as String to preserve Decimal precision
    var type: TransactionType
    var accountId: UUID
    var toAccountId: UUID?
    var categoryId: UUID?
    var note: String
    var tagsRaw: String = ""

    // Computed so SwiftData stores a plain String scalar (no faulting on array transformable)
    var tags: [String] {
        get { tagsRaw.isEmpty ? [] : tagsRaw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
        set { tagsRaw = newValue.joined(separator: ", ") }
    }

    var amount: Decimal {
        get { Decimal(string: amountValue) ?? .zero }
        set { amountValue = (newValue as NSDecimalNumber).stringValue }
    }

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        amount: Decimal,
        type: TransactionType,
        accountId: UUID,
        toAccountId: UUID? = nil,
        categoryId: UUID? = nil,
        note: String = "",
        tags: [String] = []
    ) {
        self.id = id
        self.date = date
        self.amountValue = (amount as NSDecimalNumber).stringValue
        self.type = type
        self.accountId = accountId
        self.toAccountId = toAccountId
        self.categoryId = categoryId
        self.note = note
        self.tagsRaw = tags.joined(separator: ", ")
    }
}
