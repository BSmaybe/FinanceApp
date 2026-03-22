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
        List {
            headerSection
            paymentSummarySection
            if debt.interestRate > 0 {
                financialDetailsSection
            }
            if !amortizationRows.isEmpty {
                scheduleSection
            }
        }
        .navigationTitle(debt.name)
        .navigationBarTitleDisplayMode(.large)
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
        Section {
            VStack(alignment: .leading, spacing: 12) {
                // Name + type badge + paid-off indicator
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(debt.name)
                            .font(.title2.bold())

                        HStack(spacing: 6) {
                            Text(debt.type.localizedName)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(AppTheme.primaryAccent.opacity(0.12))
                                .foregroundStyle(AppTheme.primaryAccent)
                                .clipShape(Capsule())

                            if isPaidOff {
                                Label(String(localized: "Paid"), systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.success)
                            }
                        }
                    }

                    Spacer()

                    if debt.interestRate > 0 {
                        Text("\(NSDecimalNumber(decimal: debt.interestRate * 100).doubleValue, specifier: "%.1f")%")
                            .font(.headline)
                            .foregroundStyle(.orange)
                    }
                }

                // Progress bar
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: debt.progress)
                        .tint(isPaidOff ? AppTheme.success : AppTheme.primaryAccent)

                    HStack {
                        Text(String(format: String(localized: "%@ paid"), CurrencyFormatter.string(from: paidAmount)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(debt.progress * 100))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                // Remaining amount (large)
                HStack(alignment: .lastTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "Remaining"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(CurrencyFormatter.string(from: debt.remainingAmount))
                            .font(.title.bold())
                            .foregroundStyle(isPaidOff ? AppTheme.success : AppTheme.danger)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(localized: "Total"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(CurrencyFormatter.string(from: debt.totalAmount))
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }
                }
            }
            .padding(.vertical, 8)
            .listRowBackground(
                RoundedRectangle(cornerRadius: 12)
                    .fill(AppTheme.debtGradient)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
            )
        }
    }

    // MARK: - Payment Summary Section

    private var paymentSummarySection: some View {
        Section(String(localized: "Payment")) {
            if let nextDate = nextPaymentDate {
                LabeledContent(String(localized: "Next Payment")) {
                    Text(dateFormatter.string(from: nextDate))
                        .foregroundStyle(.primary)
                }
            }

            LabeledContent(String(localized: "Minimum Payment")) {
                Text(debt.minimumPayment > 0
                     ? CurrencyFormatter.string(from: debt.minimumPayment)
                     : "—")
                .foregroundStyle(.primary)
            }

            LabeledContent(String(localized: "Remaining Payments")) {
                if let count = remainingPaymentsCount {
                    Text("\(count) \(String(localized: "payments left"))")
                        .foregroundStyle(.primary)
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }

            if let payoff = payoffDate {
                LabeledContent(String(localized: "Payoff Date")) {
                    Text(dateFormatter.string(from: payoff))
                        .foregroundStyle(AppTheme.success)
                }
            }
        }
    }

    // MARK: - Financial Details Section

    private var financialDetailsSection: some View {
        Section(String(localized: "Details")) {
            LabeledContent(String(localized: "Interest Rate (%)")) {
                Text("\(NSDecimalNumber(decimal: debt.interestRate * 100).doubleValue, specifier: "%.2f")%")
                    .foregroundStyle(.orange)
            }

            LabeledContent(String(localized: "Interest")) {
                Text(CurrencyFormatter.string(from: totalInterestRemaining))
                    .foregroundStyle(.orange)
            }

            LabeledContent(String(localized: "Total Cost")) {
                Text(CurrencyFormatter.string(from: totalRemainingCost))
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
        }
    }

    // MARK: - Schedule Section

    private var scheduleSection: some View {
        Section(String(localized: "Payment Schedule")) {
            let isSimple = debt.interestRate == 0

            if isSimple {
                // Simple installment rows: Date | Amount | Balance
                ForEach(scheduleRows) { row in
                    HStack(spacing: 0) {
                        Text("\(row.number)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 28, alignment: .leading)

                        Text(dateFormatter.string(from: row.date))
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(CurrencyFormatter.string(from: row.payment))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(AppTheme.primaryAccent)
                            .frame(width: 80, alignment: .trailing)

                        Text(CurrencyFormatter.string(from: row.balance))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .trailing)
                    }
                }
            } else {
                // Full amortization table header
                HStack(spacing: 0) {
                    Text("#")
                        .frame(width: 28, alignment: .leading)
                    Text(String(localized: "Date"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(String(localized: "Principal"))
                        .frame(width: 70, alignment: .trailing)
                    Text(String(localized: "Interest"))
                        .frame(width: 70, alignment: .trailing)
                    Text(String(localized: "Balance"))
                        .frame(width: 72, alignment: .trailing)
                }
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
                .listRowBackground(Color.clear)

                ForEach(scheduleRows) { row in
                    VStack(spacing: 3) {
                        HStack(spacing: 0) {
                            Text("\(row.number)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 28, alignment: .leading)

                            Text(dateFormatter.string(from: row.date))
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text(CurrencyFormatter.string(from: row.principal))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(AppTheme.primaryAccent)
                                .frame(width: 70, alignment: .trailing)

                            Text(CurrencyFormatter.string(from: row.interest))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.orange)
                                .frame(width: 70, alignment: .trailing)

                            Text(CurrencyFormatter.string(from: row.balance))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 72, alignment: .trailing)
                        }
                    }
                }
            }

            if amortizationRows.isEmpty {
                Text(String(localized: "No payment data"))
                    .foregroundStyle(.secondary)
            }
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
