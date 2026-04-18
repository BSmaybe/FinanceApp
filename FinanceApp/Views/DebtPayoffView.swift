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

    private var payoffHeadline: String {
        if maxMonths >= 360 {
            return String(localized: "30+ years")
        }

        let years = maxMonths / 12
        let months = maxMonths % 12
        if years > 0 {
            return "\(years) \(String(localized: "yr")) \(months) \(String(localized: "mo"))"
        }
        return "\(months) \(String(localized: "mo"))"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.canvas.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        heroSection

                        SectionShell(
                            title: String(localized: "Strategy"),
                            subtitle: String(localized: "Choose the method and any extra monthly payment before comparing the order.")
                        ) {
                            VStack(spacing: 14) {
                                Picker(String(localized: "Method"), selection: $strategy) {
                                    ForEach(DebtPayoffCalculator.Strategy.allCases, id: \.self) { value in
                                        Text(value.localizedName).tag(value)
                                    }
                                }
                                .pickerStyle(.segmented)

                                VStack(alignment: .leading, spacing: 8) {
                                    Text(String(localized: "Extra Monthly"))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    TextField("0", text: $extraPaymentText)
                                        .financeNumericKeyboard()
                                        .font(.system(.title3, design: .rounded).weight(.semibold))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 14)
                                        .background(AppTheme.elevatedSurface)
                                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                }
                            }
                        }

                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                            CompactSummaryCard(
                                title: String(localized: "Debt-free in"),
                                value: payoffHeadline,
                                detail: String(format: String(localized: "%lld debts in plan"), Int64(results.count)),
                                systemImage: "flag.checkered",
                                tint: AppTheme.primaryAccent
                            )
                            CompactSummaryCard(
                                title: String(localized: "Total Interest"),
                                value: CurrencyFormatter.string(from: totalInterest),
                                detail: strategy.localizedName,
                                systemImage: "percent",
                                tint: AppTheme.warning
                            )
                        }

                        SectionShell(
                            title: String(localized: "Payoff Order"),
                            subtitle: String(localized: "The order below reflects your current balances, rates, and extra payment." )
                        ) {
                            if results.isEmpty {
                                HStack(spacing: 12) {
                                    Image(systemName: "tray")
                                        .font(.title3)
                                        .foregroundStyle(AppTheme.primaryAccent)
                                        .frame(width: 42, height: 42)
                                        .background(AppTheme.primaryAccent.opacity(0.12))
                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    Text(String(localized: "Add debts first"))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Spacer(minLength: 0)
                                }
                            } else {
                                VStack(spacing: 12) {
                                    ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                                        payoffCard(result: result, rank: index + 1)
                                    }
                                }
                            }
                        }

                        InsightCard(
                            title: strategy == .snowball ? String(localized: "Snowball") : String(localized: "Avalanche"),
                            value: strategy == .snowball ? String(localized: "Momentum first") : String(localized: "Interest first"),
                            message: strategy == .snowball
                                ? String(localized: "Snowball: pay smallest balance first. Builds momentum.")
                                : String(localized: "Avalanche: pay highest interest rate first. Saves money."),
                            systemImage: strategy == .snowball ? "figure.run" : "chart.line.uptrend.xyaxis",
                            tint: strategy == .snowball ? AppTheme.primaryAccent : AppTheme.warning
                        )
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .keyboardDismissable()
            .financeNavigationSurface()
            .navigationTitle(String(localized: "Payoff Calculator"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var heroSection: some View {
        HeroMetricCard(
            title: String(localized: "Debt-free in"),
            value: payoffHeadline,
            supportingTitle: String(localized: "Total Interest"),
            supportingValue: CurrencyFormatter.string(from: totalInterest),
            note: String(localized: "Model repayment order before changing your monthly plan."),
            badgeText: strategy.localizedName
        )
    }

    private func payoffCard(result: DebtPayoffCalculator.PayoffResult, rank: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(format: String(localized: "Step %lld"), Int64(rank)))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(result.name)
                        .font(.headline.weight(.semibold))
                }
                Spacer(minLength: 8)
                Text("\(result.monthsToPayoff) \(String(localized: "mo"))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryAccent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppTheme.primaryAccent.opacity(0.12))
                    .clipShape(Capsule())
            }

            HStack(spacing: 12) {
                CompactSummaryCard(
                    title: String(localized: "Payoff"),
                    value: result.payoffDate.formatted(date: .abbreviated, time: .omitted),
                    systemImage: "calendar",
                    tint: AppTheme.info
                )
                CompactSummaryCard(
                    title: String(localized: "Interest"),
                    value: CurrencyFormatter.string(from: result.totalInterestPaid),
                    systemImage: "percent",
                    tint: AppTheme.warning
                )
            }
        }
        .cockpitSurface(cornerRadius: 22, elevated: true)
    }
}
