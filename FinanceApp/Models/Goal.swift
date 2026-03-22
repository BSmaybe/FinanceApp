import Foundation
import SwiftData

@Model
final class Goal {
    var id: UUID
    var name: String
    var targetValue: String   // Decimal stored as String
    var currentValue: String  // Decimal stored as String
    var note: String
    var createdDate: Date

    var targetAmount: Decimal {
        get { Decimal(string: targetValue) ?? .zero }
        set { targetValue = (newValue as NSDecimalNumber).stringValue }
    }

    var currentAmount: Decimal {
        get { Decimal(string: currentValue) ?? .zero }
        set { currentValue = (newValue as NSDecimalNumber).stringValue }
    }

    var progress: Double {
        guard targetAmount > 0 else { return 0 }
        let ratio = NSDecimalNumber(decimal: currentAmount / targetAmount).doubleValue
        return min(1.0, max(0, ratio))
    }

    init(
        id: UUID = UUID(),
        name: String,
        targetAmount: Decimal,
        currentAmount: Decimal = .zero,
        note: String = "",
        createdDate: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.targetValue = (targetAmount as NSDecimalNumber).stringValue
        self.currentValue = (currentAmount as NSDecimalNumber).stringValue
        self.note = note
        self.createdDate = createdDate
    }
}
