import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Codable backup structs

struct BackupData: Codable {
    let version: Int
    let exportDate: Date
    let accounts: [AccountBackup]
    let categories: [CategoryBackup]
    let transactions: [TransactionBackup]
    let budgets: [BudgetBackup]
    let subscriptions: [SubscriptionBackup]
    let debts: [DebtBackup]
    let goals: [GoalBackup]
    let recurringTransactions: [RecurringTransactionBackup]
}

struct AccountBackup: Codable {
    let id: UUID
    let name: String
    let type: String
    let note: String
    let currencyCode: String
}

struct CategoryBackup: Codable {
    let id: UUID
    let name: String
    let type: String
    let colorHex: String
    let iconName: String
}

struct TransactionBackup: Codable {
    let id: UUID
    let date: Date
    let amountValue: String
    let type: String
    let accountId: UUID
    let toAccountId: UUID?
    let categoryId: UUID?
    let note: String
    let tagsRaw: String
}

struct BudgetBackup: Codable {
    let id: UUID
    let categoryId: UUID
    let amount: String
    let month: Int
    let year: Int
}

struct SubscriptionBackup: Codable {
    let id: UUID
    let name: String
    let amountValue: String
    let frequency: String
    let categoryId: UUID?
    let nextBillingDate: Date
    let note: String
    let isActive: Bool
}

struct DebtBackup: Codable {
    let id: UUID
    let name: String
    let totalValue: String
    let remainingValue: String
    let interestRateValue: String
    let minimumPaymentValue: String
    let dueDay: Int
    let type: String
    let note: String
    let totalInstallments: Int
}

struct GoalBackup: Codable {
    let id: UUID
    let name: String
    let targetValue: String
    let currentValue: String
    let note: String
    let createdDate: Date
}

struct RecurringTransactionBackup: Codable {
    let id: UUID
    let title: String
    let amountValue: String
    let type: String
    let accountId: UUID
    let toAccountId: UUID?
    let categoryId: UUID?
    let note: String
    let frequency: String
    let startDate: Date
    let lastGeneratedDate: Date?
    let isActive: Bool
}

// MARK: - BackupService

enum BackupService {

