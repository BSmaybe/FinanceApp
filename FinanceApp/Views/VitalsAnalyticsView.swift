import SwiftUI
import Charts

// MARK: - VitalsAnalyticsView

struct VitalsAnalyticsView: View {
    let summary: FinancialVitalsAnalyticsSummary
    let period: AnalyticsPeriod
    let onDriverCTA: (CoachAdviceCTA) -> Void

    var body: some View {
        VStack(spacing: 18) {
            VitalsOverviewSection(vitals: summary.vitals)
            VitalsLoadSection(
                acuteLoadIndex: summary.acuteLoadIndex,
                acuteIsElevated: summary.acuteIsElevated
            )
            VitalsTrendsSection(timeline: summary.timeline, period: period)
            VitalsDriversSection(drivers: summary.drivers, onCTA: onDriverCTA)
        }
    }
}

// MARK: - VitalsOverviewSection

struct VitalsOverviewSection: View {
    let vitals: FinancialVitals

    private var readinessZone: FinancialVitalsZone {
        .from(score: vitals.readiness)
    }

    private var readinessPillText: String {
        switch readinessZone {
        case .green:
            return String(localized: "Stable")
        case .yellow:
            return String(localized: "Watch")
        case .red:
            return String(localized: "Tight")
        }
    }

    private var readinessPillColor: Color {
        switch readinessZone {
        case .green:
            return AppTheme.success
        case .yellow:
            return AppTheme.warning
        case .red:
            return AppTheme.danger
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "Money State"))
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .foregroundStyle(AppTheme.heroCardTitle)
                    Text(String(localized: "Signals for the next few days"))
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.heroCardTitle.opacity(0.72))
                }
                Spacer(minLength: 12)
                Text(readinessPillText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(readinessPillColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(readinessPillColor.opacity(0.12))
                    .clipShape(Capsule())
            }

            HStack(spacing: 10) {
                VitalsHeroMetricCard(
                    metric: .readiness,
                    score: vitals.readiness,
                    detail: String(localized: "Decision safety")
                )
                VitalsHeroMetricCard(
                    metric: .pressure,
                    score: vitals.pressure,
                    detail: String(localized: "Current load")
                )
                VitalsHeroMetricCard(
                    metric: .reserve,
                    score: vitals.reserve,
                    detail: String(localized: "Buffer strength")
                )
            }

            HStack(spacing: 10) {
                VitalsDetailTile(
                    title: String(localized: "Runway"),
                    value: String(format: String(localized: "%d days"), vitals.runwayDays),
                    subtitle: String(localized: "Essential coverage"),
                    tint: AppTheme.info,
                    progress: min(max(Double(vitals.runwayDays) / 30.0, 0), 1)
                )
                VitalsDetailTile(
                    title: String(localized: "Left to pay"),
                    value: CurrencyFormatter.string(from: vitals.leftToPayNext7Days),
                    subtitle: String(localized: "Due in 7 days"),
                    tint: AppTheme.sectionAccent,
                    progress: min(max(NSDecimalNumber(decimal: vitals.leftToPayNext7Days).doubleValue / 100000.0, 0), 1)
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(AppTheme.heroGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(AppTheme.outline.opacity(0.55), lineWidth: 1)
                )
                .shadow(color: AppTheme.shadowSoft, radius: 16, x: 0, y: 10)
        )
    }
}

private struct VitalsHeroMetricCard: View {
    let metric: FinancialVitalMetric
    let score: Int
    let detail: String

