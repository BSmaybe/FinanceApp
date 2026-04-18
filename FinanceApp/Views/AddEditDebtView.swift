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
    @State private var totalPaymentsText = ""
    @State private var showValidation = false

    private var isEditing: Bool { debt != nil }

    private var parsedTotal: Decimal {
        decimal(from: totalAmountText)
    }

    private var parsedRemaining: Decimal {
        decimal(from: remainingAmountText)
    }

    private var parsedMinPayment: Decimal {
        decimal(from: minimumPaymentText)
    }

    private var parsedInterestRatePercent: Decimal {
        decimal(from: interestRateText)
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

    private var localDecimalSeparator: String {
        Locale.current.decimalSeparator ?? "."
    }

    private var heroBalance: Decimal {
        parsedRemaining > .zero ? parsedRemaining : parsedTotal
    }

    private var monthlyInterestRate: Decimal {
        parsedInterestRatePercent / 100 / 12
    }

    private var autoPaymentsPlaceholder: String {
        let autoLabel = String(localized: "Auto")
        guard parsedMinPayment > 0, heroBalance > 0 else { return autoLabel }

        let r = NSDecimalNumber(decimal: monthlyInterestRate).doubleValue
        let payment = NSDecimalNumber(decimal: parsedMinPayment).doubleValue
        let remaining = NSDecimalNumber(decimal: heroBalance).doubleValue

        let count: Int
        if r > 0 {
            let denominator = payment - remaining * r
            guard denominator > 0 else { return autoLabel }
            count = Int(ceil(log(payment / denominator) / log(1 + r)))
        } else {
            count = Int(ceil(remaining / payment))
        }
        return "\(autoLabel) (\(count))"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.canvas.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        heroSection

                        SectionShell(
                            title: String(localized: "Details"),
                            subtitle: String(localized: "Set the core debt details before you model the payoff.")
                        ) {
                            VStack(spacing: 12) {
                                formField(
                                    title: String(localized: "Name"),
                                    text: $name,
                                    prompt: String(localized: "Name"),
                                    error: nameError
                                )

                                VStack(alignment: .leading, spacing: 8) {
                                    Text(String(localized: "Type"))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Picker(String(localized: "Type"), selection: $type) {
                                        ForEach(DebtType.allCases, id: \.self) { value in
                                            Text(value.localizedName).tag(value)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 14)
                                    .background(AppTheme.elevatedSurface)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                                    if type == .installment {
                                        Text(String(localized: "Installments are typically interest-free (0%)."))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }

                        SectionShell(
                            title: String(localized: "Amounts"),
                            subtitle: String(localized: "Use current balances and payments so forecasts stay realistic.")
                        ) {
                            VStack(spacing: 12) {
                                amountField(
                                    title: String(localized: "Total"),
                                    text: $totalAmountText,
                                    error: totalError
                                )

                                amountField(
                                    title: String(localized: "Remaining"),
                                    text: $remainingAmountText,
                                    error: remainingError
                                )
                            }
                        }

                        SectionShell(
                            title: String(localized: "Payment"),
                            subtitle: String(localized: "Payment rhythm and cost assumptions drive the payoff path.")
                        ) {
                            VStack(spacing: 12) {
                                amountField(
                                    title: String(localized: "Interest Rate (%)"),
                                    text: $interestRateText
                                )

                                amountField(
                                    title: String(localized: "Minimum Payment"),
                                    text: $minimumPaymentText,
                                    error: minPaymentError
                                )

                                amountField(
                                    title: String(localized: "Total Payments"),
                                    text: $totalPaymentsText,
                                    prompt: autoPaymentsPlaceholder,
                                    usesSecondaryPrompt: totalPaymentsText.isEmpty
                                )

                                VStack(alignment: .leading, spacing: 8) {
                                    Text(String(localized: "Due Day"))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Picker(String(localized: "Due Day"), selection: $dueDay) {
                                        ForEach(1...28, id: \.self) { day in
                                            Text("\(day)").tag(day)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 14)
                                    .background(AppTheme.elevatedSurface)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                }
                            }
                        }

                        SectionShell(
                            title: String(localized: "Notes"),
                            subtitle: String(localized: "Optional context for lender, terms, or payoff notes.")
                        ) {
                            formField(
                                title: String(localized: "Notes"),
                                text: $note,
                                prompt: String(localized: "Optional note")
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
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

    private var heroSection: some View {
        HeroMetricCard(
            title: isEditing ? String(localized: "Edit Debt") : String(localized: "New Debt"),
            value: CurrencyFormatter.string(from: heroBalance),
            supportingTitle: String(localized: "Minimum Payment"),
            supportingValue: CurrencyFormatter.string(from: parsedMinPayment),
            note: String(localized: "Remaining balance and payment shape the payoff path."),
            badgeText: type.localizedName
        )
    }

    private func formField(title: String, text: Binding<String>, prompt: String, error: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(prompt, text: text)
                .textInputAutocapitalization(.words)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(AppTheme.elevatedSurface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            validationHint(error)
        }
    }

    private func amountField(
        title: String,
        text: Binding<String>,
        prompt: String = "0",
        error: String? = nil,
        usesSecondaryPrompt: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(prompt, text: text)
                .financeNumericKeyboard()
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundStyle(usesSecondaryPrompt ? .secondary : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(AppTheme.elevatedSurface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            validationHint(error)
        }
    }

    @ViewBuilder
    private func validationHint(_ message: String?) -> some View {
        if showValidation, let message {
            Text(message)
                .font(.caption)
                .foregroundStyle(AppTheme.danger)
        }
    }

    private func prefill() {
        guard let debt else { return }
        name = debt.name
        type = debt.type
        totalAmountText = formatDecimal(debt.totalAmount)
        remainingAmountText = formatDecimal(debt.remainingAmount)
        interestRateText = formatDecimal(debt.interestRate * 100)
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

        let total = parsedTotal
        let remaining = parsedRemaining > .zero ? parsedRemaining : total
        let rate = parsedInterestRatePercent / 100
        let minimumPayment = parsedMinPayment

        let installments: Int
        if let entered = Int(totalPaymentsText), entered > 0 {
            installments = entered
        } else {
            let r = NSDecimalNumber(decimal: rate / 12).doubleValue
            let payment = NSDecimalNumber(decimal: minimumPayment).doubleValue
            let remainingValue = NSDecimalNumber(decimal: remaining).doubleValue
            if minimumPayment > 0, remaining > 0 {
                if r > 0 {
                    let denominator = payment - remainingValue * r
                    installments = denominator > 0 ? Int(ceil(log(payment / denominator) / log(1 + r))) : 0
                } else {
                    installments = Int(ceil(remainingValue / payment))
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
            debt.minimumPayment = minimumPayment
            debt.dueDay = dueDay
            debt.note = note
            debt.totalInstallments = installments
        } else {
            let newDebt = Debt(
                name: name,
                totalAmount: total,
                remainingAmount: remaining,
                interestRate: rate,
                minimumPayment: minimumPayment,
                dueDay: dueDay,
                type: type,
                note: note,
                totalInstallments: installments
            )
            modelContext.insert(newDebt)
        }

        dismiss()
    }

    private func decimal(from text: String) -> Decimal {
        Decimal(string: text.replacingOccurrences(of: localDecimalSeparator, with: ".")) ?? .zero
    }

    private func formatDecimal(_ value: Decimal) -> String {
        let string = (value as NSDecimalNumber).stringValue
        return string.replacingOccurrences(of: ".", with: localDecimalSeparator)
    }
}
