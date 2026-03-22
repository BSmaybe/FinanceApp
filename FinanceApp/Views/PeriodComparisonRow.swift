import SwiftUI

// MARK: - PeriodComparisonRow

/// Reusable row that shows a comparison label, current amount, previous amount,
/// and a delta badge (▲/▼ with % and absolute difference).
struct PeriodComparisonRow: View {
    let label: String
    let currentAmount: Decimal
    let previousAmount: Decimal

    private var delta: Decimal { currentAmount - previousAmount }

    private var deltaPercent: Double? {
        guard previousAmount != .zero else { return nil }
        let ratio = NSDecimalNumber(decimal: delta / previousAmount).doubleValue
        return ratio * 100
    }

    private var isPositive: Bool { delta >= .zero }

    private var arrowSystemImage: String {
        isPositive ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill"
    }

    private var deltaColor: Color {
        isPositive ? AppTheme.success : AppTheme.danger
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if delta == .zero && previousAmount == .zero {
                Text(String(localized: "No data for this period"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: arrowSystemImage)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(deltaColor)

                    Text(CurrencyFormatter.string(from: abs(delta)))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(deltaColor)

                    if let pct = deltaPercent {
                        Text(String(format: "(%.1f%%)", abs(pct)))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(deltaColor.opacity(0.8))
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