    private var tint: Color {
        switch metric.zone(for: score) {
        case .green:
            return AppTheme.success
        case .yellow:
            return AppTheme.warning
        case .red:
            return AppTheme.danger
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(metric.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text("\(score)")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)

            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Text("\(metric.stateLabel(for: score)) · \(metric.directionLabel)")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(tint.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(tint.opacity(0.22), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct VitalsDetailTile: View {
    let title: String
    let value: String
    let subtitle: String
    let tint: Color
    let progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit().weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            ProgressView(value: progress)
                .tint(tint)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppTheme.surface.opacity(0.72))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppTheme.outline.opacity(0.40), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: - VitalsLoadSection

private struct VitalsLoadSection: View {
    let acuteLoadIndex: Double
    let acuteIsElevated: Bool

    private var loadColor: Color {
        acuteIsElevated ? AppTheme.warning : AppTheme.success
    }

    private var loadLabel: String {
        acuteIsElevated
            ? String(localized: "Recent load is elevated")
            : String(localized: "Recent load is controlled")
    }

    private var loadMessage: String {
        acuteIsElevated
            ? String(localized: "Your latest spending is running above your normal baseline.")
            : String(localized: "Recent spending is close to your normal pattern.")
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "Recent spend vs baseline"))
                    .font(.headline.weight(.semibold))
                Text(loadMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 8) {
                Text("\(Int(acuteLoadIndex.rounded()))%")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(loadColor)
                Text(loadLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(loadColor)
                Text(String(localized: "100% is your recent norm"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .cockpitSurface(cornerRadius: 24, elevated: true)
    }
}

// MARK: - VitalsTrendsSection

struct VitalsTrendsSection: View {
    let timeline: FinancialVitalsTimeline
    let period: AnalyticsPeriod

    @State private var selectedMetric: VitalsMetric = .readiness

    enum VitalsMetric: String, CaseIterable {
        case readiness, pressure, reserve

        var label: String {
            switch self {
            case .readiness: return String(localized: "Readiness")
            case .pressure:  return String(localized: "Pressure")
            case .reserve:   return String(localized: "Reserve")
            }
        }

        var color: Color {
            switch self {
            case .readiness: return AppTheme.primaryAccent
            case .pressure:  return AppTheme.warning
            case .reserve:   return AppTheme.success
            }
        }
    }

    private func value(for metric: VitalsMetric, point: FinancialVitalsPoint) -> Int {
        switch metric {
        case .readiness: return point.readiness
        case .pressure:  return point.pressure
        case .reserve:   return point.reserve
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Trends"))
                        .font(.headline.weight(.semibold))
                    Text(String(localized: "See how your core signals are moving over time."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 8) {
                ForEach(VitalsMetric.allCases, id: \.self) { metric in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            selectedMetric = metric
                        }
                    } label: {
                        Text(metric.label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(selectedMetric == metric ? Color.white : .primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(selectedMetric == metric ? metric.color : AppTheme.surfaceMuted)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            if timeline.points.isEmpty {
                Text(String(localized: "Not enough data for this period."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 32)
            } else {
                Chart {
                    ForEach(timeline.points, id: \.date) { point in
                        LineMark(
                            x: .value(String(localized: "Date"), point.date),
                            y: .value(selectedMetric.label, value(for: selectedMetric, point: point))
                        )
                        .foregroundStyle(selectedMetric.color)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                        .interpolationMethod(.catmullRom)

                        AreaMark(
                            x: .value(String(localized: "Date"), point.date),
                            y: .value(selectedMetric.label, value(for: selectedMetric, point: point))
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [selectedMetric.color.opacity(0.22), selectedMetric.color.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)
                    }
                }
                .chartYScale(domain: 0...100)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: period == .month ? 6 : 4)) {
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(AppTheme.outline.opacity(0.5))
                        AxisValueLabel(format: axisFormat)
                    }
                }
                .chartYAxis {
                    AxisMarks(values: [0, 25, 50, 75, 100]) {
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(AppTheme.outline.opacity(0.5))
                        AxisValueLabel()
                    }
                }
                .frame(height: 190)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .cockpitSurface(cornerRadius: 24, elevated: true)
    }

    private var axisFormat: Date.FormatStyle {
        switch period {
        case .week:
            return .dateTime.weekday(.abbreviated)
        case .month:
            return .dateTime.day().month(.abbreviated)
        case .year:
            return .dateTime.month(.abbreviated)
        }
    }
}

// MARK: - VitalsDriversSection

struct VitalsDriversSection: View {
    let drivers: [FinancialVitalsDriver]
    let onCTA: (CoachAdviceCTA) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "What's Driving This"))
                        .font(.headline.weight(.semibold))
                    Text(String(localized: "The few factors having the strongest effect right now."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if drivers.isEmpty {
                Text(String(localized: "No significant drivers identified for this period."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(drivers) { driver in
                        VitalsDriverRow(driver: driver, onCTA: onCTA)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .cockpitSurface(cornerRadius: 24, elevated: true)
    }
}

private struct VitalsDriverRow: View {
    let driver: FinancialVitalsDriver
    let onCTA: (CoachAdviceCTA) -> Void

    private var impactColor: Color {
        driver.impact == .helps ? AppTheme.success : AppTheme.danger
    }

    private var impactIcon: String {
        driver.impact == .helps ? "arrow.up.circle.fill" : "arrow.down.circle.fill"
    }

    private var impactLabel: String {
        driver.impact == .helps
            ? String(localized: "Helping")
            : String(localized: "Pressuring")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: impactIcon)
                .foregroundStyle(impactColor)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 26, height: 26)
                .background(impactColor.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(driver.title)
                        .font(.subheadline.weight(.semibold))
                    Text(impactLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(impactColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(impactColor.opacity(0.10))
                        .clipShape(Capsule())
                }
                Text(driver.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if driver.cta != .none {
                    Button {
                        onCTA(driver.cta)
                    } label: {
                        Text(driver.cta.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.primaryAccent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(AppTheme.primaryAccent.opacity(0.10))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(AppTheme.surfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
