import Foundation
import SwiftData

enum SeedData {
    static let seededKey = "didSeedInitialData"
    static let seededV2Key = "didSeedV2Categories"

    static func seedIfNeeded(context: ModelContext) {
        if !UserDefaults.standard.bool(forKey: seededKey) {
            // Seed account
            let cashAccount = Account(name: "Наличные", type: .cash)
            context.insert(cashAccount)

            // Seed expense categories
            let expenseCategories: [(String, String)] = [
                ("Еда", "#FF6B6B"),
                ("Транспорт", "#4ECDC4"),
                ("Жильё", "#45B7D1"),
                ("Здоровье", "#96CEB4"),
                ("Развлечения", "#FFEAA7"),
                ("Рассрочки", "#E17055"),
                ("Кредиты", "#6C5CE7"),
                ("Прочее", "#DDA0DD")
            ]
            for (name, color) in expenseCategories {
                context.insert(Category(name: name, type: .expense, colorHex: color))
            }

            // Seed income categories
            let incomeCategories: [(String, String)] = [
                ("Зарплата", "#2ECC71"),
                ("Фриланс", "#27AE60"),
                ("Прочие доходы", "#1ABC9C")
            ]
            for (name, color) in incomeCategories {
                context.insert(Category(name: name, type: .income, colorHex: color))
            }

            try? context.save()
            UserDefaults.standard.set(true, forKey: seededKey)
        }

        // V2: add installment/credit categories to existing installs
        if !UserDefaults.standard.bool(forKey: seededV2Key) {
            let existing = (try? context.fetch(FetchDescriptor<Category>())) ?? []
            let existingNames = Set(existing.filter { $0.type == .expense }.map { $0.name })

            let newCategories: [(String, String)] = [
                ("Рассрочки", "#E17055"),
                ("Кредиты", "#6C5CE7")
            ]
            for (name, color) in newCategories where !existingNames.contains(name) {
                context.insert(Category(name: name, type: .expense, colorHex: color))
            }

            try? context.save()
            UserDefaults.standard.set(true, forKey: seededV2Key)
        }
    }
}
