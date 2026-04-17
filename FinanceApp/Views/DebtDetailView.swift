import SwiftUI
import Foundation

// MARK: - Amortization Row

struct DebtAmortizationRow: Identifiable {
    let id = UUID()
    let number: Int
    let date: Date
    let payment: Decimal
    let principal: Decimal
    let interest: Decimal
    let balance: Decimal
}

// MARK: - Amortization Calculator

private enum DebtAmortization {

    /// Returns next occurrence of dueDay on or after the given date.
    static func nextDueDate(after base: Date, dueDay: Int, calendar: Calendar = .current) -> Date {
        var comps = calendar.dateComponents([.year, .month, .day], from: base)
        let baseDay = comps.day ?? 1
        let targetDay = min(dueDay, daysInMonth(year: comps.year ?? 2024, month: comps.month ?? 1))

        if baseDay < targetDay {
            comps.day = targetDay
            return calendar.date(from: comps) ?? base
        } else {
            // Move to next month
            let next = calendar.date(byAdding: .month, value: 1, to: base) ?? base
            var nextComps = calendar.dateComponents([.year, .month], from: next)
            nextComps.day = min(dueDay, daysInMonth(year: nextComps.year ?? 2024, month: nextComps.month ?? 1))
            return calendar.date(from: nextComps) ?? next
        }
    }

    static func nextDueDateAfter(month base: Date, dueDay: Int, calendar: Calendar = .current) -> Date {
        var comps = calendar.dateComponents([.year, .month], from: base)
        comps = calendar.dateComponents([.year, .month], from: calendar.date(byAdding: .month, value: 1, to: base) ?? base)
        comps.day = min(dueDay, daysInMonth(year: comps.year ?? 2024, month: comps.month ?? 1))
        return calendar.date(from: comps) ?? base
    }

    private static func daysInMonth(year: Int, month: Int) -> Int {
        var comps = DateComponents()
        comps.year = year
        comps.month = month + 1
        comps.day = 0
        return Calendar.current.dateComponents([.day], from: Calendar.current.date(from: comps) ?? Date()).day ?? 30
    }

    /// Builds the full amortization schedule, capped at 360 rows.
    static func schedule(
        remaining: Decimal,
        monthlyPayment: Decimal,
        annualRate: Decimal,
        dueDay: Int,
        startDate: Date
    ) -> [DebtAmortizationRow] {
        guard monthlyPayment > 0, remaining > 0 else { return [] }

        let monthlyRate = annualRate / 12
        var balance = remaining
        var rows: [DebtAmortizationRow] = []
        var date = nextDueDate(after: startDate, dueDay: dueDay)
        let cal = Calendar.current

        for i in 1...360 {
            guard balance > 0 else { break }

            let interestPortion: Decimal
            if monthlyRate > 0 {
                interestPortion = (balance * monthlyRate).rounded(scale: 2)
            } else {
                interestPortion = .zero
            }

            let maxPrincipal = balance
            let principalPortion = min(monthlyPayment - interestPortion, maxPrincipal)
            // If payment doesn't cover interest (edge case), clamp
            let actualPrincipal = max(principalPortion, .zero)
            let newBalance = max(balance - actualPrincipal, .zero)

            rows.append(DebtAmortizationRow(
                number: i,
                date: date,
                payment: min(monthlyPayment, balance + interestPortion),
                principal: actualPrincipal,
                interest: interestPortion,
                balance: newBalance
            ))

            balance = newBalance
            date = nextDueDateAfter(month: date, dueDay: dueDay, calendar: cal)
        }

        return rows
    }

    /// Simple schedule for 0%-interest installments: just N equal payments.
    static func installmentSchedule(
        remaining: Decimal,
        payment: Decimal,
        paymentsLeft: Int,
        dueDay: Int,
        startDate: Date
    ) -> [DebtAmortizationRow] {
        guard payment > 0, paymentsLeft > 0 else { return [] }

        var rows: [DebtAmortizationRow] = []
        var balance = remaining
        var date = nextDueDate(after: startDate, dueDay: dueDay)
        let cal = Calendar.current

        for i in 1...paymentsLeft {
            guard balance > 0 else { break }
            let actualPayment = min(payment, balance)
            let newBalance = balance - actualPayment

            rows.append(DebtAmortizationRow(
                number: i,
                date: date,
                payment: actualPayment,
                principal: actualPayment,
                interest: .zero,
                balance: newBalance
            ))

            balance = newBalance
            date = nextDueDateAfter(month: date, dueDay: dueDay, calendar: cal)
        }

        return rows
    }
}

