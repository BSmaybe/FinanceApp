import SwiftUI

// MARK: - Feature Item

private struct FeatureItem: Identifiable {
    let id = UUID()
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    let key: String
}

private let allFeatures: [FeatureItem] = [
    FeatureItem(icon: "arrow.up.arrow.down.circle.fill", color: Color(red: 0.18, green: 0.72, blue: 0.56),
                title: String(localized: "Income & Expenses"), subtitle: String(localized: "Log daily money flow"), key: "feature.transactions"),
    FeatureItem(icon: "chart.bar.fill", color: Color(red: 0.24, green: 0.48, blue: 0.98),
                title: String(localized: "Analytics"), subtitle: String(localized: "Charts and spending insights"), key: "feature.analytics"),
    FeatureItem(icon: "gauge.with.needle.fill", color: Color(red: 0.92, green: 0.55, blue: 0.20),
                title: String(localized: "Budgets"), subtitle: String(localized: "Monthly category limits"), key: "feature.budgets"),
    FeatureItem(icon: "target", color: Color(red: 0.62, green: 0.35, blue: 0.95),
                title: String(localized: "Savings Goals"), subtitle: String(localized: "Track progress to targets"), key: "feature.goals"),
    FeatureItem(icon: "creditcard.fill", color: Color(red: 0.90, green: 0.28, blue: 0.30),
                title: String(localized: "Debts & Subscriptions"), subtitle: String(localized: "Loans and recurring bills"), key: "feature.debts")
]

private let currencyOptions: [(code: String, symbol: String, name: String)] = [
    ("KZT", "₸", "Tenge"),
    ("USD", "$", "Dollar"),
    ("RUB", "₽", "Ruble"),
    ("EUR", "€", "Euro")
]

// MARK: - OnboardingView

struct OnboardingView: View {
    @Binding var isPresented: Bool

    // Pages: 0 Welcome · 1 Currency · 2 Questionnaire · 3 Demo
    private let totalPages = 4
    @State private var page = 0
    @State private var bgOpacity: Double = 0
    @State private var isFinishing = false

    // Welcome
    @State private var logoScale: CGFloat = 0
    @State private var titleOpacity: Double = 0
    @State private var titleOffset: CGFloat = 24
    @State private var bulletRevealCount = 0

    // Currency
    @State private var selectedCurrency = "KZT"

    // Features (A2: start empty — user picks what they need)
    @State private var selected: [Bool] = Array(repeating: false, count: allFeatures.count)
    @State private var showSelectionHint = false

    // Demo
    @State private var revealedCount = 0

    var body: some View {
        ZStack {
            bg
            VStack(spacing: 0) {
                Spacer()
                content
                Spacer()
                controls.padding(.bottom, 48)
            }
        }
        .ignoresSafeArea()
        .opacity(bgOpacity)
        .onAppear { animateIn() }
    }

    // MARK: - BG

