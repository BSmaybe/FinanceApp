import SwiftUI

// MARK: - ThemePalette

struct ThemePalette {
    let id: String
    let name: String
    let isDark: Bool

    let canvas: Color
    let surface: Color
    let outline: Color

    let primaryAccent: Color
    let secondaryAccent: Color
    let danger: Color
    let success: Color

    let heroCardTitle: Color
    let heroCardLabel: Color

    let heroGradient: LinearGradient
    let incomeGradient: LinearGradient
    let expenseGradient: LinearGradient
    let debtGradient: LinearGradient
    let subscriptionGradient: LinearGradient
    let fabGradient: LinearGradient

    let timelineLine: Color
    let timelineDot: Color
}

// MARK: - Presets

extension ThemePalette {

    // 1. Finance Blue — синий + зелёный, холодный серо-голубой фон
    static let financeBlue = ThemePalette(
        id: "finance_blue",
        name: String(localized: "Finance Blue"),
        isDark: false,
        canvas: Color(hex: "#F0F4FA"),
        surface: .white,
        outline: Color(hex: "#CBD5E1"),
        primaryAccent: Color(hex: "#2563EB"),
        secondaryAccent: Color(hex: "#16A34A"),
        danger: Color(hex: "#DC2626"),
        success: Color(hex: "#16A34A"),
        heroCardTitle: Color(hex: "#1E3A5F"),
        heroCardLabel: Color(hex: "#2563EB"),
        heroGradient: LinearGradient(
            colors: [Color(hex: "#EBF2FF"), Color(hex: "#E8E0FF")],
            startPoint: .topLeading, endPoint: .bottomTrailing
        ),
        incomeGradient: LinearGradient(
            colors: [.green.opacity(0.18), .mint.opacity(0.10)],
            startPoint: .leading, endPoint: .trailing
        ),
        expenseGradient: LinearGradient(
            colors: [.red.opacity(0.18), .orange.opacity(0.10)],
            startPoint: .leading, endPoint: .trailing
        ),
        debtGradient: LinearGradient(
            colors: [Color(hex: "#FEE2E2"), Color(hex: "#FFF7ED")],
            startPoint: .topLeading, endPoint: .bottomTrailing
        ),
        subscriptionGradient: LinearGradient(
            colors: [Color(hex: "#EDE9FE"), Color(hex: "#E0F2FE")],
            startPoint: .topLeading, endPoint: .bottomTrailing
        ),
        fabGradient: LinearGradient(
            colors: [Color(hex: "#2563EB"), Color(hex: "#7C3AED")],
            startPoint: .topLeading, endPoint: .bottomTrailing
        ),
        timelineLine: Color(hex: "#CBD5E1"),
        timelineDot: Color(hex: "#2563EB")
    )

    // 2. Midnight Green — изумруд + золото
    static let midnightGreen = ThemePalette(
        id: "midnight_green",
        name: String(localized: "Midnight Green"),
        isDark: false,
        canvas: Color(hex: "#F0FDF4"),
        surface: .white,
        outline: Color(hex: "#BBF7D0"),
        primaryAccent: Color(hex: "#065F46"),
        secondaryAccent: Color(hex: "#D97706"),
        danger: Color(hex: "#DC2626"),
        success: Color(hex: "#065F46"),
        heroCardTitle: Color(hex: "#064E3B"),
        heroCardLabel: Color(hex: "#065F46"),
        heroGradient: LinearGradient(
            colors: [Color(hex: "#ECFDF5"), Color(hex: "#D1FAE5")],
            startPoint: .topLeading, endPoint: .bottomTrailing
        ),
        incomeGradient: LinearGradient(
            colors: [.green.opacity(0.20), .mint.opacity(0.12)],
            startPoint: .leading, endPoint: .trailing
        ),
        expenseGradient: LinearGradient(
            colors: [.red.opacity(0.18), .orange.opacity(0.10)],
            startPoint: .leading, endPoint: .trailing
        ),
        debtGradient: LinearGradient(
            colors: [Color(hex: "#FEE2E2"), Color(hex: "#FFF3C4")],
            startPoint: .topLeading, endPoint: .bottomTrailing
        ),
        subscriptionGradient: LinearGradient(
            colors: [Color(hex: "#D1FAE5"), Color(hex: "#FEF3C7")],
            startPoint: .topLeading, endPoint: .bottomTrailing
        ),
        fabGradient: LinearGradient(
            colors: [Color(hex: "#065F46"), Color(hex: "#047857")],
            startPoint: .topLeading, endPoint: .bottomTrailing
        ),
        timelineLine: Color(hex: "#BBF7D0"),
        timelineDot: Color(hex: "#065F46")
    )

