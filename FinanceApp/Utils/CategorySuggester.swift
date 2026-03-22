import Foundation

enum CategorySuggester {
    /// Returns suggested category for a given note text, based on transaction history.
    /// Matches by finding transactions whose note contains any word from the query (case-insensitive, 3+ chars).
    /// Returns the most frequently used category for matching transactions.
    /// Returns nil if no match or fewer than 2 matches found.
    static func suggest(for note: String, transactions: [Transaction], categories: [Category]) -> Category? {
        let queryWords = tokenize(note)
        guard !queryWords.isEmpty else { return nil }

        let categoryMap = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        var categoryCount: [UUID: Int] = [:]

        for txn in transactions {
            guard !txn.note.isEmpty, let catId = txn.categoryId else { continue }
            let txnWords = tokenize(txn.note)
            let hasMatch = queryWords.contains { txnWords.contains($0) }
            guard hasMatch else { continue }
            categoryCount[catId, default: 0] += 1
        }

        guard let best = categoryCount.max(by: { $0.value < $1.value }),
              best.value >= 2 else { return nil }

        return categoryMap[best.key]
    }

    private static func tokenize(_ text: String) -> Set<String> {
        let words = text.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count >= 3 }
        return Set(words)
    }
}
