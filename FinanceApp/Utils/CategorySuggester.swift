import Foundation

enum CategorySuggester {
    /// Returns up to 3 suggested category IDs, ranked by confidence.
    /// - Parameters:
    ///   - note: current note/merchant text being typed
    ///   - amount: current amount
    ///   - type: transaction type (only match same type)
    ///   - transactions: all historical transactions
    static func suggest(
        note: String,
        amount: Decimal,
        type: TransactionType,
        from transactions: [Transaction]
    ) -> [UUID] {
        let now = Date()
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now

        let candidates = transactions.filter { $0.type == type && $0.categoryId != nil }

        var scores: [UUID: Double] = [:]

        let noteTokens = tokenize(note)

        if noteTokens.count > 0 {
            for txn in candidates {
                guard let catId = txn.categoryId else { continue }
                let txnTokens = tokenize(txn.note)
                let overlap = noteTokens.filter { txnTokens.contains($0) }.count
                guard overlap > 0 else { continue }
                let recency = txn.date >= thirtyDaysAgo ? 2.0 : 1.0
                scores[catId, default: 0] += Double(overlap) * recency
            }
        }

        // Fall back to most-used category if note is empty or no scores found
        if note.count < 2 || scores.values.max() == nil || scores.values.max() == 0 {
            scores = [:]
            if amount > 0 {
                let lower = amount * Decimal(0.8)
                let upper = amount * Decimal(1.2)
                for txn in candidates {
                    guard let catId = txn.categoryId else { continue }
                    if txn.amount >= lower && txn.amount <= upper {
                        let recency = txn.date >= thirtyDaysAgo ? 2.0 : 1.0
                        scores[catId, default: 0] += recency
                    }
                }
            }

            // If still empty, use overall most-used
            if scores.isEmpty {
                for txn in candidates {
                    guard let catId = txn.categoryId else { continue }
                    let recency = txn.date >= thirtyDaysAgo ? 2.0 : 1.0
                    scores[catId, default: 0] += recency
                }
            }
        }

        let sorted = scores
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { $0.key }

        return Array(sorted)
    }

    private static func tokenize(_ text: String) -> Set<String> {
        let words = text.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count >= 3 }
        return Set(words)
    }
}
