import SwiftUI
import SwiftData
import Charts

struct CashFlowForecastView: View {
    @Query private var accounts: [Account]
    @Query private var transactions: [Transaction]
    @Query(filter: #Predicate<RecurringTransaction> { $0.isActive == true })
    private var recurringTransactions: [RecurringTransaction]
    @Query(filter: #Predicate<Subscription> { $0.isActive == true })
    private var subscriptions: [Subscription]

    private var forecast: [CashFlowForecast.DailyForecast] {
        CashFlowForecast.forecast(
            accounts: accounts,
            transactions: transactions,
            recurringTransactions: recurringTransactions,
            subscriptions: subscriptions
        )
    }

    var body: some View {
        NavigationStack {
            List {
                summarySection
                chartSection
                eventsSection
            }
            .listStyle(.plain)
            .financeNavigationSurface()
            .navigationTitle(String(localized: "Cash Flow Forecast"))
        }
    }

    // MARK: - Sections

    private var summarySection: some View {
        Section {
            if let today = forecast.first, let day30 = forecast.last {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "Today"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(CurrencyFormatter.string(from: today.projectedBalance))
                            .font(.title3.bold())
                    }
                    Spacer()
                    Image(systemName: day30.projectedBalance >= today.projectedBalance ? "arrow.up.right" : "arrow.down.right")
                        .font(.title2)
                        .foregroundStyle(day30.projectedBalance >= today.projectedBalance ? Color.green : Color.red)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(String(localized: "In 30 days"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(CurrencyFormatter.string(from: day30.projectedBalance))
                            .font(.title3.bold())
                            .foregroundStyle(day30.projectedBalance >= 0 ? Color.primary : Color.red)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var chartSection: some View {
        Section(String(localized: "30-Day Projection")) {
            Chart(forecast) { point in
                LineMark(
                    x: .value("Date", point.date, unit: .day),
                    y: .value("Balance", NSDecimalNumber(decimal: point.projectedBalance).doubleValue)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Color.blue.gradient)

                AreaMark(
                    x: .value("Date", point.date, unit: .day),
                    y: .value("Balance", NSDecimalNumber(decimal: point.projectedBalance).doubleValue)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Color.blue.opacity(0.1).gradient)
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 200)
            .padding(.vertical, 8)
        }
    }

    private var eventsSection: some View {
        Section(String(localized: "Upcoming Events")) {
            let eventsWithDates = forecast.filter { !$0.events.isEmpty }
            if eventsWithDates.isEmpty {
                Text(String(localized: "No scheduled events in the next 30 days"))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(eventsWithDates.prefix(15)) { day in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(day.date, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(day.events, id: \.self) { event in
                            Text(event)
                                .font(.subheadline)
                        }
                    }
                }
            }
        }
    }
}
