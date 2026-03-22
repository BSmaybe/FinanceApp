import Foundation
import SwiftData

@Model
class Budget {
    var id: UUID
    var categoryId: UUID
    var amount: String  // stored as String for Decimal, same pattern as Transaction
    var month: Int      // 1-12
    var year: Int

    var limitAmount: Decimal {
        get { Decimal(string: amount) ?? .zero }
        set { amount = (newValue as NSDecimalNumber).stringValue }
    }

    init(categoryId: UUID, limitAmount: Decimal, month: Int, year: Int) {
        self.id = UUID()
        self.categoryId = categoryId
        self.amount = (limitAmount as NSDecimalNumber).stringValue
        self.month = month
        self.year = year
    }
}
