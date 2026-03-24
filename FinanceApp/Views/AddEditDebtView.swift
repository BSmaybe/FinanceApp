import SwiftUI
import SwiftData

struct AddEditDebtView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var debt: Debt?

    @State private var name = ""
    @State private var type: DebtType = .loan
    @State private var totalAmountText = ""
    @State private var remainingAmountText = ""
    @State private var interestRateText = ""
    @State private var minimumPaymentText = ""
    @State private var dueDay = 1
    @State private var note = ""
    @State private var totalInstallments = 12
    @State private var totalPaymentsText = ""  // empty = auto-calculate
    @State private var showValidation = false

    private var isEditing: Bool { debt != nil }

    // MARK: - Validation

    private var parsedTotal: Decimal {
        Decimal(string: totalAmountText.replacingOccurrences(of: localDecimalSeparator, with: ".")) ?? .zero
    }
    private var parsedRemaining: Decimal {
        Decimal(string: remainingAmountText.replacingOccurrences(of: localDecimalSeparator, with: ".")) ?? .zero
    }
    private var parsedMinPayment: Decimal {
        Decimal(string: minimumPaymentText.replacingOccurrences(of: localDecimalSeparator, with: ".")) ?? .zero
    }

    private var nameError: String? {
        name.trimmingCharacters(in: .whitespaces).isEmpty ? String(localized: "Name is required") : nil
    }
    private var totalError: String? {
        parsedTotal <= 0 ? String(localized: "Enter the total debt amount") : nil
    }
    private var remainingError: String? {
        if parsedRemaining <= 0 { return String(localized: "Enter the remaining balance") }
        if parsedRemaining > parsedTotal && parsedTotal > 0 { return String(localized: "Remaining cannot exceed total") }
        return nil
    }
    private var minPaymentError: String? {
        parsedMinPayment <= 0 ? String(localized: "Enter the monthly payment amount") : nil
    }

    private var isValid: Bool {
        nameError == nil && totalError == nil && remainingError == nil && minPaymentError == nil
    }

    @ViewBuilder
    private func validationHint(_ message: String?) -> some View {
        if showValidation, let message {
            Text(message)
                .font(.caption)
                .foregroundStyle(AppTheme.danger)
        }
    }

    /// Auto-calculated total payments count shown as placeholder when field is empty.
    private var autoPaymentsPlaceholder: String {
        let sep = localDecimalSeparator
        // Use remaining amount (what's left to pay) — not total — so edit mode shows correct remaining count
        let remaining = Decimal(string: remainingAmountText.replacingOccurrences(of: sep, with: "."))
            ?? Decimal(string: totalAmountText.replacingOccurrences(of: sep, with: "."))
            ?? .zero
        let ratePercent = Decimal(string: interestRateText.replacingOccurrences(of: sep, with: ".")) ?? .zero
        let rate = ratePercent / 100
        let minPay = Decimal(string: minimumPaymentText.replacingOccurrences(of: sep, with: ".")) ?? .zero

        let autoLabel = String(localized: "Auto")
        guard minPay > 0, remaining > 0 else { return autoLabel }

        let r = NSDecimalNumber(decimal: rate / 12).doubleValue
        let payment = NSDecimalNumber(decimal: minPay).doubleValue
        let remainingD = NSDecimalNumber(decimal: remaining).doubleValue

        let n: Int
        if r > 0 {
            let denominator = payment - remainingD * r
            guard denominator > 0 else { return autoLabel }
            n = Int(ceil(log(payment / denominator) / log(1 + r)))
        } else {
            n = Int(ceil(remainingD / payment))
        }
        return "\(autoLabel) (\(n))"
    }

    private var localDecimalSeparator: String {
        Locale.current.decimalSeparator ?? "."
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "Details")) {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField(String(localized: "Name"), text: $name)
                        validationHint(nameError)
                    }
                    Picker(String(localized: "Type"), selection: $type) {
                        ForEach(DebtType.allCases, id: \.self) { t in
                            Text(t.localizedName).tag(t)
                        }
                    }
                    if type == .installment {
                        Text(String(localized: "Installments are typically interest-free (0%)."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section(String(localized: "Amounts")) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(String(localized: "Total"))
                            Spacer()
                            TextField("0", text: $totalAmountText)
                                .financeNumericKeyboard()
                                .multilineTextAlignment(.trailing)
                        }
                        validationHint(totalError)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(String(localized: "Remaining"))
                            Spacer()
                            TextField("0", text: $remainingAmountText)
                                .financeNumericKeyboard()
                                .multilineTextAlignment(.trailing)
                        }
                        validationHint(remainingError)
                    }
                }

                Section(String(localized: "Payment")) {
                    HStack {
                        Text(String(localized: "Interest Rate (%)"))
                        Spacer()
                        TextField("0", text: $interestRateText)
                            .financeNumericKeyboard()
                            .multilineTextAlignment(.trailing)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(String(localized: "Minimum Payment"))
                            Spacer()
                            TextField("0", text: $minimumPaymentText)
                                .financeNumericKeyboard()
                                .multilineTextAlignment(.trailing)
                        }
                        validationHint(minPaymentError)
                    }
                    HStack {
                        Text(String(localized: "Total Payments"))
                        Spacer()
                        TextField(autoPaymentsPlaceholder, text: $totalPaymentsText)
                            .financeNumericKeyboard()
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(totalPaymentsText.isEmpty ? .secondary : .primary)
                    }
                    Picker(String(localized: "Due Day"), selection: $dueDay) {
                        ForEach(1...28, id: \.self) { day in
                            Text("\(day)").tag(day)
                        }
                    }
                }

                Section(String(localized: "Notes")) {
                    TextField(String(localized: "Optional note"), text: $note)
                }
            }
            .keyboardDismissable()
            .financeNavigationSurface()
            .navigationTitle(isEditing ? String(localized: "Edit Debt") : String(localized: "New Debt"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) { save() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear { prefill() }
        }
    }

    private func prefill() {
        guard let debt else { return }
        name = debt.name
        type = debt.type
        totalAmountText = formatDecimal(debt.totalAmount)
        remainingAmountText = formatDecimal(debt.remainingAmount)
        interestRateText = formatDecimal(debt.interestRate * 100) // store as %, display as %
        minimumPaymentText = formatDecimal(debt.minimumPayment)
        dueDay = debt.dueDay
        note = debt.note
        totalInstallments = debt.totalInstallments
        totalPaymentsText = debt.totalInstallments > 0 ? "\(debt.totalInstallments)" : ""
    }

    private func save() {
        guard isValid else {
            HapticManager.error()
            showValidation = true
            return
        }
        HapticManager.success()
        let sep = localDecimalSeparator
        let total = Decimal(string: totalAmountText.replacingOccurrences(of: sep, with: ".")) ?? .zero
        let remaining = Decimal(string: remainingAmountText.replacingOccurrences(of: sep, with: ".")) ?? total
        let ratePercent = Decimal(string: interestRateText.replacingOccurrences(of: sep, with: ".")) ?? .zero
        let rate = ratePercent / 100
        let minPay = Decimal(string: minimumPaymentText.replacingOccurrences(of: sep, with: ".")) ?? .zero

        // Use manually entered count, or auto-calculate from remaining amount
        let installments: Int
        if let entered = Int(totalPaymentsText), entered > 0 {
            installments = entered
        } else {
            let r = NSDecimalNumber(decimal: rate / 12).doubleValue
            let payment = NSDecimalNumber(decimal: minPay).doubleValue
            let remainingD = NSDecimalNumber(decimal: remaining).doubleValue
            if minPay > 0, remaining > 0 {
                if r > 0 {
                    let denominator = payment - remainingD * r
                    installments = denominator > 0 ? Int(ceil(log(payment / denominator) / log(1 + r))) : 0
                } else {
                    installments = Int(ceil(remainingD / payment))
                }
            } else {
                installments = 0
            }
        }
        if let debt {
            debt.name = name
            debt.type = type
            debt.totalAmount = total
            debt.remainingAmount = remaining
            debt.interestRate = rate
            debt.minimumPayment = minPay
            debt.dueDay = dueDay
            debt.note = note
            debt.totalInstallments = installments
        } else {
            let newDebt = Debt(
                name: name,
                totalAmount: total,
                remainingAmount: remaining,
                interestRate: rate,
                minimumPayment: minPay,
                dueDay: dueDay,
                type: type,
                note: note,
                totalInstallments: installments
            )
            modelContext.insert(newDebt)
        }
        dismiss()
    }

    private func formatDecimal(_ value: Decimal) -> String {
        let str = (value as NSDecimalNumber).stringValue
        return str.replacingOccurrences(of: ".", with: localDecimalSeparator)
    }
}
