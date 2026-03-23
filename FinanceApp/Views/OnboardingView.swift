import SwiftUI

// MARK: - Feature Item

private struct FeatureItem {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    let key: String
}

private let allFeatures: [FeatureItem] = [
    FeatureItem(
        icon: "arrow.up.arrow.down.circle.fill",
        color: Color(red: 0.18, green: 0.72, blue: 0.56),
        title: String(localized: "Income & Expenses"),
        subtitle: String(localized: "Log daily money flow"),
        key: "feature.transactions"
    ),
    FeatureItem(
        icon: "chart.bar.fill",
        color: Color(red: 0.24, green: 0.48, blue: 0.98),
        title: String(localized: "Analytics"),
        subtitle: String(localized: "Charts and spending insights"),
        key: "feature.analytics"
    ),
    FeatureItem(
        icon: "gauge.with.needle.fill",
        color: Color(red: 0.92, green: 0.55, blue: 0.20),
        title: String(localized: "Budgets"),
        subtitle: String(localized: "Monthly category limits"),
        key: "feature.budgets"
    ),
    FeatureItem(
        icon: "target",
        color: Color(red: 0.62, green: 0.35, blue: 0.95),
        title: String(localized: "Savings Goals"),
        subtitle: String(localized: "Track progress to targets"),
        key: "feature.goals"
    ),
    FeatureItem(
        icon: "creditcard.fill",
        color: Color(red: 0.90, green: 0.28, blue: 0.30),
        title: String(localized: "Debts & Subscriptions"),
        subtitle: String(localized: "Loans and recurring bills"),
        key: "feature.debts"
    )
]

// MARK: - OnboardingView

struct OnboardingView: View {
    @Binding var isPresented: Bool

    // Page: 0 = Welcome, 1 = Questionnaire, 2 = Demo
    @State private var currentPage = 0
    @State private var bgOpacity: Double = 0
    @State private var isFinishing = false

    // Welcome slide animations
    @State private var iconScale: CGFloat = 0
    @State private var textOpacity: Double = 0
    @State private var textOffset: CGFloat = 30
    @State private var buttonScale: CGFloat = 0.85

    // Feature selections (all on by default)
    @State private var selected: [Bool] = Array(repeating: true, count: allFeatures.count)

    // Demo slide reveal counter
    @State private var revealedCount = 0

    var body: some View {
        ZStack {
            backgroundLayer
            VStack(spacing: 0) {
                Spacer()
                pageContent
                Spacer()
                bottomLayer
                    .padding(.bottom, 52)
            }
        }
        .ignoresSafeArea()
        .opacity(bgOpacity)
        .onAppear { animateIn() }
    }

    // MARK: - Background

