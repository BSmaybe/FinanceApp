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

    enum ExportFormat: String, CaseIterable {
        case csv = "CSV"
        case pdf = "PDF"
    }

    private var filteredTransactions: [Transaction] {
        let start = Calendar.current.startOfDay(for: startDate)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: endDate)) ?? endDate
        return allTransactions.filter { $0.date >= start && $0.date < end }
    }

    private var incomeTotal: Decimal {
        filteredTransactions.filter { $0.type == .income }.reduce(.zero) { $0 + $1.amount }
    }

    private var expenseTotal: Decimal {
        filteredTransactions.filter { $0.type == .expense }.reduce(.zero) { $0 + $1.amount }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.canvas.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        HeroMetricCard(
                            title: String(localized: "Export Data"),
                            value: "\(filteredTransactions.count)",
                            supportingTitle: String(localized: "Format"),
                            supportingValue: format.rawValue,
                            note: String(localized: "Choose a clean date range before sharing transactions out of the app."),
                            badgeText: String(localized: "Share")
                        )

                        SectionShell(
                            title: String(localized: "Date Range"),
                            subtitle: String(localized: "Export only the period you actually want to review or archive.")
                        ) {
                            VStack(spacing: 12) {
                                exportDatePicker(title: String(localized: "From"), selection: $startDate)
                                exportDatePicker(title: String(localized: "To"), selection: $endDate)
                            }
                        }

                        SectionShell(
                            title: String(localized: "Format"),
                            subtitle: String(localized: "Choose CSV for analysis or PDF for a readable snapshot.")
                        ) {
                            Picker(String(localized: "Format"), selection: $format) {
                                ForEach(ExportFormat.allCases, id: \.self) { value in
                                    Text(value.rawValue).tag(value)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        SectionShell(
                            title: String(localized: "Preview"),
                            subtitle: String(localized: "Check the range before exporting.")
                        ) {
                            VStack(spacing: 12) {
                                metricRow(title: String(localized: "Transactions"), value: "\(filteredTransactions.count)")
                                metricRow(
                                    title: String(localized: "Income"),
                                    value: CurrencyFormatter.string(from: incomeTotal),
                                    tint: AppTheme.success
                                )
                                metricRow(
                                    title: String(localized: "Expenses"),
                                    value: CurrencyFormatter.string(from: expenseTotal),
                                    tint: AppTheme.warning
                                )
                            }
                        }

                        Button(action: exportData) {
                            Label(String(localized: "Export"), systemImage: "square.and.arrow.up")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                        .background(filteredTransactions.isEmpty ? AppTheme.chartNeutral : AppTheme.primaryAccent)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .disabled(filteredTransactions.isEmpty)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .financeNavigationSurface()
            .navigationTitle(String(localized: "Export Data"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
            }
        }
    }

    private func exportDatePicker(title: String, selection: Binding<Date>) -> some View {
        DatePicker(title, selection: selection, displayedComponents: .date)
            .datePickerStyle(.compact)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(AppTheme.elevatedSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func metricRow(title: String, value: String, tint: Color = .primary) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(AppTheme.elevatedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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

        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }
        topVC.present(activityVC, animated: true)
    }
}
