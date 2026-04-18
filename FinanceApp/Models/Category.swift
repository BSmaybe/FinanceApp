import Foundation
import SwiftData

enum CategoryType: String, Codable, CaseIterable {
    case income = "Income"
    case expense = "Expense"

    var localizedName: String {
        String(localized: String.LocalizationValue(rawValue))
    }
}

enum CategoryAdviceRole: String, Codable, CaseIterable {
    case essential
    case fixed
    case flexible
    case income

    var localizedName: String {
        switch self {
        case .essential:
            return String(localized: "Essential")
        case .fixed:
            return String(localized: "Fixed")
        case .flexible:
            return String(localized: "Flexible")
        case .income:
            return String(localized: "Income Flow")
        }
    }
}

@Model
final class Category {
    var id: UUID
    var name: String
    var type: CategoryType
    var colorHex: String
    var iconName: String
    var sortOrder: Int = 0
    var adviceRoleRaw: String = ""

    var adviceRole: CategoryAdviceRole {
        get {
            guard !adviceRoleRaw.isEmpty else {
                return Category.inferredAdviceRole(name: name, type: type)
            }
            return CategoryAdviceRole(rawValue: adviceRoleRaw) ?? Category.inferredAdviceRole(name: name, type: type)
        }
        set {
            adviceRoleRaw = newValue.rawValue
        }
    }

    init(
        id: UUID = UUID(),
        name: String,
        type: CategoryType,
        colorHex: String = "#888888",
        iconName: String = "folder",
        sortOrder: Int = 0,
        adviceRole: CategoryAdviceRole? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.colorHex = colorHex
        self.iconName = iconName
        self.sortOrder = sortOrder
        self.adviceRoleRaw = adviceRole?.rawValue ?? ""
    }

    static let availableIcons: [String] = [
        "cart", "car", "house", "fork.knife", "heart", "gamecontroller",
        "tshirt", "gift", "bus", "airplane", "music.note", "phone",
        "wifi", "drop", "bolt", "book", "graduationcap", "briefcase",
        "stethoscope", "pawprint", "dumbbell", "film", "ticket",
        "banknote", "creditcard", "bag", "cup.and.saucer", "pill",
        "fuelpump", "wrench", "scissors", "paintbrush", "camera",
        "tv", "desktopcomputer", "headphones", "bicycle", "figure.walk",
        "leaf", "star", "folder"
    ]

    static func inferredAdviceRole(name: String, type: CategoryType) -> CategoryAdviceRole {
        guard type != .income else { return .income }

        let normalized = name.adviceNormalized

        let essentialKeywords = [
            "food", "grocery", "grocer", "meal", "restaurant", "delivery",
            "еда", "продукт", "кафе", "ресторан", "доставка",
            "health", "medical", "medicine", "doctor",
            "мед", "аптек", "лекар", "врач",
            "transport", "taxi", "fuel", "bus", "metro",
            "транспорт", "такси", "бенз", "автобус", "метро"
        ]
        if essentialKeywords.contains(where: normalized.contains) {
            return .essential
        }

        let fixedKeywords = [
            "rent", "lease", "mortgage", "utility", "utilities",
            "internet", "phone", "electric", "water", "gas",
            "аренд", "ипотек", "коммун", "интернет", "связ", "свет", "вода", "газ"
        ]
        if fixedKeywords.contains(where: normalized.contains) {
            return .fixed
        }

        let flexibleKeywords = [
            "shopping", "entertain", "fun", "travel", "subscription", "stream",
            "spotify", "netflix", "game", "gift", "coffee",
            "покуп", "развлеч", "подпис", "игр", "подар", "кофе", "путеш"
        ]
        if flexibleKeywords.contains(where: normalized.contains) {
            return .flexible
        }

        return .flexible
    }
}

private extension String {
    var adviceNormalized: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }
}