    private var backgroundLayer: some View {
        ZStack {
            Color(red: 0.05, green: 0.07, blue: 0.12)
                .ignoresSafeArea()
            RadialGradient(
                colors: [accentColor.opacity(0.30), .clear],
                center: .init(x: 0.5, y: 0.3),
                startRadius: 0,
                endRadius: 400
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.55), value: currentPage)
        }
    }

    private var accentColor: Color {
        switch currentPage {
        case 0: return Color(red: 0.24, green: 0.48, blue: 0.98)
        case 1: return Color(red: 0.62, green: 0.35, blue: 0.95)
        default: return Color(red: 0.18, green: 0.72, blue: 0.56)
        }
    }

    // MARK: - Page Content

    @ViewBuilder
    private var pageContent: some View {
        switch currentPage {
        case 0:  welcomePage
        case 1:  questionnairePage
        default: demoPage
        }
    }

    // MARK: - Welcome Page

    private var welcomePage: some View {
        let blue = Color(red: 0.24, green: 0.48, blue: 0.98)
        return VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(blue.opacity(0.18))
                    .frame(width: 160, height: 160)
                    .blur(radius: 20)
                Circle()
                    .fill(blue.opacity(0.12))
                    .frame(width: 120, height: 120)
                Image(systemName: "chart.line.uptrend.xyaxis.circle.fill")
                    .font(.system(size: 58, weight: .bold))
                    .foregroundStyle(blue)
            }
            .scaleEffect(iconScale)

            Spacer().frame(height: 40)

            VStack(spacing: 14) {
                Text(String(localized: "Onboarding.Welcome.Title"))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text(String(localized: "Onboarding.Welcome.Subtitle"))
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 36)
            }
            .opacity(textOpacity)
            .offset(y: textOffset)
        }
    }

    // MARK: - Questionnaire Page

    private var questionnairePage: some View {
        VStack(spacing: 20) {
            VStack(spacing: 10) {
                Text(String(localized: "What do you need?"))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text(String(localized: "Select all that apply — change anytime in Settings"))
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.white.opacity(0.60))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            VStack(spacing: 10) {
                alwaysOnRow
                ForEach(allFeatures.indices, id: \.self) { i in
                    featureToggleRow(index: i)
                }
            }
            .padding(.horizontal, 24)
        }
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        ))
    }

    private var alwaysOnRow: some View {
        let gold = Color(red: 0.92, green: 0.75, blue: 0.20)
        return HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(gold.opacity(0.20))
                    .frame(width: 40, height: 40)
                Image(systemName: "creditcard.and.123")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(gold)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Accounts & Balances"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text(String(localized: "Always enabled"))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.40))
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(gold)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(0.07))
        )
    }

    private func featureToggleRow(index: Int) -> some View {
        let feature = allFeatures[index]
        let isOn = selected[index]
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selected[index].toggle()
            }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(feature.color.opacity(isOn ? 0.22 : 0.08))
                        .frame(width: 40, height: 40)
                    Image(systemName: feature.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isOn ? feature.color : feature.color.opacity(0.35))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(feature.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isOn ? .white : .white.opacity(0.40))
                    Text(feature.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(isOn ? 0.50 : 0.25))
                }
                Spacer()
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isOn ? feature.color : .white.opacity(0.22))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white.opacity(isOn ? 0.09 : 0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(isOn ? feature.color.opacity(0.35) : .clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Demo Page

    private var demoPage: some View {
        VStack(spacing: 20) {
            let green = Color(red: 0.18, green: 0.72, blue: 0.56)
            VStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 52, weight: .bold))
                    .foregroundStyle(green)
                    .scaleEffect(revealedCount > 0 ? 1.0 : 0.4)
                    .animation(.spring(response: 0.5, dampingFraction: 0.65), value: revealedCount > 0)

                Text(String(localized: "Your app is ready"))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(String(localized: "Here's what we've set up for you"))
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.60))
                    .padding(.horizontal, 32)
            }
            .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 12) {
                demoRow(
                    icon: "creditcard.and.123",
                    color: Color(red: 0.92, green: 0.75, blue: 0.20),
                    title: String(localized: "Accounts & Balances"),
                    visible: revealedCount >= 1
                )
                ForEach(selectedFeatureIndices.indices, id: \.self) { pos in
                    let i = selectedFeatureIndices[pos]
                    demoRow(
                        icon: allFeatures[i].icon,
                        color: allFeatures[i].color,
                        title: allFeatures[i].title,
                        visible: revealedCount >= pos + 2
                    )
                }
            }
            .padding(.horizontal, 48)
        }
        .onAppear { startDemoReveal() }
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        ))
    }

    private func demoRow(icon: String, color: Color, title: String, visible: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 28)
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
            Spacer()
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(color)
        }
        .opacity(visible ? 1 : 0)
        .offset(x: visible ? 0 : -24)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: visible)
    }

    private var selectedFeatureIndices: [Int] {
        allFeatures.indices.filter { selected[$0] }
    }

    private func startDemoReveal() {
        revealedCount = 0
        let total = 1 + selectedFeatureIndices.count
        for i in 0..<total {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12 + Double(i) * 0.15) {
                withAnimation { revealedCount = i + 1 }
            }
        }
    }

    // MARK: - Bottom Bar

    private var bottomLayer: some View {
        VStack(spacing: 28) {
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule()
                        .fill(i == currentPage ? .white : .white.opacity(0.3))
                        .frame(width: i == currentPage ? 24 : 8, height: 8)
                        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: currentPage)
                }
            }

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
                        .fill(accentColor)
                        .shadow(color: accentColor.opacity(0.5), radius: 16, y: 6)
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

    // MARK: - Helpers

    private var isLastPage: Bool { currentPage == 2 }

    private func nextPage() {
        if isLastPage {
            saveFeatures()
            finishOnboarding()
        } else {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                currentPage += 1
            }
        }
    }

    private func saveFeatures() {
        for (i, feature) in allFeatures.enumerated() {
            UserDefaults.standard.set(selected[i], forKey: feature.key)
        }
        // debts flag also controls subscriptions
        let debtsIndex = allFeatures.firstIndex(where: { $0.key == "feature.debts" }) ?? 4
        UserDefaults.standard.set(selected[debtsIndex], forKey: "feature.subscriptions")
    }

    private func finishOnboarding() {
        guard !isFinishing else { return }
        isFinishing = true
        withAnimation(.easeInOut(duration: 0.45)) { bgOpacity = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { isPresented = false }
    }

    private func animateIn() {
        withAnimation(.easeIn(duration: 0.35)) { bgOpacity = 1 }
        withAnimation(.spring(response: 0.6, dampingFraction: 0.65).delay(0.25)) { iconScale = 1 }
        withAnimation(.easeOut(duration: 0.45).delay(0.35)) { textOpacity = 1; textOffset = 0 }
    }
}
