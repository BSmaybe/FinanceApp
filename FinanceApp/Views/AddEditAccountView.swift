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
        if let a = account {
            _name = State(initialValue: a.name)
            _type = State(initialValue: a.type)
            _note = State(initialValue: a.note)
            _currencyCode = State(initialValue: a.currencyCode)
            _openingBalanceText = State(initialValue: a.openingBalance > 0 ? a.openingBalanceValue : "")
            _interestRateText = State(initialValue: a.interestRate > 0 ? a.interestRateValue : "")
        }
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "Name")) {
                    TextField(String(localized: "Account name"), text: $name)
                }
                Section(String(localized: "Type")) {
                    Picker(String(localized: "Type"), selection: $type) {
                        ForEach(AccountType.allCases, id: \.self) { t in
                            Text(t.localizedName).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section(String(localized: "Currency")) {
                    Picker(String(localized: "Currency"), selection: $currencyCode) {
                        ForEach(SupportedCurrency.allCases, id: \.rawValue) { currency in
                            Text(currency.name).tag(currency.rawValue)
                        }
                    }
                }
                Section {
                    LabeledContent(String(localized: "Opening Balance")) {
                        TextField("0", text: $openingBalanceText)
                            .financeNumericKeyboard()
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent(String(localized: "Annual Interest %")) {
                        TextField("0", text: $interestRateText)
                            .financeNumericKeyboard()
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text(String(localized: "Balance & Interest"))
                } footer: {
                    Text(String(localized: "Opening balance is not counted as income — it represents money already in this account."))
                        .font(.caption)
                }
                Section(String(localized: "Note")) {
                    TextField(String(localized: "Optional note"), text: $note)
                }
            }
            .keyboardDismissable()
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
                }
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let openingBalance = Decimal(string: openingBalanceText) ?? .zero
        let interestRate   = Decimal(string: interestRateText)   ?? .zero
        if let existing = existingAccount {
            existing.name = trimmedName
            existing.type = type
            existing.note = note
            existing.currencyCode = currencyCode
            existing.openingBalance = openingBalance
            existing.interestRate   = interestRate
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
