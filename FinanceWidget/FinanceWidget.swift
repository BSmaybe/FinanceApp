import WidgetKit
import SwiftUI

// MARK: - Shared data loading (same logic as WidgetDataProvider in main app)

private let suiteName = "group.com.personal.financeappbilly"

private func loadWidgetData() -> (netWorth: Decimal, income: Decimal, expense: Decimal, lastUpdate: Date) {
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        return (.zero, .zero, .zero, Date())
    }
    let nw = Decimal(string: defaults.string(forKey: "netWorth") ?? "0") ?? .zero
    let inc = Decimal(string: defaults.string(forKey: "monthlyIncome") ?? "0") ?? .zero
    let exp = Decimal(string: defaults.string(forKey: "monthlyExpense") ?? "0") ?? .zero
    let ts = defaults.double(forKey: "lastUpdate")
    return (nw, inc, exp, ts > 0 ? Date(timeIntervalSince1970: ts) : Date())
}

private func formatCurrency(_ value: Decimal) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = "KZT"
    formatter.maximumFractionDigits = 0
    return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
}

// MARK: - Timeline

struct FinanceEntry: TimelineEntry {
    let date: Date
    let netWorth: Decimal
    let monthlyIncome: Decimal
    let monthlyExpense: Decimal
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> FinanceEntry {
        FinanceEntry(date: Date(), netWorth: 150_000, monthlyIncome: 500_000, monthlyExpense: 350_000)
    }

    func getSnapshot(in context: Context, completion: @escaping (FinanceEntry) -> Void) {
        let data = loadWidgetData()
        completion(FinanceEntry(date: Date(), netWorth: data.netWorth, monthlyIncome: data.income, monthlyExpense: data.expense))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FinanceEntry>) -> Void) {
        let data = loadWidgetData()
        let entry = FinanceEntry(date: Date(), netWorth: data.netWorth, monthlyIncome: data.income, monthlyExpense: data.expense)
        // Refresh every 30 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}

// MARK: - Small Widget View

struct SmallWidgetView: View {
    let entry: FinanceEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
            }

            Spacer()

            Text("Net Worth")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))

            Text(formatCurrency(entry.netWorth))
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(.white)
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            let net = entry.monthlyIncome - entry.monthlyExpense
            HStack(spacing: 2) {
                Image(systemName: net >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.caption2)
                Text(formatCurrency(abs(net)))
                    .font(.caption2.monospacedDigit())
            }
            .foregroundStyle(net >= 0 ? .mint : .orange)
        }
        .padding(12)
    }
}

// MARK: - Medium Widget View

struct MediumWidgetView: View {
    let entry: FinanceEntry

    var body: some View {
        HStack(spacing: 16) {
            // Left: Net Worth
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                    Text("Finance")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }

                Spacer()

                Text("Net Worth")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
                Text(formatCurrency(entry.netWorth))
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }

            Divider()
                .background(.white.opacity(0.3))

            // Right: Monthly summary
            VStack(alignment: .leading, spacing: 8) {
                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.mint)
                    Text("Income")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Text(formatCurrency(entry.monthlyIncome))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.mint)
                }

                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Text("Expense")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Text(formatCurrency(entry.monthlyExpense))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.orange)
                }

                let net = entry.monthlyIncome - entry.monthlyExpense
                HStack(spacing: 4) {
                    Image(systemName: "equal.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(net >= 0 ? .green : .red)
                    Text("Net")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Text(formatCurrency(net))
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(net >= 0 ? .green : .red)
                }
            }
        }
        .padding(12)
    }
}

// MARK: - Widget

struct FinanceWidget: Widget {
    let kind: String = "FinanceWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            Group {
                if #available(iOSApplicationExtension 17.0, *) {
                    FinanceWidgetEntryView(entry: entry)
                        .containerBackground(
                            LinearGradient(
                                colors: [Color.blue, Color.indigo],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            for: .widget
                        )
                } else {
                    FinanceWidgetEntryView(entry: entry)
                        .background(
                            LinearGradient(
                                colors: [Color.blue, Color.indigo],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            }
        }
        .configurationDisplayName("Finance")
        .description("Net worth and monthly summary")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct FinanceWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: Provider.Entry

    var body: some View {
        switch family {
        case .systemMedium:
            MediumWidgetView(entry: entry)
        default:
            SmallWidgetView(entry: entry)
        }
    }
}

#Preview(as: .systemSmall) {
    FinanceWidget()
} timeline: {
    FinanceEntry(date: .now, netWorth: 1_250_000, monthlyIncome: 500_000, monthlyExpense: 350_000)
}

#Preview(as: .systemMedium) {
    FinanceWidget()
} timeline: {
    FinanceEntry(date: .now, netWorth: 1_250_000, monthlyIncome: 500_000, monthlyExpense: 350_000)
}
