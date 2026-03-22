import Foundation
import SwiftData

enum DebtType: String, Codable, CaseIterable {
    case loan = "Loan"
    case creditCard = "Credit Card"
    case mortgage = "Mortgage"
    case installment = "Installment"
    case other = "Other"

    var localizedName: String {
        String(localized: String.LocalizationValue(rawValue))
    }
}

@Model
class Debt {
    var id: UUID
    var name: String
    var totalValue: String
    var remainingValue: String
    var interestRateValue: String   // annual rate as decimal, e.g. "0.05" for 5%
    var minimumPaymentValue: String
    var dueDay: Int                 // day of month (1-31)
    var type: DebtType
    var note: String
    var totalInstallments: Int      // 0 = not installment, N = total payment count

    var totalAmount: Decimal {
        get { Decimal(string: totalValue) ?? .zero }
        set { totalValue = (newValue as NSDecimalNumber).stringValue }
    }
    var remainingAmount: Decimal {
        get { Decimal(string: remainingValue) ?? .zero }
        set { remainingValue = (newValue as NSDecimalNumber).stringValue }
    }
    var interestRate: Decimal {
        get { Decimal(string: interestRateValue) ?? .zero }
        set { interestRateValue = (newValue as NSDecimalNumber).stringValue }
    }
    var minimumPayment: Decimal {
        get { Decimal(string: minimumPaymentValue) ?? .zero }
        set { minimumPaymentValue = (newValue as NSDecimalNumber).stringValue }
    }
    var progress: Double {
        guard totalAmount > 0 else { return 0 }
        let paid = totalAmount - remainingAmount
        return NSDecimalNumber(decimal: paid / totalAmount).doubleValue
    }

    var paidInstallments: Int {
        guard type == .installment, minimumPayment > 0, totalInstallments > 0 else { return 0 }
        let paid = totalAmount - remainingAmount
        let count = NSDecimalNumber(decimal: paid / minimumPayment).doubleValue.rounded()
        return max(0, Int(count))
    }

    /// Total number of payments for the full loan (from the very start).
    var totalPaymentsCount: Int? {
        guard minimumPayment > 0, totalAmount > 0 else { return nil }

        if type == .installment, totalInstallments > 0 {
            return totalInstallments
        }

        let r = NSDecimalNumber(decimal: interestRate / 12).doubleValue
        let payment = NSDecimalNumber(decimal: minimumPayment).doubleValue
        let total = NSDecimalNumber(decimal: totalAmount).doubleValue

        if r > 0 {
            let denominator = payment - total * r
            guard denominator > 0 else { return nil }
            return Int(ceil(log(payment / denominator) / log(1 + r)))
        } else {
            return Int(ceil(total / payment))
        }
    }

    /// Number of payments already made (derived from paid amount).
    var paidPaymentsCount: Int? {
        guard let total = totalPaymentsCount, total > 0, minimumPayment > 0 else { return nil }

        if type == .installment, totalInstallments > 0 {
            return paidInstallments
        }

        let r = NSDecimalNumber(decimal: interestRate / 12).doubleValue
        let payment = NSDecimalNumber(decimal: minimumPayment).doubleValue
        let remaining = NSDecimalNumber(decimal: remainingAmount).doubleValue

        let remainingCount: Int
        if r > 0 {
            let denominator = payment - remaining * r
            guard denominator > 0 else { return 0 }
            remainingCount = Int(ceil(log(payment / denominator) / log(1 + r)))
        } else {
            remainingCount = Int(ceil(remaining / payment))
        }
        return max(0, total - remainingCount)
    }

    init(name: String, totalAmount: Decimal, remainingAmount: Decimal, interestRate: Decimal, minimumPayment: Decimal, dueDay: Int, type: DebtType, note: String = "", totalInstallments: Int = 0) {
        self.id = UUID()
        self.name = name
        self.totalValue = (totalAmount as NSDecimalNumber).stringValue
        self.remainingValue = (remainingAmount as NSDecimalNumber).stringValue
        self.interestRateValue = (interestRate as NSDecimalNumber).stringValue
        self.minimumPaymentValue = (minimumPayment as NSDecimalNumber).stringValue
        self.dueDay = dueDay
        self.type = type
        self.note = note
        self.totalInstallments = totalInstallments
    }
}