    private var bg: some View {
        let colors: [Color] = [
            Color(red: 0.23, green: 0.43, blue: 0.82),
            Color(red: 0.15, green: 0.55, blue: 0.44),
            Color(red: 0.47, green: 0.38, blue: 0.78),
            Color(red: 0.15, green: 0.55, blue: 0.44)
        ]
        let accent = colors[min(page, colors.count - 1)]
        return ZStack {
            Color(red: 0.05, green: 0.07, blue: 0.11).ignoresSafeArea()
            RadialGradient(colors: [accent.opacity(0.22), .clear],
                           center: .init(x: 0.5, y: 0.28), startRadius: 0, endRadius: 420)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.5), value: page)
        }
    }

    // MARK: - Page content

    @ViewBuilder private var content: some View {
        switch page {
        case 0:  welcomeSlide
        case 1:  currencySlide
        case 2:  questionnaireSlide
        default: demoSlide
        }
    }

    // MARK: Welcome (A3: bullets instead of single subtitle)

    private var welcomeSlide: some View {
        let bullets: [(icon: String, text: String)] = [
            ("gauge.with.needle.fill",      String(localized: "See your money state at a glance")),
            ("plus.circle.fill",            String(localized: "Capture transactions in seconds")),
            ("calendar.badge.clock",        String(localized: "Plan ahead without spreadsheet stress"))
        ]

        return VStack(spacing: 0) {
            Text(String(localized: "Daily money clarity"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(accentForPage)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.white.opacity(0.08))
                .clipShape(Capsule())
                .scaleEffect(logoScale)

            Spacer().frame(height: 28)

            VStack(spacing: 16) {
                Text(String(localized: "See what your next move should be"))
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text(String(localized: "Understand pressure early, keep reserve visible, and act before bills become stress."))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                moneyStatePreviewCard
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(bullets.indices, id: \.self) { i in
                        if bulletRevealCount > i {
                            HStack(spacing: 10) {
                                Image(systemName: bullets[i].icon)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(accentForPage)
                                    .frame(width: 20)
                                Text(bullets[i].text)
                                    .font(.system(size: 14))
                                    .foregroundStyle(.white.opacity(0.75))
                            }
                            .transition(.move(edge: .leading).combined(with: .opacity))
                        }
                    }
                }
                .padding(.horizontal, 40)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .opacity(titleOpacity)
            .offset(y: titleOffset)
        }
    }

    private var moneyStatePreviewCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Money State"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.52))
                    Text("76")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                Spacer()
                Text(String(localized: "Stable"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(red: 0.18, green: 0.72, blue: 0.56))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(red: 0.18, green: 0.72, blue: 0.56).opacity(0.14))
                    .clipShape(Capsule())
            }

            HStack(spacing: 10) {
                onboardingSignalPill(title: String(localized: "Pressure"), value: "38")
                onboardingSignalPill(title: String(localized: "Reserve"), value: "71")
                onboardingSignalPill(title: String(localized: "Runway"), value: "18d")
            }

            Text(String(localized: "Higher readiness and reserve are better. Lower pressure is better."))
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.58))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(.white.opacity(0.10), lineWidth: 1)
                )
        )
        .padding(.horizontal, 26)
    }

    private func onboardingSignalPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.44))
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: Currency

    private var currencySlide: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text(String(localized: "Pick your default currency"))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(String(localized: "This becomes the default for new accounts. You can still change currency per account later."))
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.50))
            }
            .multilineTextAlignment(.center)

            VStack(spacing: 10) {
                ForEach(currencyOptions, id: \.code) { cur in
                    let isOn = selectedCurrency == cur.code
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            selectedCurrency = cur.code
                        }
                        HapticManager.impact(.light)
                    } label: {
                        HStack(spacing: 14) {
                            Text(cur.symbol)
                                .font(.system(size: 22, weight: .bold))
                                .frame(width: 40, height: 40)
                                .background(Circle().fill(isOn ? .white.opacity(0.18) : .white.opacity(0.06)))
                                .foregroundStyle(.white)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(cur.code)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(isOn ? .white : .white.opacity(0.55))
                                Text(cur.name)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.35))
                            }
                            Spacer()
                            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22))
                                .foregroundStyle(isOn ? Color(red: 0.18, green: 0.72, blue: 0.56) : .white.opacity(0.20))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(isOn ? .white.opacity(0.10) : .white.opacity(0.04))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(isOn ? Color(red: 0.18, green: 0.72, blue: 0.56).opacity(0.5) : .clear, lineWidth: 1))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 28)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(String(localized: "Preview"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.42))
                        Text("24 500 \(currencyOptions.first(where: { $0.code == selectedCurrency })?.symbol ?? "₸")")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    Text(selectedCurrency)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(accentForPage)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(accentForPage.opacity(0.14))
                        .clipShape(Capsule())
                }

                Text(String(localized: "Use the default for fast capture, then override it only when an account needs another currency."))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.56))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.white.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(.white.opacity(0.10), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 28)
        }
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)))
    }

    // MARK: Questionnaire (A2: starts empty)

    private var canAdvanceFromQuestionnaire: Bool {
        selected.contains(true)
    }

    private var selectedFeatureCount: Int {
        selected.filter { $0 }.count
    }

    private var questionnaireSlide: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text(String(localized: "Build your first cockpit"))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(String(localized: "Start with the flows you care about most. Everything can change later in Settings."))
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.50))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            HStack(spacing: 10) {
                Text(String(format: String(localized: "%lld selected"), Int64(selectedFeatureCount)))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accentForPage)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(accentForPage.opacity(0.12))
                    .clipShape(Capsule())

                Text(String(localized: "Recommended: transactions, budgets, analytics"))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.52))
            }

            VStack(spacing: 8) {
                ForEach(allFeatures.indices, id: \.self) { i in
                    featureRow(index: i)
                }
            }
            .padding(.horizontal, 24)

            // A2: Selection hint
            if showSelectionHint {
                Text(String(localized: "Choose at least one feature"))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
                    .transition(.opacity)
            }
        }
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)))
    }

    private func featureRow(index: Int) -> some View {
        let f = allFeatures[index]
        let isOn = selected[index]
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { selected[index].toggle() }
            HapticManager.impact(.light)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: f.icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isOn ? f.color : f.color.opacity(0.30))
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(f.color.opacity(isOn ? 0.18 : 0.06))
                    )
                VStack(alignment: .leading, spacing: 1) {
                    Text(f.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isOn ? .white : .white.opacity(0.35))
                    Text(f.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(isOn ? 0.45 : 0.20))
                }
                Spacer()
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isOn ? f.color : .white.opacity(0.18))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.white.opacity(isOn ? 0.09 : 0.03))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(isOn ? f.color.opacity(0.30) : .clear, lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Demo (A4: mini-dashboard card instead of chips)

    private var demoSlide: some View {
        let green = Color(red: 0.18, green: 0.72, blue: 0.56)

        return VStack(spacing: 24) {
            Image(systemName: "chart.line.uptrend.xyaxis.circle.fill")
                .font(.system(size: 56, weight: .bold))
                .foregroundStyle(green)
                .scaleEffect(revealedCount > 0 ? 1.0 : 0.3)
                .opacity(revealedCount > 0 ? 1.0 : 0.0)
                .animation(.spring(response: 0.5, dampingFraction: 0.6), value: revealedCount)

            VStack(spacing: 6) {
                Text(String(localized: "Preview your setup"))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(String(localized: "Start with a calm daily view of balances, pressure and next actions."))
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.50))
            }
            .multilineTextAlignment(.center)

            miniDashboardCard
        }
        .onAppear {
            let enabledCount = selected.filter { $0 }.count
            startReveal(count: 1 + enabledCount)
        }
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)))
    }

    private var miniDashboardCard: some View {
        let enabledFeatures = allFeatures.enumerated().filter { selected[$0.offset] }.map(\.element)
        let curSymbol = currencyOptions.first(where: { $0.code == selectedCurrency })?.symbol ?? "₸"

        return VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "DEFAULT CURRENCY"))
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                        .tracking(0.5)
                    Text("\(selectedCurrency) \(curSymbol)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                Spacer()
                miniHeroChip(icon: "gauge.with.needle.fill", color: Color(red: 0.18, green: 0.72, blue: 0.56), label: "76")
                miniHeroChip(icon: "calendar.badge.clock", color: Color(red: 0.92, green: 0.75, blue: 0.20), label: "2 due")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)

            // Feature rows
            VStack(spacing: 0) {
                miniDashRow(
                    icon: "creditcard.fill",
                    color: Color(red: 0.92, green: 0.75, blue: 0.20),
                    label: String(localized: "Accounts"),
                    visible: revealedCount >= 1,
                    index: 0
                )
                ForEach(enabledFeatures.indices, id: \.self) { pos in
                    let f = enabledFeatures[pos]
                    miniDashRow(icon: f.icon, color: f.color, label: f.title,
                                visible: revealedCount >= pos + 2, index: pos + 1)
                }
            }
            .padding(.vertical, 4)
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
        .padding(.horizontal, 24)
    }

    private func miniHeroChip(icon: String, color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(.white.opacity(0.10)))
    }

    private func miniDashRow(icon: String, color: Color, label: String, visible: Bool, index: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(Circle().fill(color.opacity(0.15)))
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
            Spacer()
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(color.opacity(0.8))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .opacity(visible ? 1 : 0)
        .offset(x: visible ? 0 : -16)
        .animation(.spring(response: 0.4, dampingFraction: 0.75).delay(Double(index) * 0.05), value: visible)
    }

    private func startReveal(count: Int) {
        revealedCount = 0
        for i in 0..<count {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15 + Double(i) * 0.14) {
                withAnimation { revealedCount = i + 1 }
            }
        }
    }

    // MARK: - Controls (A1: back button)

    private var controls: some View {
        VStack(spacing: 22) {
            // A1: Nav row with back button + dots
            HStack(spacing: 0) {
                // Back button (pages 1–3)
                if page > 0 {
                    Button {
                        HapticManager.impact(.light)
                        if page == 3 { revealedCount = 0 }
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) { page -= 1 }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.60))
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(.white.opacity(0.10)))
                    }
                    .buttonStyle(.plain)
                } else {
                    Spacer().frame(width: 32)
                }

                Spacer()

                // Dots
                HStack(spacing: 7) {
                    ForEach(0..<totalPages, id: \.self) { i in
                        Capsule()
                            .fill(i == page ? .white : .white.opacity(0.28))
                            .frame(width: i == page ? 22 : 7, height: 7)
                            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: page)
                    }
                }

                Spacer()

                // Placeholder to balance back button
                Spacer().frame(width: 32)
            }
            .padding(.horizontal, 24)

            // Next / Get Started button
            let isLast = page == totalPages - 1
            Button(action: advance) {
                HStack(spacing: 8) {
                    Text(isLast ? String(localized: "Get Started") : String(localized: "Next"))
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                    Image(systemName: isLast ? "checkmark" : "arrow.right")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(width: 200, height: 50)
                .background(
                    Capsule().fill(accentForPage)
                        .shadow(color: accentForPage.opacity(0.45), radius: 14, y: 5)
                )
            }
        }
    }

    private var accentForPage: Color {
        let colors: [Color] = [
            Color(red: 0.24, green: 0.48, blue: 0.98),
            Color(red: 0.18, green: 0.72, blue: 0.56),
            Color(red: 0.62, green: 0.35, blue: 0.95),
            Color(red: 0.18, green: 0.72, blue: 0.56)
        ]
        return colors[min(page, colors.count - 1)]
    }

    // MARK: - Actions

    private func advance() {
        // A2: block advance on questionnaire if nothing selected
        if page == 2 && !canAdvanceFromQuestionnaire {
            HapticManager.impact(.light)
            withAnimation { showSelectionHint = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation { showSelectionHint = false }
            }
            return
        }

        HapticManager.impact(.medium)
        if page == totalPages - 1 {
            saveAndFinish()
        } else {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) { page += 1 }
        }
    }

    private func saveAndFinish() {
        guard !isFinishing else { return }
        isFinishing = true
        // Save currency
        UserDefaults.standard.set(selectedCurrency, forKey: "defaultCurrency")
        // Save features
        for (i, f) in allFeatures.enumerated() {
            UserDefaults.standard.set(selected[i], forKey: f.key)
        }
        let debtsIdx = allFeatures.firstIndex(where: { $0.key == "feature.debts" }) ?? 4
        UserDefaults.standard.set(selected[debtsIdx], forKey: "feature.subscriptions")

        withAnimation(.easeInOut(duration: 0.4)) { bgOpacity = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { isPresented = false }
    }

    private func animateIn() {
        withAnimation(.easeIn(duration: 0.3)) { bgOpacity = 1 }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.65).delay(0.2)) { logoScale = 1 }
        withAnimation(.easeOut(duration: 0.4).delay(0.3)) { titleOpacity = 1; titleOffset = 0 }
        // A3: staggered bullet reveal
        for i in 0..<3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5 + Double(i) * 0.2) {
                withAnimation(.easeOut(duration: 0.35)) { bulletRevealCount = i + 1 }
            }
        }
    }
}
