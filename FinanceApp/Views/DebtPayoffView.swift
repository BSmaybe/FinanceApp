import SwiftUI
import SwiftData

struct DebtPayoffView: View {
    @Query private var debts: [Debt]
    @State private var strategy: DebtPayoffCalculator.Strategy = .avalanche
    @State private var extraPaymentText = ""

    private var localDecimalSeparator: String {
        Locale.current.decimalSeparator ?? "."
    }

    private var extraPayment: Decimal {
        Decimal(string: extraPaymentText.replacingOccurrences(of: localDecimalSeparator, with: ".")) ?? .zero
    }

    private var results: [DebtPayoffCalculator.PayoffResult] {
        DebtPayoffCalculator.calculate(debts: debts, extraMonthlyPayment: extraPayment, strategy: strategy)
    }

    private var totalInterest: Decimal {
        results.reduce(.zero) { $0 + $1.totalInterestPaid }
    }

    private var maxMonths: Int {
        results.map(\.monthsToPayoff).max() ?? 0
    }

    var body: some View {
        NavigationStack {
            List {
                Section(String(localized: "Strategy")) {
                    Picker(String(localized: "Method"), selection: $strategy) {
                        ForEach(DebtPayoffCalculator.Strategy.allCases, id: \.self) { s in
                            Text(s.localizedName).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Text(String(localized: "Extra Monthly"))
                        Spacer()
                        TextField("0", text: $extraPaymentText)
                            .financeNumericKeyboard()
                            .multilineTextAlignment(.trailing)
                            .frame(width: 120)
                    }
                }

                Section(String(localized: "Summary")) {
                    HStack {
                        Text(String(localized: "Debt-free in"))
                        Spacer()
                        if maxMonths >= 360 {
                            Text(String(localized: "30+ years"))
                                .foregroundStyle(.red)
                        } else {
                            let years = maxMonths / 12
                            let months = maxMonths % 12
                            if years > 0 {
                                Text("\(years) \(String(localized: "yr")) \(months) \(String(localized: "mo"))")
                                    .font(.headline)
                            } else {
                                Text("\(months) \(String(localized: "mo"))")
                                    .font(.headline)
                            }
                        }
                    }
                    HStack {
                        Text(String(localized: "Total Interest"))
                        Spacer()
                        Text(CurrencyFormatter.string(from: totalInterest))
                            .font(.headline)
                            .foregroundStyle(.orange)
                    }
                }

                Section(String(localized: "Payoff Order")) {
                    if results.isEmpty {
                        Text(String(localized: "Add debts first"))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(results) { result in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(result.name)
                                        .font(.headline)
                                    Spacer()
                                    Text("\(result.monthsToPayoff) \(String(localized: "mo"))")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                HStack {
                                    Text(String(localized: "Payoff:"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(result.payoffDate, style: .date)
                                        .font(.caption)
                                    Spacer()
                                    Text(String(localized: "Interest:"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(CurrencyFormatter.string(from: result.totalInterestPaid))
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                if strategy == .snowball {
                    Section {
                        Text(String(localized: "Snowball: pay smallest balance first. Builds momentum."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        Text(String(localized: "Avalanche: pay highest interest rate first. Saves money."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.plain)
            .financeNavigationSurface()
            .navigationTitle(String(localized: "Payoff Calculator"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