    // 3. Sunset — оранжевый + фиолетовый, тёплый кремовый фон
    static let sunset = ThemePalette(
        id: "sunset",
        name: String(localized: "Sunset"),
        isDark: false,
        canvas: Color(hex: "#FFF8F0"),
        surface: .white,
        outline: Color(hex: "#FED7AA"),
        primaryAccent: Color(hex: "#EA580C"),
        secondaryAccent: Color(hex: "#7C3AED"),
        danger: Color(hex: "#DC2626"),
        success: Color(hex: "#16A34A"),
        heroCardTitle: Color(hex: "#7C2D12"),
        heroCardLabel: Color(hex: "#EA580C"),
        heroGradient: LinearGradient(
            colors: [Color(hex: "#FFF7ED"), Color(hex: "#FEE2D5")],
            startPoint: .topLeading, endPoint: .bottomTrailing
        ),
        incomeGradient: LinearGradient(
            colors: [.green.opacity(0.18), .mint.opacity(0.10)],
            startPoint: .leading, endPoint: .trailing
        ),
        expenseGradient: LinearGradient(
            colors: [.orange.opacity(0.22), .red.opacity(0.12)],
            startPoint: .leading, endPoint: .trailing
        ),
        debtGradient: LinearGradient(
            colors: [Color(hex: "#FEE2E2"), Color(hex: "#FFF7ED")],
            startPoint: .topLeading, endPoint: .bottomTrailing
        ),
        subscriptionGradient: LinearGradient(
            colors: [Color(hex: "#EDE9FE"), Color(hex: "#FFF7ED")],
            startPoint: .topLeading, endPoint: .bottomTrailing
        ),
        fabGradient: LinearGradient(
            colors: [Color(hex: "#EA580C"), Color(hex: "#DC2626")],
            startPoint: .topLeading, endPoint: .bottomTrailing
        ),
        timelineLine: Color(hex: "#FED7AA"),
        timelineDot: Color(hex: "#EA580C")
    )

    // 4. Lavender — фиолетовый + розовый
    static let lavender = ThemePalette(
        id: "lavender",
        name: String(localized: "Lavender"),
        isDark: false,
        canvas: Color(hex: "#FAF5FF"),
        surface: .white,
        outline: Color(hex: "#DDD6FE"),
        primaryAccent: Color(hex: "#7C3AED"),
        secondaryAccent: Color(hex: "#DB2777"),
        danger: Color(hex: "#DC2626"),
        success: Color(hex: "#16A34A"),
        heroCardTitle: Color(hex: "#4C1D95"),
        heroCardLabel: Color(hex: "#7C3AED"),
        heroGradient: LinearGradient(
            colors: [Color(hex: "#F5F3FF"), Color(hex: "#FCE7F3")],
            startPoint: .topLeading, endPoint: .bottomTrailing
        ),
        incomeGradient: LinearGradient(
            colors: [.green.opacity(0.18), .mint.opacity(0.10)],
            startPoint: .leading, endPoint: .trailing
        ),
        expenseGradient: LinearGradient(
            colors: [.red.opacity(0.18), .orange.opacity(0.10)],
            startPoint: .leading, endPoint: .trailing
        ),
        debtGradient: LinearGradient(
            colors: [Color(hex: "#FEE2E2"), Color(hex: "#FDF2F8")],
            startPoint: .topLeading, endPoint: .bottomTrailing
        ),
        subscriptionGradient: LinearGradient(
            colors: [Color(hex: "#EDE9FE"), Color(hex: "#FDF2F8")],
            startPoint: .topLeading, endPoint: .bottomTrailing
        ),
        fabGradient: LinearGradient(
            colors: [Color(hex: "#7C3AED"), Color(hex: "#DB2777")],
            startPoint: .topLeading, endPoint: .bottomTrailing
        ),
        timelineLine: Color(hex: "#DDD6FE"),
        timelineDot: Color(hex: "#7C3AED")
    )

    // 5. Midnight — тёмная тема, синие акценты на угольном фоне
    static let midnight = ThemePalette(
        id: "midnight",
        name: String(localized: "Midnight"),
        isDark: true,
        canvas: Color(hex: "#0F172A"),
        surface: Color(hex: "#1E293B"),
        outline: Color(hex: "#334155"),
        primaryAccent: Color(hex: "#60A5FA"),
        secondaryAccent: Color(hex: "#34D399"),
        danger: Color(hex: "#F87171"),
        success: Color(hex: "#34D399"),
        heroCardTitle: Color(hex: "#E2E8F0"),
        heroCardLabel: Color(hex: "#60A5FA"),
        heroGradient: LinearGradient(
            colors: [Color(hex: "#1E293B"), Color(hex: "#1E1B4B")],
            startPoint: .topLeading, endPoint: .bottomTrailing
        ),
        incomeGradient: LinearGradient(
            colors: [Color(hex: "#34D399").opacity(0.25), Color(hex: "#6EE7B7").opacity(0.12)],
            startPoint: .leading, endPoint: .trailing
        ),
        expenseGradient: LinearGradient(
            colors: [Color(hex: "#F87171").opacity(0.25), Color(hex: "#FCA5A5").opacity(0.12)],
            startPoint: .leading, endPoint: .trailing
        ),
        debtGradient: LinearGradient(
            colors: [Color(hex: "#450A0A"), Color(hex: "#431407")],
            startPoint: .topLeading, endPoint: .bottomTrailing
        ),
        subscriptionGradient: LinearGradient(
            colors: [Color(hex: "#2E1065"), Color(hex: "#1E1B4B")],
            startPoint: .topLeading, endPoint: .bottomTrailing
        ),
        fabGradient: LinearGradient(
            colors: [Color(hex: "#3B82F6"), Color(hex: "#6D28D9")],
            startPoint: .topLeading, endPoint: .bottomTrailing
        ),
        timelineLine: Color(hex: "#334155"),
        timelineDot: Color(hex: "#60A5FA")
    )

