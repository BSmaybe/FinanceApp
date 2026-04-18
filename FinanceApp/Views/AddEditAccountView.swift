import SwiftUI
import SwiftData

struct AddEditAccountView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let existingAccount: Account?

    @State private var name: String = ""
    @State private var type: AccountType = .checking
    @State private var note: String = ""
    @State private var currencyCode: String = "KZT"
    @State private var openingBalanceText: String = ""
    @State private var interestRateText: String = ""

    init(account: Account? = nil) {
        self.existingAccount = account
        if let account {
            _name = State(initialValue: account.name)
            _type = State(initialValue: account.type)
            _note = State(initialValue: account.note)
            _currencyCode = State(initialValue: account.currencyCode)
            _openingBalanceText = State(initialValue: account.openingBalance > 0 ? account.openingBalanceValue : "")
            _interestRateText = State(initialValue: account.interestRate > 0 ? account.interestRateValue : "")
        }
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var localDecimalSeparator: String {
        Locale.current.decimalSeparator ?? "."
    }

    private var openingBalance: Decimal {
        Decimal(string: openingBalanceText.replacingOccurrences(of: localDecimalSeparator, with: ".")) ?? .zero
    }

    private var interestRate: Decimal {
        Decimal(string: interestRateText.replacingOccurrences(of: localDecimalSeparator, with: ".")) ?? .zero
    }

    private var selectedCurrency: SupportedCurrency? {
        SupportedCurrency(rawValue: currencyCode)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.canvas.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        heroSection

                        SectionShell(
                            title: String(localized: "Core setup"),
                            subtitle: String(localized: "Choose the account structure that best matches how money actually lives.")
                        ) {
                            VStack(spacing: 12) {
                                textField(title: String(localized: "Name"), text: $name, prompt: String(localized: "Account name"))

                                VStack(alignment: .leading, spacing: 8) {
                                    Text(String(localized: "Type"))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Picker(String(localized: "Type"), selection: $type) {
                                        ForEach(AccountType.allCases, id: \.self) { value in
                                            Text(value.localizedName).tag(value)
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
                            title: String(localized: "Currency"),
                            subtitle: String(localized: "Opening balance, currency, and interest define how this account behaves in the cockpit.")
                        ) {
                            VStack(spacing: 12) {
                                Picker(String(localized: "Currency"), selection: $currencyCode) {
                                    ForEach(SupportedCurrency.allCases, id: \.rawValue) { currency in
                                        Text(currency.name).tag(currency.rawValue)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 14)
                                .background(AppTheme.elevatedSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                                amountField(title: String(localized: "Opening Balance"), text: $openingBalanceText)
                                amountField(title: String(localized: "Annual Interest %"), text: $interestRateText)
                            }
                        }

                        SectionShell(
                            title: String(localized: "Notes"),
                            subtitle: String(localized: "Optional context for bank, purpose, or access rules.")
                        ) {
                            textField(title: String(localized: "Note"), text: $note, prompt: String(localized: "Optional note"))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .keyboardDismissable()
            .financeNavigationSurface()
            .navigationTitle(existingAccount == nil ? String(localized: "Add Account") : String(localized: "Edit Account"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) {
                        HapticManager.success()
                        save()
                        dismiss()
                    }
                    .disabled(!isValid)
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private var heroSection: some View {
        HeroMetricCard(
            title: existingAccount == nil ? String(localized: "Add Account") : String(localized: "Edit Account"),
            value: CurrencyFormatter.string(from: openingBalance),
            supportingTitle: String(localized: "Currency"),
            supportingValue: selectedCurrency?.symbol ?? currencyCode,
            note: String(localized: "Opening balance is not counted as income — it represents money already in this account."),
            badgeText: type.localizedName
        )
    }

    private func textField(title: String, text: Binding<String>, prompt: String) -> some View {
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
        }
    }

    private func amountField(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("0", text: text)
                .financeNumericKeyboard()
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(AppTheme.elevatedSurface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        if let existing = existingAccount {
            existing.name = trimmedName
            existing.type = type
            existing.note = note
            existing.currencyCode = currencyCode
            existing.openingBalance = openingBalance
            existing.interestRate = interestRate
        } else {
            modelContext.insert(Account(
                name: trimmedName,
                type: type,
                note: note,
                currencyCode: currencyCode,
                openingBalance: openingBalance,
                interestRate: interestRate
            ))
        }
        do {
            try modelContext.save()
        } catch {
            print("Save error: \(error)")
        }
    }
}
