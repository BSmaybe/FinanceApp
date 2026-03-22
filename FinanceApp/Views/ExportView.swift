import SwiftUI
import SwiftData

struct ExportView: View {
    @Query private var allTransactions: [Transaction]
    @Query private var accounts: [Account]
    @Query private var categories: [Category]
    @Environment(\.dismiss) private var dismiss

    @State private var startDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var endDate = Date()
    @State private var format: ExportFormat = .csv
    @State private var isExporting = false

    enum ExportFormat: String, CaseIterable {
        case csv = "CSV"
        case pdf = "PDF"
    }

    private var filteredTransactions: [Transaction] {
        let start = Calendar.current.startOfDay(for: startDate)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: endDate)) ?? endDate
        return allTransactions.filter { $0.date >= start && $0.date < end }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "Date Range")) {
                    DatePicker(String(localized: "From"), selection: $startDate, displayedComponents: .date)
                    DatePicker(String(localized: "To"), selection: $endDate, displayedComponents: .date)
                }

                Section(String(localized: "Format")) {
                    Picker(String(localized: "Format"), selection: $format) {
                        ForEach(ExportFormat.allCases, id: \.self) { f in
                            Text(f.rawValue).tag(f)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section(String(localized: "Preview")) {
                    HStack {
                        Text(String(localized: "Transactions"))
                        Spacer()
                        Text("\(filteredTransactions.count)")
                            .foregroundStyle(.secondary)
                    }
                    if !filteredTransactions.isEmpty {
                        let income = filteredTransactions.filter { $0.type == .income }.reduce(Decimal.zero) { $0 + $1.amount }
                        let expense = filteredTransactions.filter { $0.type == .expense }.reduce(Decimal.zero) { $0 + $1.amount }
                        HStack {
                            Text(String(localized: "Income"))
                            Spacer()
                            Text(CurrencyFormatter.string(from: income))
                                .foregroundStyle(.green)
                        }
                        HStack {
                            Text(String(localized: "Expenses"))
                            Spacer()
                            Text(CurrencyFormatter.string(from: expense))
                                .foregroundStyle(.red)
                        }
                    }
                }

                Section {
                    Button {
                        exportData()
                    } label: {
                        HStack {
                            Spacer()
                            Label(String(localized: "Export"), systemImage: "square.and.arrow.up")
                                .font(.headline)
                            Spacer()
                        }
                    }
                    .disabled(filteredTransactions.isEmpty)
                }
            }
            .navigationTitle(String(localized: "Export Data"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
            }
        }
    }

    private func exportData() {
        let tempDir = FileManager.default.temporaryDirectory

        switch format {
        case .csv:
            let csv = ExportService.generateCSV(transactions: filteredTransactions, accounts: accounts, categories: categories)
            let url = tempDir.appendingPathComponent("transactions.csv")
            try? csv.write(to: url, atomically: true, encoding: .utf8)
            shareFile(url: url)

        case .pdf:
            let start = Calendar.current.startOfDay(for: startDate)
            let end = Calendar.current.startOfDay(for: endDate)
            let data = ExportService.generatePDF(transactions: filteredTransactions, accounts: accounts, categories: categories, dateRange: start...end)
            let url = tempDir.appendingPathComponent("transactions.pdf")
            try? data.write(to: url)
            shareFile(url: url)
        }
    }

    private func shareFile(url: URL) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else { return }

        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)

        // Find the topmost presented view controller
        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }
        topVC.present(activityVC, animated: true)
    }
}
