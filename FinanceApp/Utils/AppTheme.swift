import SwiftUI

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
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cockpitSurface(cornerRadius: 20, elevated: true, compact: true)
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