    // 6. Warm Minimal — cream canvas, near-black accent, green signals
    static let warmMinimal = ThemePalette(
        id: "warm_minimal",
        name: String(localized: "Warm Minimal"),
        isDark: false,
        canvas: Color(hex: "#F5F3EF"),
        surface: .white,
        outline: Color(hex: "#E5E2DC"),
        primaryAccent: Color(hex: "#1A1A1A"),
        secondaryAccent: Color(hex: "#22C55E"),
        danger: Color(hex: "#EF4444"),
        success: Color(hex: "#22C55E"),
        heroCardTitle: Color(hex: "#111111"),
        heroCardLabel: Color(hex: "#6B7280"),
        heroGradient: LinearGradient(
            colors: [Color(hex: "#FFFFFF"), Color(hex: "#F0EDE8")],
            startPoint: .topLeading, endPoint: .bottomTrailing
        ),
        incomeGradient: LinearGradient(
            colors: [.green.opacity(0.12), .mint.opacity(0.06)],
            startPoint: .leading, endPoint: .trailing
        ),
        expenseGradient: LinearGradient(
            colors: [.red.opacity(0.12), .orange.opacity(0.06)],
            startPoint: .leading, endPoint: .trailing
        ),
        debtGradient: LinearGradient(
            colors: [Color(hex: "#FEE2E2"), Color(hex: "#FFF7ED")],
            startPoint: .topLeading, endPoint: .bottomTrailing
        ),
        subscriptionGradient: LinearGradient(
            colors: [Color(hex: "#F3F4F6"), Color(hex: "#F5F3EF")],
            startPoint: .topLeading, endPoint: .bottomTrailing
        ),
        fabGradient: LinearGradient(
            colors: [Color(hex: "#1A1A1A"), Color(hex: "#374151")],
            startPoint: .topLeading, endPoint: .bottomTrailing
        ),
        timelineLine: Color(hex: "#E5E2DC"),
        timelineDot: Color(hex: "#1A1A1A")
    )

    static let all: [String: ThemePalette] = [
        financeBlue.id:    .financeBlue,
        midnightGreen.id:  .midnightGreen,
        sunset.id:         .sunset,
        lavender.id:       .lavender,
        midnight.id:       .midnight,
        warmMinimal.id:    .warmMinimal,
    ]

    static let allCases: [ThemePalette] = [.warmMinimal, .financeBlue, .midnightGreen, .sunset, .lavender, .midnight]

    var surfaceMuted: Color {
        switch id {
        case "warm_minimal":   return Color(hex: "#F0EDE8")
        case "finance_blue":   return Color(hex: "#F8FAFD")
        case "midnight_green": return Color(hex: "#F6FCF8")
        case "sunset":         return Color(hex: "#FFF7EF")
        case "lavender":       return Color(hex: "#FCF8FF")
        case "midnight":       return Color(hex: "#162033")
        default: return surface
        }
    }

    var surfaceElevated: Color {
        switch id {
        case "warm_minimal":   return Color(hex: "#FFFFFF")
        case "finance_blue":   return Color(hex: "#FFFFFF")
        case "midnight_green": return Color(hex: "#FFFFFF")
        case "sunset":         return Color(hex: "#FFFFFF")
        case "lavender":       return Color(hex: "#FFFFFF")
        case "midnight":       return Color(hex: "#1B2840")
        default: return surface
        }
    }

    var glassOverlay: Color {
        isDark ? Color.white.opacity(0.08) : Color.white.opacity(0.60)
    }

    var warning: Color {
        isDark ? Color(hex: "#FBBF24") : Color(hex: "#D97706")
    }

    var info: Color {
        isDark ? Color(hex: "#38BDF8") : Color(hex: "#0284C7")
    }

    var shadowSoft: Color {
        isDark ? Color.black.opacity(0.22) : Color(hex: "#0F172A").opacity(0.08)
    }

    var shadowStrong: Color {
        isDark ? Color.black.opacity(0.36) : Color(hex: "#0F172A").opacity(0.16)
    }

    var chartNeutral: Color {
        isDark ? Color(hex: "#64748B") : Color(hex: "#94A3B8")
    }

    var sectionAccent: Color {
        isDark ? secondaryAccent.opacity(0.9) : secondaryAccent.opacity(0.72)
    }
}

// MARK: - ThemeStore

final class ThemeStore: ObservableObject {
    static let shared = ThemeStore()

    @AppStorage("selectedTheme") var selectedTheme: String = "warm_minimal" {
        didSet { objectWillChange.send() }
    }

    var palette: ThemePalette {
        ThemePalette.all[selectedTheme] ?? .financeBlue
    }
}
