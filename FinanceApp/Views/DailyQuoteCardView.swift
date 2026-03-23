import SwiftUI

// MARK: - DailyQuoteOverlayView
// Full-screen overlay that appears when the user opens the Dashboard each day.
// Dims everything behind it, dismisses with a beautiful animation on tap.

struct DailyQuoteOverlayView: View {
    let onDismiss: () -> Void

    private let quote = DailyQuoteStore.today

    @State private var backdropOpacity: Double = 0
    @State private var cardScale: CGFloat = 0.82
    @State private var cardOpacity: Double = 0
    @State private var textOffset: CGFloat = 16
    @State private var textOpacity: Double = 0

    var body: some View {
        ZStack {
            // Dimmed backdrop — tap to dismiss
            Color.black.opacity(0.65)
                .ignoresSafeArea()
                .opacity(backdropOpacity)
                .onTapGesture { dismiss() }

            VStack(spacing: 0) {
                Spacer()

                quoteCard
                    .scaleEffect(cardScale)
                    .opacity(cardOpacity)

                hintText
                    .offset(y: textOffset)
                    .opacity(textOpacity)

                Spacer()
            }
            .padding(.horizontal, 28)
        }
        .onAppear { animateIn() }
    }

    // MARK: - Quote Card

    private var quoteCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Category badge
            HStack(spacing: 6) {
                Text(categoryEmoji)
                    .font(.subheadline)
                Text(categoryLabel)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .textCase(.uppercase)
                    .tracking(0.8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(.white.opacity(0.2))
            .clipShape(Capsule())

            // Quote text
            Text("\u{201C}" + quote.localizedText + "\u{201D}")
                .font(.system(size: 20, weight: .semibold, design: .serif))
                .italic()
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .lineSpacing(4)

            // Source / attribution
            HStack(spacing: 0) {
                Rectangle()
                    .fill(.white.opacity(0.5))
                    .frame(width: 3, height: 38)
                    .clipShape(Capsule())
                Text(quote.source)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.leading)
                    .padding(.leading, 12)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: gradientColors[0].opacity(0.45), radius: 32, x: 0, y: 12)
    }

    private var hintText: some View {
        Text(String(localized: "Tap anywhere to continue"))
            .font(.caption)
            .foregroundStyle(.white.opacity(0.5))
            .padding(.top, 22)
    }

    // MARK: - Helpers

    private var categoryEmoji: String {
        switch quote.category {
        case "anime": return "🍜"
        case "game":  return "🎮"
        default:      return "🎬"
        }
    }

    private var categoryLabel: String {
        switch quote.category {
        case "anime": return String(localized: "Anime")
        case "game":  return String(localized: "Game")
        default:      return String(localized: "Movie")
        }
    }

    private var gradientColors: [Color] {
        switch quote.category {
        case "anime": return [Color(red: 0.55, green: 0.15, blue: 0.90), Color(red: 0.85, green: 0.25, blue: 0.55)]
        case "game":  return [Color(red: 0.05, green: 0.45, blue: 0.85), Color(red: 0.05, green: 0.70, blue: 0.65)]
        default:      return [Color(red: 0.80, green: 0.35, blue: 0.05), Color(red: 0.75, green: 0.15, blue: 0.45)]
        }
    }

    // MARK: - Animations

    private func animateIn() {
        withAnimation(.easeOut(duration: 0.25)) {
            backdropOpacity = 1
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.72).delay(0.08)) {
            cardScale = 1.0
            cardOpacity = 1
        }
        withAnimation(.easeOut(duration: 0.4).delay(0.28)) {
            textOffset = 0
            textOpacity = 1
        }
    }

    private func dismiss() {
        withAnimation(.easeIn(duration: 0.22)) {
            cardScale = 0.88
            cardOpacity = 0
            backdropOpacity = 0
            textOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            onDismiss()
        }
    }
}
