import SwiftUI

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
