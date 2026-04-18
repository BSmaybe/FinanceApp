import SwiftUI

// MARK: - AchievementToastView
// Slides up from the bottom when a new achievement is unlocked.
// Usage: .overlay(alignment: .bottom) { if let a = achievement { AchievementToastView(achievement: a) { achievement = nil } } }

struct AchievementToastView: View {
    let achievement: Achievement
    let onDismiss: () -> Void

    @State private var offsetY: CGFloat = 120
    @State private var opacity: Double = 0

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: achievement.symbolName)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color(red: 0.86, green: 0.63, blue: 0.12))
                .frame(width: 52, height: 52)
                .background(
                    LinearGradient(
                        colors: [Color(red: 1.0, green: 0.78, blue: 0.0).opacity(0.25),
                                 Color(red: 1.0, green: 0.55, blue: 0.0).opacity(0.15)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .clipShape(Circle())
                .overlay(Circle().stroke(Color(red: 1.0, green: 0.78, blue: 0.0).opacity(0.5), lineWidth: 1.5))

            VStack(alignment: .leading, spacing: 3) {
                Text(String(localized: "Milestone recorded"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.0))
                Text(achievement.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                Text(achievement.description)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "xmark")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(6)
                .onTapGesture { dismissToast() }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color(red: 1.0, green: 0.78, blue: 0.0).opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
        .offset(y: offsetY)
        .opacity(opacity)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .onAppear { animateIn() }
        .onTapGesture { dismissToast() }
    }

    private func animateIn() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) {
            offsetY = 0
            opacity = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { dismissToast() }
    }

    private func dismissToast() {
        withAnimation(.easeIn(duration: 0.3)) {
            offsetY = 120
            opacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onDismiss() }
    }
}

// MARK: - LevelUpOverlayView
// Full-screen celebration when the player levels up.
// Usage: .overlay { if showLevelUp { LevelUpOverlayView(level: n, title: "...") { showLevelUp = false } } }

struct LevelUpOverlayView: View {
    let level: Int
    let title: String
    let onDismiss: () -> Void

    @State private var backdropOpacity: Double = 0
    @State private var ringScale: CGFloat = 0.2
    @State private var ringOpacity: Double = 0
    @State private var levelScale: CGFloat = 0.3
    @State private var levelOpacity: Double = 0
    @State private var textOffset: CGFloat = 20
    @State private var textOpacity: Double = 0
    @State private var starOffsets: [CGSize] = Array(repeating: .zero, count: 12)
    @State private var starOpacity: Double = 0
    @State private var starScales: [CGFloat] = Array(repeating: 0.3, count: 12)

    private let gold = Color(red: 1.0, green: 0.78, blue: 0.0)
    private let starAngles: [Double] = stride(from: 0, to: 360, by: 30).map { $0 }
    private let starDist: CGFloat = 110
    private let starColors: [Color] = [
        .yellow, .orange, .yellow, Color(red: 1.0, green: 0.78, blue: 0.0),
        .white, .yellow, .orange, .yellow,
        Color(red: 1.0, green: 0.78, blue: 0.0), .white, .yellow, .orange
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(backdropOpacity * 0.6)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 16) {
                ZStack {
                    // Star particles
                    ForEach(0..<12, id: \.self) { i in
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(starColors[i])
                            .scaleEffect(starScales[i])
                            .offset(starOffsets[i])
                            .opacity(starOpacity)
                    }

                    // Glow ring
                    Circle()
                        .fill(gold.opacity(0.15))
                        .frame(width: 160, height: 160)
                        .scaleEffect(ringScale)
                        .opacity(ringOpacity)

                    Circle()
                        .stroke(
                            LinearGradient(colors: [gold, gold.opacity(0.3), gold],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 3
                        )
                        .frame(width: 130, height: 130)
                        .scaleEffect(ringScale)
                        .opacity(ringOpacity)

                    // Level number
                    VStack(spacing: 2) {
                        Image(systemName: "star.fill")
                            .font(.title2)
                            .foregroundStyle(gold)
                        Text("\(level)")
                            .font(.system(size: 52, weight: .black, design: .rounded))
                            .foregroundStyle(gold)
                            .shadow(color: gold.opacity(0.6), radius: 12)
                    }
                    .scaleEffect(levelScale)
                    .opacity(levelOpacity)
                }
                .frame(width: 200, height: 200)

                VStack(spacing: 8) {
                    Text(String(localized: "Level Up!"))
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(gold)
                    Text(String(localized: "Tap to continue"))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.top, 4)
                }
                .offset(y: textOffset)
                .opacity(textOpacity)
            }
        }
        .onAppear { animateIn() }
    }

    private func animateIn() {
        withAnimation(.easeOut(duration: 0.25)) { backdropOpacity = 1 }

        withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.1)) {
            ringScale = 1
            ringOpacity = 1
        }

        withAnimation(.spring(response: 0.45, dampingFraction: 0.5).delay(0.15)) {
            levelScale = 1
            levelOpacity = 1
        }

        withAnimation(.easeOut(duration: 0.55).delay(0.25)) {
            starOpacity = 1
            for i in 0..<12 {
                let angle = starAngles[i] * .pi / 180
                starOffsets[i] = CGSize(
                    width: cos(angle) * starDist,
                    height: sin(angle) * starDist
                )
                starScales[i] = 1
            }
        }
        withAnimation(.easeIn(duration: 0.4).delay(0.75)) { starOpacity = 0 }

        withAnimation(.easeOut(duration: 0.4).delay(0.3)) {
            textOpacity = 1
            textOffset = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { dismiss() }
    }

    private func dismiss() {
        withAnimation(.easeIn(duration: 0.3)) {
            backdropOpacity = 0
            levelOpacity = 0
            textOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onDismiss() }
    }
}

