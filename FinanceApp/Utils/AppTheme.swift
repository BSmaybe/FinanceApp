import SwiftUI

// MARK: - HapticManager
enum HapticManager {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        let gen = UIImpactFeedbackGenerator(style: style)
        gen.impactOccurred()
    }
    static func success() {
        let gen = UINotificationFeedbackGenerator()
        gen.notificationOccurred(.success)
    }
    static func warning() {
        let gen = UINotificationFeedbackGenerator()
        gen.notificationOccurred(.warning)
    }
    static func error() {
        let gen = UINotificationFeedbackGenerator()
        gen.notificationOccurred(.error)
    }
}

// MARK: - NumberAbbreviator
enum NumberAbbreviator {
    /// Formats a Decimal to abbreviated string: 1 234 567 → "1.2M", 45 000 → "45K"
    /// Falls back to CurrencyFormatter for small numbers (< 10 000)
    @MainActor static func string(from value: Decimal) -> String {
        let d = NSDecimalNumber(decimal: abs(value)).doubleValue
        let sign = value < 0 ? "-" : ""
        switch d {
        case 1_000_000_000...:
            return "\(sign)\(format(d / 1_000_000_000))B"
        case 1_000_000...:
            return "\(sign)\(format(d / 1_000_000))M"
        case 10_000...:
            return "\(sign)\(format(d / 1_000))K"
        default:
            return CurrencyFormatter.string(from: value)
        }
    }

    private static func format(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(v))
            : String(format: "%.1f", v)
    }
}

enum AppTheme {
    private static var p: ThemePalette { ThemeStore.shared.palette }

    static var canvas: Color           { p.canvas }
    static var surface: Color          { p.surface }
    static var surfaceMuted: Color     { p.surfaceMuted }
    static var elevatedSurface: Color  { p.surfaceElevated }
    static var glassOverlay: Color     { p.glassOverlay }
    static var outline: Color          { p.outline }

    static var primaryAccent: Color    { p.primaryAccent }
    static var secondaryAccent: Color  { p.secondaryAccent }
    static var danger: Color           { p.danger }
    static var success: Color          { p.success }
    static var warning: Color          { p.warning }
    static var info: Color             { p.info }
    static var chartNeutral: Color     { p.chartNeutral }
    static var sectionAccent: Color    { p.sectionAccent }
    static var shadowSoft: Color       { p.shadowSoft }
    static var shadowStrong: Color     { p.shadowStrong }

    static var heroCardTitle: Color    { p.heroCardTitle }
    static var heroCardLabel: Color    { p.heroCardLabel }

    static var timelineLine: Color     { p.timelineLine }
    static var timelineDot: Color      { p.timelineDot }

    static var heroGradient: LinearGradient         { p.heroGradient }
    static var incomeGradient: LinearGradient       { p.incomeGradient }
    static var expenseGradient: LinearGradient      { p.expenseGradient }
    static var debtGradient: LinearGradient         { p.debtGradient }
    static var subscriptionGradient: LinearGradient { p.subscriptionGradient }
    static var fabGradient: LinearGradient          { p.fabGradient }
}

enum AppRootTab: String, Hashable {
    case dashboard
    case transactions
    case analytics
    case accounts
    case settings
}

private struct CockpitSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let elevated: Bool
    let compact: Bool

    func body(content: Content) -> some View {
        content
            .padding(compact ? 14 : 18)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(elevated ? AppTheme.elevatedSurface : AppTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(AppTheme.outline.opacity(0.55), lineWidth: 1)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(AppTheme.glassOverlay)
                            .blur(radius: compact ? 8 : 12)
                            .opacity(0.22)
                    )
                    .shadow(color: AppTheme.shadowSoft, radius: elevated ? 18 : 12, x: 0, y: elevated ? 10 : 6)
            )
    }
}

extension View {
    func cockpitSurface(cornerRadius: CGFloat = 22, elevated: Bool = false, compact: Bool = false) -> some View {
        modifier(CockpitSurfaceModifier(cornerRadius: cornerRadius, elevated: elevated, compact: compact))
    }

    /// Uses a full symbols keyboard so digits are available in a more standard top-row layout.
    func financeNumericKeyboard() -> some View {
        self
            .keyboardType(.numbersAndPunctuation)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
    }

    /// Adds swipe-to-dismiss + Done button on keyboard toolbar to any Form/ScrollView.
    func keyboardDismissable() -> some View {
        self
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(String(localized: "Done")) {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil, from: nil, for: nil
                        )
                    }
                    .fontWeight(.semibold)
                }
            }
    }
}

struct SectionShell<Content: View, Trailing: View>: View {
    let title: String
    let subtitle: String?
    let trailing: Trailing
    let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Capsule()
                            .fill(AppTheme.sectionAccent)
                            .frame(width: 22, height: 6)
                        Text(title)
                            .font(.system(.title3, design: .rounded).weight(.semibold))
                    }
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                trailing
            }
            content
        }
        .cockpitSurface()
    }
}

extension SectionShell where Trailing == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.init(title: title, subtitle: subtitle, trailing: { EmptyView() }, content: content)
    }
}

