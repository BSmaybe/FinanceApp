import Foundation
import SwiftData

enum RecurringFrequency: String, Codable, CaseIterable {
    case daily = "daily"
    case weekly = "weekly"
    case monthly = "monthly"
    case yearly = "yearly"

    var localizedName: String {
        String(localized: String.LocalizationValue(rawValue))
    }
}

@Model
class RecurringTransaction {
    var id: UUID
    var title: String
    var amountValue: String
    var type: TransactionType
    var accountId: UUID
    var toAccountId: UUID?
    var categoryId: UUID?
    var note: String
    var frequency: RecurringFrequency
    var startDate: Date
    var lastGeneratedDate: Date?
    var isActive: Bool

    var amount: Decimal {
        get { Decimal(string: amountValue) ?? .zero }
        set { amountValue = (newValue as NSDecimalNumber).stringValue }
    }

    init(title: String, amount: Decimal, type: TransactionType, accountId: UUID, toAccountId: UUID? = nil, categoryId: UUID? = nil, note: String = "", frequency: RecurringFrequency, startDate: Date) {
        self.id = UUID()
        self.title = title
        self.amountValue = (amount as NSDecimalNumber).stringValue
        self.type = type
        self.accountId = accountId
        self.toAccountId = toAccountId
        self.categoryId = categoryId
        self.note = note
        self.frequency = frequency
        self.startDate = startDate
        self.lastGeneratedDate = nil
        self.isActive = true
    }
}
