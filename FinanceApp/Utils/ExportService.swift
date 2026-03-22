import Foundation
import UIKit

enum ExportService {
    @MainActor
    static func generateCSV(transactions: [Transaction], accounts: [Account], categories: [Category]) -> String {
        let accountMap = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.name) })
        let categoryMap = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.name) })

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"

        var csv = "Date,Amount,Type,Category,Account,Note\n"
        for txn in transactions.sorted(by: { $0.date > $1.date }) {
            let date = df.string(from: txn.date)
            let amount = (txn.amount as NSDecimalNumber).stringValue
            let type = txn.type.rawValue
            let category = txn.categoryId.flatMap { categoryMap[$0] } ?? ""
            let account = accountMap[txn.accountId] ?? ""
            let note = txn.note
                .replacingOccurrences(of: "\"", with: "\"\"")
            csv += "\(date),\(amount),\(type),\"\(category)\",\"\(account)\",\"\(note)\"\n"
        }
        return csv
    }

    @MainActor
    static func generatePDF(transactions: [Transaction], accounts: [Account], categories: [Category], dateRange: ClosedRange<Date>) -> Data {
        let filtered = transactions.filter { dateRange.contains($0.date) }.sorted { $0.date > $1.date }
        let categoryMap = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.name) })

        let pageWidth: CGFloat = 612
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 40

        let df = DateFormatter()
        df.dateStyle = .medium

        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        )

        return renderer.pdfData { context in
            context.beginPage()
            var y: CGFloat = margin

            // Title
            let titleAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 20)]
            (String(localized: "Transaction Report") as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: titleAttrs)
            y += 30

            // Date range
            let rangeAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12), .foregroundColor: UIColor.gray]
            ("\(df.string(from: dateRange.lowerBound)) – \(df.string(from: dateRange.upperBound))" as NSString)
                .draw(at: CGPoint(x: margin, y: y), withAttributes: rangeAttrs)
            y += 25

            // Summary
            let totalIncome = filtered.filter { $0.type == .income }.reduce(Decimal.zero) { $0 + $1.amount }
            let totalExpense = filtered.filter { $0.type == .expense }.reduce(Decimal.zero) { $0 + $1.amount }
            let summaryAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 14)]
            let summaryText = "\(String(localized: "Income")): \(CurrencyFormatter.string(from: totalIncome))  |  \(String(localized: "Expenses")): \(CurrencyFormatter.string(from: totalExpense))"
            (summaryText as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: summaryAttrs)
            y += 30

            // Table header
            let headerAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 10)]
            let rowAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10)]
            let cols: [(String, CGFloat)] = [
                (String(localized: "Date"), margin),
                (String(localized: "Amount"), margin + 100),
                (String(localized: "Type"), margin + 200),
                (String(localized: "Category"), margin + 280),
                (String(localized: "Note"), margin + 400)
            ]
            for (title, x) in cols {
                (title as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: headerAttrs)
            }
            y += 18

            // Rows
            for txn in filtered {
                if y > pageHeight - margin - 20 {
                    context.beginPage()
                    y = margin
                }
                let values: [(String, CGFloat)] = [
                    (df.string(from: txn.date), cols[0].1),
                    (CurrencyFormatter.string(from: txn.amount), cols[1].1),
                    (txn.type.rawValue, cols[2].1),
                    (txn.categoryId.flatMap { categoryMap[$0] } ?? "-", cols[3].1),
                    (String(txn.note.prefix(25)), cols[4].1)
                ]
                for (text, x) in values {
                    (text as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: rowAttrs)
                }
                y += 16
            }

            // Footer: count
            y += 10
            if y > pageHeight - margin - 30 {
                context.beginPage()
                y = margin
            }
            let footerAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.italicSystemFont(ofSize: 10), .foregroundColor: UIColor.gray]
            ("\(String(localized: "Total transactions")): \(filtered.count)" as NSString)
                .draw(at: CGPoint(x: margin, y: y), withAttributes: footerAttrs)
        }
    }
}