    static func exportData(context: ModelContext) throws -> Data {
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        let categories = (try? context.fetch(FetchDescriptor<Category>())) ?? []
        let transactions = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
        let budgets = (try? context.fetch(FetchDescriptor<Budget>())) ?? []
        let subscriptions = (try? context.fetch(FetchDescriptor<Subscription>())) ?? []
        let debts = (try? context.fetch(FetchDescriptor<Debt>())) ?? []
        let goals = (try? context.fetch(FetchDescriptor<Goal>())) ?? []
        let recurring = (try? context.fetch(FetchDescriptor<RecurringTransaction>())) ?? []

        let backup = BackupData(
            version: 1,
            exportDate: Date(),
            accounts: accounts.map {
                AccountBackup(id: $0.id, name: $0.name, type: $0.type.rawValue, note: $0.note, currencyCode: $0.currencyCode)
            },
            categories: categories.map {
                CategoryBackup(id: $0.id, name: $0.name, type: $0.type.rawValue, colorHex: $0.colorHex, iconName: $0.iconName)
            },
            transactions: transactions.map {
                TransactionBackup(id: $0.id, date: $0.date, amountValue: $0.amountValue, type: $0.type.rawValue, accountId: $0.accountId, toAccountId: $0.toAccountId, categoryId: $0.categoryId, note: $0.note, tagsRaw: $0.tagsRaw)
            },
            budgets: budgets.map {
                BudgetBackup(id: $0.id, categoryId: $0.categoryId, amount: $0.amount, month: $0.month, year: $0.year)
            },
            subscriptions: subscriptions.map {
                SubscriptionBackup(id: $0.id, name: $0.name, amountValue: $0.amountValue, frequency: $0.frequency.rawValue, categoryId: $0.categoryId, nextBillingDate: $0.nextBillingDate, note: $0.note, isActive: $0.isActive)
            },
            debts: debts.map {
                DebtBackup(id: $0.id, name: $0.name, totalValue: $0.totalValue, remainingValue: $0.remainingValue, interestRateValue: $0.interestRateValue, minimumPaymentValue: $0.minimumPaymentValue, dueDay: $0.dueDay, type: $0.type.rawValue, note: $0.note, totalInstallments: $0.totalInstallments)
            },
            goals: goals.map {
                GoalBackup(id: $0.id, name: $0.name, targetValue: $0.targetValue, currentValue: $0.currentValue, note: $0.note, createdDate: $0.createdDate)
            },
            recurringTransactions: recurring.map {
                RecurringTransactionBackup(id: $0.id, title: $0.title, amountValue: $0.amountValue, type: $0.type.rawValue, accountId: $0.accountId, toAccountId: $0.toAccountId, categoryId: $0.categoryId, note: $0.note, frequency: $0.frequency.rawValue, startDate: $0.startDate, lastGeneratedDate: $0.lastGeneratedDate, isActive: $0.isActive)
            }
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(backup)
    }

    static func importData(_ data: Data, context: ModelContext) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(BackupData.self, from: data)

        // Clear existing data
        try context.delete(model: Transaction.self)
        try context.delete(model: Budget.self)
        try context.delete(model: Subscription.self)
        try context.delete(model: Debt.self)
        try context.delete(model: Goal.self)
        try context.delete(model: RecurringTransaction.self)
        try context.delete(model: Category.self)
        try context.delete(model: Account.self)

        // Restore accounts
        for a in backup.accounts {
            let account = Account(id: a.id, name: a.name, type: AccountType(rawValue: a.type) ?? .cash, note: a.note, currencyCode: a.currencyCode)
            context.insert(account)
        }

        // Restore categories
        for c in backup.categories {
            let cat = Category(id: c.id, name: c.name, type: CategoryType(rawValue: c.type) ?? .expense, colorHex: c.colorHex, iconName: c.iconName)
            context.insert(cat)
        }

        // Restore transactions
        for t in backup.transactions {
            let txn = Transaction(id: t.id, date: t.date, amount: Decimal(string: t.amountValue) ?? .zero, type: TransactionType(rawValue: t.type) ?? .expense, accountId: t.accountId, toAccountId: t.toAccountId, categoryId: t.categoryId, note: t.note, tags: t.tagsRaw.isEmpty ? [] : t.tagsRaw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
            context.insert(txn)
        }

        // Restore budgets
        for b in backup.budgets {
            let budget = Budget(categoryId: b.categoryId, limitAmount: Decimal(string: b.amount) ?? .zero, month: b.month, year: b.year)
            budget.id = b.id
            context.insert(budget)
        }

        // Restore subscriptions
        for s in backup.subscriptions {
            let sub = Subscription(name: s.name, amount: Decimal(string: s.amountValue) ?? .zero, frequency: RecurringFrequency(rawValue: s.frequency) ?? .monthly, categoryId: s.categoryId, nextBillingDate: s.nextBillingDate, note: s.note, isActive: s.isActive)
            sub.id = s.id
            context.insert(sub)
        }

        // Restore debts
        for d in backup.debts {
            let debt = Debt(name: d.name, totalAmount: Decimal(string: d.totalValue) ?? .zero, remainingAmount: Decimal(string: d.remainingValue) ?? .zero, interestRate: Decimal(string: d.interestRateValue) ?? .zero, minimumPayment: Decimal(string: d.minimumPaymentValue) ?? .zero, dueDay: d.dueDay, type: DebtType(rawValue: d.type) ?? .other, note: d.note, totalInstallments: d.totalInstallments)
            debt.id = d.id
            context.insert(debt)
        }

        // Restore goals
        for g in backup.goals {
            let goal = Goal(id: g.id, name: g.name, targetAmount: Decimal(string: g.targetValue) ?? .zero, currentAmount: Decimal(string: g.currentValue) ?? .zero, note: g.note, createdDate: g.createdDate)
            context.insert(goal)
        }

        // Restore recurring transactions
        for r in backup.recurringTransactions {
            let rec = RecurringTransaction(title: r.title, amount: Decimal(string: r.amountValue) ?? .zero, type: TransactionType(rawValue: r.type) ?? .expense, accountId: r.accountId, toAccountId: r.toAccountId, categoryId: r.categoryId, note: r.note, frequency: RecurringFrequency(rawValue: r.frequency) ?? .monthly, startDate: r.startDate)
            rec.id = r.id
            rec.lastGeneratedDate = r.lastGeneratedDate
            rec.isActive = r.isActive
            context.insert(rec)
        }

        try context.save()

        // Reset seed keys so SeedData doesn't re-add defaults
        UserDefaults.standard.set(true, forKey: SeedData.seededKey)
        UserDefaults.standard.set(true, forKey: SeedData.seededV2Key)
    }
}

// MARK: - Auto-Backup

enum AutoBackupInterval: String, CaseIterable {
    case off = "off"
    case daily = "daily"
    case weekly = "weekly"
    case monthly = "monthly"

    var localizedName: String {
        switch self {
        case .off: return String(localized: "Off")
        case .daily: return String(localized: "Daily")
        case .weekly: return String(localized: "Weekly")
        case .monthly: return String(localized: "Monthly")
        }
    }
}

enum AutoBackupManager {
    static let maxBackups = 5
    private static let directoryName = "AutoBackups"

    static func backupDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent(directoryName)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func shouldPerformBackup(interval: AutoBackupInterval, lastBackupDate: Date?) -> Bool {
        guard interval != .off else { return false }
        guard let last = lastBackupDate else { return true }

        let calendar = Calendar.current
        switch interval {
        case .off: return false
        case .daily:
            return !calendar.isDateInToday(last)
        case .weekly:
            let daysSince = calendar.dateComponents([.day], from: last, to: Date()).day ?? 0
            return daysSince >= 7
        case .monthly:
            let monthsSince = calendar.dateComponents([.month], from: last, to: Date()).month ?? 0
            return monthsSince >= 1
        }
    }

    @discardableResult
    static func performBackupIfNeeded(context: ModelContext, interval: AutoBackupInterval, lastBackupDate: Date?) -> Date? {
        guard shouldPerformBackup(interval: interval, lastBackupDate: lastBackupDate) else { return nil }

        do {
            let data = try BackupService.exportData(context: context)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd_HHmmss"
            let filename = "AutoBackup_\(formatter.string(from: Date())).json"
            let fileURL = backupDirectory().appendingPathComponent(filename)
            try data.write(to: fileURL)
            pruneOldBackups()
            return Date()
        } catch {
            print("Auto-backup failed: \(error)")
            return nil
        }
    }

    static func pruneOldBackups() {
        let dir = backupDirectory()
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles) else { return }

        let sorted = files
            .filter { $0.pathExtension == "json" }
            .sorted { a, b in
                let dateA = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let dateB = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return dateA > dateB // newest first
            }

        if sorted.count > maxBackups {
            for file in sorted.dropFirst(maxBackups) {
                try? fm.removeItem(at: file)
            }
        }
    }
}

// MARK: - BackupDocument for file export/import

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
