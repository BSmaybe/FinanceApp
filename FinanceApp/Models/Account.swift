import Foundation
import SwiftData

enum AccountType: String, Codable, CaseIterable {
    case checking = "Checking"
    case savings = "Savings"
    case cash = "Cash"
    case card = "Card"
    case deposit = "Deposit"
    case crypto = "Crypto"

    var localizedName: String {
        String(localized: String.LocalizationValue(rawValue))
    }
}

@Model
final class Account {
    var id: UUID
    var name: String
    var type: AccountType
    var note: String
    var currencyCode: String
    var sortOrder: Int = 0
    /// Persisted as String to preserve Decimal precision (same pattern as Transaction.amountValue)
    var openingBalanceValue: String = "0"
    /// Annual interest rate percentage, e.g. "12.5" = 12.5% p.a. "0" means no interest.
    var interestRateValue: String = "0"

    var openingBalance: Decimal {
        get { Decimal(string: openingBalanceValue) ?? .zero }
        set { openingBalanceValue = (newValue as NSDecimalNumber).stringValue }
    }

    var interestRate: Decimal {
        get { Decimal(string: interestRateValue) ?? .zero }
        set { interestRateValue = (newValue as NSDecimalNumber).stringValue }
    }

    init(
        id: UUID = UUID(),
        name: String,
        type: AccountType,
        note: String = "",
        currencyCode: String = "KZT",
        sortOrder: Int = 0,
        openingBalance: Decimal = .zero,
        interestRate: Decimal = .zero
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.note = note
        self.currencyCode = currencyCode
        self.sortOrder = sortOrder
        self.openingBalanceValue = (openingBalance as NSDecimalNumber).stringValue
        self.interestRateValue = (interestRate as NSDecimalNumber).stringValue
    }
}

enum SupportedCurrency: String, CaseIterable {
    case KZT, USD, RUB, EUR

    var symbol: String {
        switch self {
        case .KZT: return "₸"
        case .USD: return "$"
        case .RUB: return "₽"
        case .EUR: return "€"
        }
    }

    var name: String {
        switch self {
        case .KZT: return "Тенге (₸)"
        case .USD: return "Доллар ($)"
        case .RUB: return "Рубль (₽)"
        case .EUR: return "Евро (€)"
        }
    }
}
