import Foundation
import SwiftUI

enum CurrencyFormatter {
    @MainActor static let shared: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = Locale.current
        return f
    }()

    @MainActor static func string(from decimal: Decimal) -> String {
        shared.string(from: decimal as NSDecimalNumber) ?? "\(decimal)"
    }

    @MainActor private static var formatterCache: [String: NumberFormatter] = [:]

    @MainActor static func string(from decimal: Decimal, currencyCode: String) -> String {
        let formatter: NumberFormatter
        if let cached = formatterCache[currencyCode] {
            formatter = cached
        } else {
            let f = NumberFormatter()
            f.numberStyle = .currency
            f.currencyCode = currencyCode
            formatterCache[currencyCode] = f
            formatter = f
        }
        return formatter.string(from: decimal as NSDecimalNumber) ?? "\(decimal)"
    }
}

extension Color {
    init(hex: String) {
        var hex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex = String(hex.dropFirst()) }

        let scanner = Scanner(string: hex)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)

        let r = Double((rgb >> 16) & 0xFF) / 255
        let g = Double((rgb >> 8) & 0xFF) / 255
        let b = Double(rgb & 0xFF) / 255

        self.init(red: r, green: g, blue: b)
    }

    func toHex() -> String {
        let uiColor = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