struct HeroMetricCard: View {
    let title: String
    let value: String
    let supportingTitle: String
    let supportingValue: String
    let note: String
    var badgeText: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.heroCardLabel)
                    Text(value)
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.72)
                        .foregroundStyle(AppTheme.heroCardTitle)
                }
                Spacer(minLength: 12)
                if let badgeText, !badgeText.isEmpty {
                    Text(badgeText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.primaryAccent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AppTheme.surface.opacity(0.72))
                        .clipShape(Capsule())
                }
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(supportingTitle)
                        .font(.caption)
                        .foregroundStyle(AppTheme.heroCardTitle.opacity(0.72))
                    Text(supportingValue)
                        .font(.headline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(AppTheme.heroCardTitle)
                }
                Spacer(minLength: 12)
                Text(note)
                    .font(.caption)
                    .foregroundStyle(AppTheme.heroCardTitle.opacity(0.65))
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(AppTheme.heroGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(AppTheme.outline.opacity(0.55), lineWidth: 1)
                )
                .shadow(color: AppTheme.shadowStrong, radius: 24, x: 0, y: 14)
        )
    }
}

struct InsightCard: View {
    let title: String
    let value: String
    let message: String
    let systemImage: String
    var tint: Color = AppTheme.primaryAccent

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
            }
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cockpitSurface(cornerRadius: 20, elevated: true, compact: true)
    }
}

struct CompactSummaryCard: View {
    let title: String
    let value: String
    var detail: String? = nil
    let systemImage: String
    var tint: Color = AppTheme.primaryAccent

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                Spacer(minLength: 0)
            }
            Text(value)
                .font(.system(.headline, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cockpitSurface(cornerRadius: 18, elevated: true, compact: true)
    }
}

struct ActionTile: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var tint: Color = AppTheme.primaryAccent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 38, height: 38)
                    .background(tint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 116, alignment: .leading)
            .cockpitSurface(cornerRadius: 22, elevated: true)
        }
        .buttonStyle(.plain)
    }
}

struct FilterChip: View {
    let label: String
    var systemImage: String? = nil
    var selected: Bool = false
    var tint: Color = AppTheme.primaryAccent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption.weight(.semibold))
                }
                Text(label)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
            }
            .foregroundStyle(selected ? Color.white : .primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(selected ? tint : AppTheme.surface)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(selected ? tint : AppTheme.outline.opacity(0.55), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - AmountNumpad
struct AmountNumpad: View {
    @Binding var text: String
    var tint: Color = AppTheme.primaryAccent

    private let separator = Locale.current.decimalSeparator ?? "."

    var body: some View {
        VStack(spacing: 10) {
            ForEach([[1, 2, 3], [4, 5, 6], [7, 8, 9]] as [[Int]], id: \.self) { row in
                HStack(spacing: 10) {
                    ForEach(row, id: \.self) { digit in
                        numKey(label: "\(digit)") { append("\(digit)") }
                    }
                }
            }
            HStack(spacing: 10) {
                numKey(label: separator) { appendSeparator() }
                numKey(label: "0") { append("0") }
                numKey(label: "⌫", isDestructive: true) { backspace() }
            }
        }
    }

    private func numKey(label: String, isDestructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: {
            HapticManager.impact(.light)
            action()
        }) {
            Text(label)
                .font(.title2.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(isDestructive ? AppTheme.danger.opacity(0.12) : AppTheme.surface)
                .foregroundStyle(isDestructive ? AppTheme.danger : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func append(_ digit: String) {
        if text == "0" && digit != separator { text = digit; return }
        text += digit
    }

    private func appendSeparator() {
        guard !text.contains(separator) else { return }
        if text.isEmpty { text = "0" }
        text += separator
    }

    private func backspace() {
        guard !text.isEmpty else { return }
        text.removeLast()
    }
}

// MARK: - SuccessBurst
struct SuccessBurst: View {
    @Binding var isShowing: Bool
    var message: String = String(localized: "Saved!")

    @State private var scale: CGFloat = 0.3
    @State private var opacity: Double = 0

    var body: some View {
        if isShowing {
            VStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(AppTheme.success)
                Text(message)
                    .font(.headline.weight(.semibold))
            }
            .padding(28)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                    scale = 1; opacity = 1
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                    withAnimation(.easeOut(duration: 0.25)) {
                        scale = 0.8; opacity = 0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        isShowing = false
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }
}

// MARK: - BudgetRingCard
struct BudgetRingCard: View {
    let name: String
    let icon: String
    let color: Color
    let spent: Decimal
    let limit: Decimal
    let ratio: Double
    let onTap: () -> Void

    private var accent: Color {
        ratio >= 1 ? AppTheme.danger : (ratio >= 0.8 ? AppTheme.warning : AppTheme.success)
    }
    private var progress: Double { min(max(ratio, 0), 1) }
    private var pct: Int { Int(ratio * 100) }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .stroke(AppTheme.surfaceMuted, lineWidth: 6)
                        .frame(width: 68, height: 68)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .frame(width: 68, height: 68)
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: progress)
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(color)
                }
                VStack(spacing: 2) {
                    Text("\(pct)%")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(accent)
                    Text(name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: 88)
            .padding(.vertical, 14)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - SparklineView
import Charts

struct SparklineView: View {
    let values: [Double]
    var tint: Color = AppTheme.primaryAccent
    var showArea: Bool = true

    var body: some View {
        if values.count >= 2 {
            Chart {
                ForEach(Array(values.enumerated()), id: \.offset) { i, val in
                    if showArea {
                        AreaMark(
                            x: .value("i", i),
                            yStart: .value("base", values.min() ?? 0),
                            yEnd: .value("val", val)
                        )
                        .foregroundStyle(tint.opacity(0.2))
                    }
                    LineMark(
                        x: .value("i", i),
                        y: .value("val", val)
                    )
                    .foregroundStyle(tint)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .chartYScale(domain: (values.min() ?? 0)...(values.max() ?? 1))
        } else {
            Rectangle()
                .fill(tint.opacity(0.2))
                .frame(height: 1)
        }
    }
}
