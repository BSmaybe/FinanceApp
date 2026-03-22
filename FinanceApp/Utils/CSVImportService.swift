import Foundation
import SwiftData

enum CSVImportService {

    struct ImportResult {
        let imported: Int
        let skipped: Int
        let errors: [String]
    }

    /// Parses CSV exported by ExportService (Date,Amount,Type,Category,Account,Note)
    /// Matches accounts and categories by name (case-insensitive).
    /// Creates missing categories with a default color.
    /// Falls back to the first available account if no match found.
    static func importCSV(_ data: Data, context: ModelContext) throws -> ImportResult {
        guard let content = String(data: data, encoding: .utf8) else {
            throw ImportError.invalidEncoding
        }

        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard lines.count >= 2 else { throw ImportError.emptyFile }

        // Validate header
        let header = parseCSVLine(lines[0]).map { $0.lowercased() }
        guard header.contains("date") && header.contains("amount") && header.contains("type") else {
            throw ImportError.invalidHeader
        }

        // Column indices
        let dateIdx    = header.firstIndex(of: "date") ?? 0
        let amountIdx  = header.firstIndex(of: "amount") ?? 1
        let typeIdx    = header.firstIndex(of: "type") ?? 2
        let catIdx     = header.firstIndex(of: "category") ?? 3
        let acctIdx    = header.firstIndex(of: "account") ?? 4
        let noteIdx    = header.firstIndex(of: "note") ?? 5

        // Fetch existing data for matching
        let accounts   = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        let categories = (try? context.fetch(FetchDescriptor<Category>())) ?? []

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")

        var imported = 0, skipped = 0
        var errors: [String] = []

        for (lineNum, line) in lines.dropFirst().enumerated() {
            let row = parseCSVLine(line)
            guard row.count > max(dateIdx, amountIdx, typeIdx) else {
                skipped += 1
                continue
            }

            // Date
            guard let date = df.date(from: row[safe: dateIdx] ?? "") else {
                errors.append("Line \(lineNum + 2): invalid date '\(row[safe: dateIdx] ?? "")'")
                skipped += 1
                continue
            }

            // Amount
            let amountStr = (row[safe: amountIdx] ?? "").replacingOccurrences(of: ",", with: ".")
            guard let amount = Decimal(string: amountStr), amount > 0 else {
                errors.append("Line \(lineNum + 2): invalid amount")
                skipped += 1
                continue
            }

            // Type
            let typeStr = row[safe: typeIdx] ?? ""
            guard let type = TransactionType(rawValue: typeStr) else {
                errors.append("Line \(lineNum + 2): unknown type '\(typeStr)'")
                skipped += 1
                continue
            }

            // Account — match by name, fallback to first
            let acctName = row[safe: acctIdx] ?? ""
            let account = accounts.first { $0.name.lowercased() == acctName.lowercased() }
                ?? accounts.first

            guard let account else {
                errors.append("Line \(lineNum + 2): no accounts found in app")
                skipped += 1
                continue
            }

            // Category — match by name, create if missing (income/expense only)
            var categoryId: UUID? = nil
            if type != .transfer {
                let catName = row[safe: catIdx] ?? ""
                if !catName.isEmpty {
                    if let existing = categories.first(where: { $0.name.lowercased() == catName.lowercased() }) {
                        categoryId = existing.id
                    } else {
                        // Create new category
                        let newCat = Category(
                            name: catName,
                            type: type == .income ? .income : .expense,
                            colorHex: "#888888",
                            iconName: "folder"
                        )
                        context.insert(newCat)
                        categoryId = newCat.id
                    }
                }
            }

            let note = row[safe: noteIdx] ?? ""
            let txn = Transaction(
                date: date,
                amount: amount,
                type: type,
                accountId: account.id,
                categoryId: categoryId,
                note: note
            )
            context.insert(txn)
            imported += 1
        }

        try context.save()
        return ImportResult(imported: imported, skipped: skipped, errors: errors)
    }

    // MARK: - CSV line parser (handles quoted fields with commas)

    private static func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false

        for ch in line {
            if ch == "\"" {
                inQuotes.toggle()
            } else if ch == "," && !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(ch)
            }
        }
        fields.append(current)
        return fields
    }

    enum ImportError: LocalizedError {
        case invalidEncoding
        case emptyFile
        case invalidHeader

        var errorDescription: String? {
            switch self {
            case .invalidEncoding: return String(localized: "Cannot read file (invalid encoding)")
            case .emptyFile:       return String(localized: "File is empty or has no data rows")
            case .invalidHeader:   return String(localized: "Invalid CSV format. Expected columns: Date, Amount, Type, Category, Account, Note")
            }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
