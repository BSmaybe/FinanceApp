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

    init(account: Account? = nil) {
        self.existingAccount = account
        if let a = account {
            _name = State(initialValue: a.name)
            _type = State(initialValue: a.type)
            _note = State(initialValue: a.note)
            _currencyCode = State(initialValue: a.currencyCode)
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
                Section(String(localized: "Note")) {
                    TextField(String(localized: "Optional note"), text: $note)
                }
            }
            .navigationTitle(existingAccount == nil ? String(localized: "Add Account") : String(localized: "Edit Account"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) {
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
        if let existing = existingAccount {
            existing.name = trimmedName
            existing.type = type
            existing.note = note
            existing.currencyCode = currencyCode
        } else {
            modelContext.insert(Account(name: trimmedName, type: type, note: note, currencyCode: currencyCode))
        }
        do {
            try modelContext.save()
        } catch {
            print("Save error: \(error)")
        }
    }
}
