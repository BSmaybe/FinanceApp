import SwiftUI

struct DailyQuoteCardView: View {
    @AppStorage("quoteDismissedDate") private var quoteDismissedDate = ""
    @State private var isExpanded = false

    private let quote = DailyQuoteStore.today

    private var todayString: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }

    private var categoryEmoji: String {
        switch quote.category {
        case "anime": return "🍜"
        case "game":  return "🎮"
        default:      return "🎬"
        }
    }

    private var gradientColors: [Color] {
        switch quote.category {
        case "anime": return [Color(red: 0.55, green: 0.15, blue: 0.90), Color(red: 0.85, green: 0.25, blue: 0.55)]
        case "game":  return [Color(red: 0.05, green: 0.45, blue: 0.85), Color(red: 0.05, green: 0.70, blue: 0.65)]
        default:      return [Color(red: 0.90, green: 0.45, blue: 0.05), Color(red: 0.85, green: 0.20, blue: 0.35)]
        }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            cardContent
            dismissButton
        }
        .onTapGesture {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                isExpanded.toggle()
            }
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            categoryBadge
            quoteText
            if isExpanded {
                sourceText
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: gradientColors[0].opacity(0.3), radius: 12, x: 0, y: 6)
    }

    private var categoryBadge: some View {
        HStack(spacing: 6) {
            Text(categoryEmoji)
                .font(.caption)
            Text(categoryLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.white.opacity(0.18))
        .clipShape(Capsule())
    }

    private var categoryLabel: String {
        switch quote.category {
        case "anime": return String(localized: "Anime")
        case "game":  return String(localized: "Game")
        default:      return String(localized: "Movie")
        }
    }

    private var quoteText: some View {
        Text("\u{201C}" + quote.text + "\u{201D}")
            .font(.callout.weight(.medium))
            .italic()
            .foregroundStyle(.white)
            .lineLimit(isExpanded ? nil : 3)
            .multilineTextAlignment(.leading)
    }

    private var sourceText: some View {
        Text("— " + quote.source)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.75))
    }

    private var dismissButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) {
                quoteDismissedDate = todayString
            }
        } label: {
            Image(systemName: "xmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 26, height: 26)
                .background(.white.opacity(0.2))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .padding(10)
    }
}