// MARK: - DebtDetailView

struct DebtDetailView: View {
    let debt: Debt

    @State private var showingEdit = false

    private var isPaidOff: Bool { debt.remainingAmount <= 0 }
    private var paidAmount: Decimal { debt.totalAmount - debt.remainingAmount }

    // Amortization rows
    private var amortizationRows: [DebtAmortizationRow] {
        if isPaidOff { return [] }

        let isZeroInterest = debt.interestRate == 0

        if isZeroInterest && debt.type == .installment && debt.totalInstallments > 0 {
            let left = debt.totalInstallments - debt.paidInstallments
            guard left > 0 else { return [] }
            return DebtAmortization.installmentSchedule(
                remaining: debt.remainingAmount,
                payment: debt.minimumPayment,
                paymentsLeft: left,
                dueDay: debt.dueDay,
                startDate: Date()
            )
        }

        return DebtAmortization.schedule(
            remaining: debt.remainingAmount,
            monthlyPayment: debt.minimumPayment,
            annualRate: debt.interestRate,   // stored as fraction (0.045 = 4.5%)
            dueDay: debt.dueDay,
            startDate: Date()
        )
    }

    private var nextPaymentDate: Date? {
        amortizationRows.first?.date
    }

    private var payoffDate: Date? {
        amortizationRows.last?.date
    }

    private var remainingPaymentsCount: Int? {
        if isPaidOff || debt.minimumPayment == 0 { return nil }
        let count = amortizationRows.count
        return count > 0 ? count : nil
    }

    private var totalInterestRemaining: Decimal {
        amortizationRows.reduce(.zero) { $0 + $1.interest }
    }

    private var totalRemainingCost: Decimal {
        debt.remainingAmount + totalInterestRemaining
    }

