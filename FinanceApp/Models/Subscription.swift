import Foundation
import SwiftData

@Model
class Subscription {
    var id: UUID
    var name: String
    var amountValue: String
    var frequency: RecurringFrequency
    var categoryId: UUID?
    var nextBillingDate: Date
    var note: String
    var isActive: Bool

    var amount: Decimal {
        get { Decimal(string: amountValue) ?? .zero }
        set { amountValue = (newValue as NSDecimalNumber).stringValue }
    }

    var monthlyCost: Decimal {
        switch frequency {
        case .daily: return amount * 30
        case .weekly: return amount * Decimal(52) / Decimal(12)
        case .monthly: return amount
        case .yearly: return amount / 12
        }
    }

    var yearlyCost: Decimal {
        switch frequency {
        case .daily: return amount * 365
        case .weekly: return amount * 52
        case .monthly: return amount * 12
        case .yearly: return amount
        }
    }

    init(name: String, amount: Decimal, frequency: RecurringFrequency, categoryId: UUID? = nil, nextBillingDate: Date, note: String = "", isActive: Bool = true) {
        self.id = UUID()
        self.name = name
        self.amountValue = (amount as NSDecimalNumber).stringValue
        self.frequency = frequency
        self.categoryId = categoryId
        self.nextBillingDate = nextBillingDate
        self.note = note
        self.isActive = isActive
    }
}
