import Foundation

enum WidgetDataProvider {
    static let suiteName = "group.com.personal.financeappbilly"

    static func save(netWorth: Decimal, monthlyIncome: Decimal, monthlyExpense: Decimal) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        defaults.set((netWorth as NSDecimalNumber).stringValue, forKey: "netWorth")
        defaults.set((monthlyIncome as NSDecimalNumber).stringValue, forKey: "monthlyIncome")
        defaults.set((monthlyExpense as NSDecimalNumber).stringValue, forKey: "monthlyExpense")
        defaults.set(Date().timeIntervalSince1970, forKey: "lastUpdate")
    }

    static func load() -> (netWorth: Decimal, monthlyIncome: Decimal, monthlyExpense: Decimal, lastUpdate: Date) {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return (.zero, .zero, .zero, Date())
        }
        let nw = Decimal(string: defaults.string(forKey: "netWorth") ?? "0") ?? .zero
        let inc = Decimal(string: defaults.string(forKey: "monthlyIncome") ?? "0") ?? .zero
        let exp = Decimal(string: defaults.string(forKey: "monthlyExpense") ?? "0") ?? .zero
        let ts = defaults.double(forKey: "lastUpdate")
        return (nw, inc, exp, Date(timeIntervalSince1970: ts))
    }
}
