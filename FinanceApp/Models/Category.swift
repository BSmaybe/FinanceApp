import Foundation
import SwiftData

enum CategoryType: String, Codable, CaseIterable {
    case income = "Income"
    case expense = "Expense"

    var localizedName: String {
        String(localized: String.LocalizationValue(rawValue))
    }
}

@Model
final class Category {
    var id: UUID
    var name: String
    var type: CategoryType
    var colorHex: String
    var iconName: String

    init(id: UUID = UUID(), name: String, type: CategoryType, colorHex: String = "#888888", iconName: String = "folder") {
        self.id = id
        self.name = name
        self.type = type
        self.colorHex = colorHex
        self.iconName = iconName
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
}
