import SwiftUI

// MARK: - Model

private struct OnboardingPage {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
}

private let onboardingPages: [OnboardingPage] = [
    OnboardingPage(
        icon: "chart.line.uptrend.xyaxis.circle.fill",
        color: Color(red: 0.24, green: 0.48, blue: 0.98),
        title: String(localized: "Onboarding.Welcome.Title"),
        subtitle: String(localized: "Onboarding.Welcome.Subtitle")
    ),
    OnboardingPage(
        icon: "creditcard.fill",
        color: Color(red: 0.18, green: 0.72, blue: 0.56),
        title: String(localized: "Onboarding.Accounts.Title"),
        subtitle: String(localized: "Onboarding.Accounts.Subtitle")
    ),
    OnboardingPage(
        icon: "chart.bar.fill",
        color: Color(red: 0.92, green: 0.55, blue: 0.20),
        title: String(localized: "Onboarding.Budget.Title"),
        subtitle: String(localized: "Onboarding.Budget.Subtitle")
    ),
    OnboardingPage(
        icon: "flag.checkered.2.crossed",
        color: Color(red: 0.62, green: 0.35, blue: 0.95),
        title: String(localized: "Onboarding.Goals.Title"),
        subtitle: String(localized: "Onboarding.Goals.Subtitle")
    )
]

// MARK: - OnboardingView

struct OnboardingView: View {
    @Binding var isPresented: Bool
    @State private var currentPage = 0
    @State private var iconScale: CGFloat = 0
    @State private var textOpacity: Double = 0
    @State private var textOffset: CGFloat = 30
    @State private var bgOpacity: Double = 0
    @State private var buttonScale: CGFloat = 0.85
    @State private var isFinishing = false

    var body: some View {
        ZStack {
            // Background gradient that shifts per page
            backgroundLayer

            VStack(spacing: 0) {
                Spacer()

                // Icon
                iconLayer

                Spacer().frame(height: 40)

                // Text
                textLayer

                Spacer()

                // Dots + Button
                bottomLayer
                    .padding(.bottom, 52)
            }
        }
        .ignoresSafeArea()
        .opacity(bgOpacity)
        .onAppear { animateIn() }
    }

    // MARK: Background

    private var backgroundLayer: some View {
        let page = onboardingPages[currentPage]
        return ZStack {
            Color(red: 0.05, green: 0.07, blue: 0.12)
                .ignoresSafeArea()
            RadialGradient(
                colors: [page.color.opacity(0.35), .clear],
                center: .init(x: 0.5, y: 0.3),
                startRadius: 0,
                endRadius: 380
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.55), value: currentPage)
        }
    }

    // MARK: Icon

    private var iconLayer: some View {
        let page = onboardingPages[currentPage]
        return ZStack {
            Circle()
                .fill(page.color.opacity(0.18))
                .frame(width: 160, height: 160)
                .blur(radius: 20)
            Circle()
                .fill(page.color.opacity(0.12))
                .frame(width: 120, height: 120)
            Image(systemName: page.icon)
                .font(.system(size: 58, weight: .bold))
                .foregroundStyle(page.color)
        }
        .scaleEffect(iconScale)
        .animation(.spring(response: 0.55, dampingFraction: 0.65), value: currentPage)
    }

    // MARK: Text

    private var textLayer: some View {
        let page = onboardingPages[currentPage]
        return VStack(spacing: 14) {
            Text(page.title)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(page.subtitle)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 36)
        }
        .opacity(textOpacity)
        .offset(y: textOffset)
        .id(currentPage) // forces re-animate on page change
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        ))
    }

    // MARK: Bottom

    private var bottomLayer: some View {
        VStack(spacing: 28) {
            // Dots
            HStack(spacing: 8) {
                ForEach(0..<onboardingPages.count, id: \.self) { i in
                    Capsule()
                        .fill(i == currentPage ? .white : .white.opacity(0.3))
                        .frame(width: i == currentPage ? 24 : 8, height: 8)
                        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: currentPage)
                }
            }

            // Button
            Button(action: nextPage) {
                HStack(spacing: 10) {
                    Text(isLastPage
                         ? String(localized: "Get Started")
                         : String(localized: "Next"))
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Image(systemName: isLastPage ? "checkmark" : "arrow.right")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 220, height: 56)
                .background(
                    Capsule()
                        .fill(onboardingPages[currentPage].color)
                        .shadow(color: onboardingPages[currentPage].color.opacity(0.5), radius: 16, y: 6)
                )
            }
            .scaleEffect(buttonScale)
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.5)) {
                    buttonScale = 1.0
                }
            }
        }
    }

    // MARK: Helpers

    private var isLastPage: Bool { currentPage == onboardingPages.count - 1 }

    private func nextPage() {
        if isLastPage {
            finishOnboarding()
        } else {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                currentPage += 1
            }
            // Re-animate text for new page
            textOpacity = 0
            textOffset = 28
            withAnimation(.easeOut(duration: 0.42).delay(0.1)) {
                textOpacity = 1
                textOffset = 0
            }
        }
    }

    private func finishOnboarding() {
        guard !isFinishing else { return }
        isFinishing = true
        withAnimation(.easeInOut(duration: 0.45)) {
            bgOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            isPresented = false
        }
    }

    private func animateIn() {
        withAnimation(.easeIn(duration: 0.35)) { bgOpacity = 1 }
        withAnimation(.spring(response: 0.6, dampingFraction: 0.65).delay(0.25)) {
            iconScale = 1
        }
        withAnimation(.easeOut(duration: 0.45).delay(0.35)) {
            textOpacity = 1
            textOffset = 0
        }
    }
}