// MARK: - SuccessOverlayView
// Shows an animated checkmark + sparkles when a goal is reached or a debt is paid off.
// Usage:  .overlay { if showSuccess { SuccessOverlayView(message: "...", subtitle: "...") { showSuccess = false } } }

struct SuccessOverlayView: View {
    let message: String
    let subtitle: String
    let onDismiss: () -> Void

    @State private var scale: CGFloat = 0.3
    @State private var opacity: Double = 0
    @State private var checkScale: CGFloat = 0
    @State private var textOffset: CGFloat = 18
    @State private var textOpacity: Double = 0
    @State private var sparkOffsets: [CGSize] = Array(repeating: .zero, count: 8)
    @State private var sparkOpacity: Double = 0

    // Sparkle directions (8 evenly spread)
    private let sparkAngles: [Double] = stride(from: 0, to: 360, by: 45).map { $0 }
    private let sparkColors: [Color] = [
        .yellow, .orange, AppTheme.success, AppTheme.primaryAccent,
        .pink, .purple, .cyan, .mint
    ]
    private let sparkDistance: CGFloat = 90

    var body: some View {
        ZStack {
            // Dim backdrop — tap to dismiss
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 20) {
                // Sparkles + checkmark
                ZStack {
                    // Sparkle particles
                    ForEach(0..<8, id: \.self) { i in
                        Circle()
                            .fill(sparkColors[i])
                            .frame(width: 10, height: 10)
                            .offset(sparkOffsets[i])
                            .opacity(sparkOpacity)
                    }

                    // Outer glow ring
                    Circle()
                        .fill(AppTheme.success.opacity(0.25))
                        .frame(width: 120, height: 120)
                        .scaleEffect(scale * 1.3)

                    // Main circle
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [AppTheme.success, AppTheme.success.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 90, height: 90)
                        .shadow(color: AppTheme.success.opacity(0.5), radius: 18, y: 6)
                        .scaleEffect(checkScale)

                    // Checkmark
                    Image(systemName: "checkmark")
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(.white)
                        .scaleEffect(checkScale)
                }
                .frame(width: 150, height: 150)

                // Text
                VStack(spacing: 6) {
                    Text(message)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                }
                .offset(y: textOffset)
                .opacity(textOpacity)
                .padding(.horizontal, 32)
            }
            .opacity(opacity)
        }
        .onAppear { animateIn() }
        .onDisappear { }
    }

    // MARK: - Animations

    private func animateIn() {
        // Backdrop
        withAnimation(.easeOut(duration: 0.2)) { opacity = 1 }

        // Checkmark circle — spring pop
        withAnimation(.spring(response: 0.45, dampingFraction: 0.55).delay(0.1)) {
            checkScale = 1
            scale = 1
        }

        // Sparkles fly outward
        withAnimation(.easeOut(duration: 0.6).delay(0.2)) {
            sparkOpacity = 1
            for i in 0..<8 {
                let angle = sparkAngles[i] * .pi / 180
                sparkOffsets[i] = CGSize(
                    width: cos(angle) * sparkDistance,
                    height: sin(angle) * sparkDistance
                )
            }
        }
        // Sparkles fade out
        withAnimation(.easeIn(duration: 0.45).delay(0.6)) {
            sparkOpacity = 0
        }

        // Text slides up
        withAnimation(.easeOut(duration: 0.4).delay(0.3)) {
            textOpacity = 1
            textOffset = 0
        }

        // Auto-dismiss after 2.8s
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
            dismiss()
        }
    }

    private func dismiss() {
        withAnimation(.easeIn(duration: 0.25)) {
            opacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            onDismiss()
        }
    }
}