    // Schedule display: cap at 24 rows for interest-bearing, full list for installments
    private var scheduleRows: [DebtAmortizationRow] {
        let isInstallment = debt.type == .installment && debt.interestRate == 0
        return isInstallment ? amortizationRows : Array(amortizationRows.prefix(24))
    }

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        ZStack {
            AppTheme.canvas
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    headerSection
                    paymentSummarySection
                    if debt.interestRate > 0 {
                        financialDetailsSection
                    }
                    if !amortizationRows.isEmpty {
                        scheduleSection
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .financeNavigationSurface()
        .navigationTitle(debt.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingEdit = true
                } label: {
                    Image(systemName: "pencil")
                }
            }
        }
        .sheet(isPresented: $showingEdit) {
            AddEditDebtView(debt: debt)
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 12) {
            HeroMetricCard(
                title: debt.name,
                value: CurrencyFormatter.string(from: debt.remainingAmount),
                supportingTitle: String(localized: "Monthly payment"),
                supportingValue: debt.minimumPayment > 0 ? CurrencyFormatter.string(from: debt.minimumPayment) : "—",
                note: String(localized: "Remaining balance and payoff pace for this debt."),
                badgeText: isPaidOff ? String(localized: "Paid") : debt.type.localizedName
            )

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 12
            ) {
                CompactSummaryCard(
                    title: String(localized: "Paid"),
                    value: CurrencyFormatter.string(from: paidAmount),
                    detail: String(format: String(localized: "%lld%% paid"), Int64((debt.progress * 100).rounded())),
                    systemImage: "checkmark.circle.fill",
                    tint: AppTheme.success
                )

                CompactSummaryCard(
                    title: String(localized: "Remaining"),
                    value: CurrencyFormatter.string(from: debt.remainingAmount),
                    detail: String(localized: "Outstanding balance"),
                    systemImage: "creditcard.fill",
                    tint: isPaidOff ? AppTheme.success : AppTheme.danger
                )

                CompactSummaryCard(
                    title: String(localized: "Next payment"),
                    value: nextPaymentDate.map { dateFormatter.string(from: $0) } ?? "—",
                    detail: String(localized: "Upcoming due date"),
                    systemImage: "calendar.badge.clock",
                    tint: AppTheme.info
                )

                CompactSummaryCard(
                    title: String(localized: "Payoff"),
                    value: payoffDate.map { dateFormatter.string(from: $0) } ?? "—",
                    detail: String(localized: "Estimated finish date"),
                    systemImage: "flag.checkered.2.crossed",
                    tint: AppTheme.warning
                )
            }
        }
    }

    // MARK: - Payment Summary Section

    private var paymentSummarySection: some View {
        SectionShell(
            title: String(localized: "Payment plan"),
            subtitle: String(localized: "The next key dates and cadence for this debt.")
        ) {
            VStack(spacing: 12) {
                if let nextDate = nextPaymentDate {
                    detailMetricRow(
                        title: String(localized: "Next Payment"),
                        value: dateFormatter.string(from: nextDate)
                    )
                }

                detailMetricRow(
                    title: String(localized: "Minimum Payment"),
                    value: debt.minimumPayment > 0 ? CurrencyFormatter.string(from: debt.minimumPayment) : "—"
                )

                detailMetricRow(
                    title: String(localized: "Remaining Payments"),
                    value: remainingPaymentsCount.map { "\($0) \(String(localized: "payments left"))" } ?? "—"
                )

                if let payoff = payoffDate {
                    detailMetricRow(
                        title: String(localized: "Payoff Date"),
                        value: dateFormatter.string(from: payoff),
                        tint: AppTheme.success
                    )
                }
            }
        }
    }

    // MARK: - Financial Details Section

    private var financialDetailsSection: some View {
        SectionShell(
            title: String(localized: "Cost breakdown"),
            subtitle: String(localized: "Interest and total cost if you keep the current payment pace.")
        ) {
            VStack(spacing: 12) {
                detailMetricRow(
                    title: String(localized: "Interest Rate (%)"),
                    value: String(format: "%.2f%%", NSDecimalNumber(decimal: debt.interestRate * 100).doubleValue),
                    tint: AppTheme.warning
                )

                detailMetricRow(
                    title: String(localized: "Interest"),
                    value: CurrencyFormatter.string(from: totalInterestRemaining),
                    tint: AppTheme.warning
                )

                detailMetricRow(
                    title: String(localized: "Total Cost"),
                    value: CurrencyFormatter.string(from: totalRemainingCost)
                )
            }
        }
    }

    // MARK: - Schedule Section

    private var scheduleSection: some View {
        SectionShell(
            title: String(localized: "Payment Schedule"),
            subtitle: String(localized: "Projected amortization based on the current payment amount.")
        ) {
            let isSimple = debt.interestRate == 0

            VStack(spacing: 0) {
                if amortizationRows.isEmpty {
                    Text(String(localized: "No payment data"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                } else if isSimple {
                    ForEach(scheduleRows) { row in
                        VStack(spacing: 0) {
                            HStack(spacing: 12) {
                                Text("\(row.number)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24, alignment: .leading)

                                Text(dateFormatter.string(from: row.date))
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Text(CurrencyFormatter.string(from: row.payment))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(AppTheme.primaryAccent)
                                    .frame(width: 90, alignment: .trailing)

                                Text(CurrencyFormatter.string(from: row.balance))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 90, alignment: .trailing)
                            }
                            .padding(.vertical, 10)

                            if row.id != scheduleRows.last?.id {
                                Divider()
                            }
                        }
                    }
                } else {
                    HStack(spacing: 12) {
                        Text("#")
                            .frame(width: 24, alignment: .leading)
                        Text(String(localized: "Date"))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(String(localized: "Principal"))
                            .frame(width: 78, alignment: .trailing)
                        Text(String(localized: "Interest"))
                            .frame(width: 78, alignment: .trailing)
                        Text(String(localized: "Balance"))
                            .frame(width: 82, alignment: .trailing)
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 10)

                    ForEach(scheduleRows) { row in
                        VStack(spacing: 0) {
                            HStack(spacing: 12) {
                                Text("\(row.number)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24, alignment: .leading)

                                Text(dateFormatter.string(from: row.date))
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Text(CurrencyFormatter.string(from: row.principal))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(AppTheme.primaryAccent)
                                    .frame(width: 78, alignment: .trailing)

                                Text(CurrencyFormatter.string(from: row.interest))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(AppTheme.warning)
                                    .frame(width: 78, alignment: .trailing)

                                Text(CurrencyFormatter.string(from: row.balance))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 82, alignment: .trailing)
                            }
                            .padding(.vertical, 10)

                            if row.id != scheduleRows.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }

    private func detailMetricRow(title: String, value: String, tint: Color = .primary) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Decimal Rounding Helper

private extension Decimal {
    func rounded(scale: Int) -> Decimal {
        var result = Decimal()
        var source = self
        NSDecimalRound(&result, &source, scale, .plain)
        return result
    }
}
