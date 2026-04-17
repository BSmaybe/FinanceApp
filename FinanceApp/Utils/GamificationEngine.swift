import Foundation

struct HeroStats {
    let level: Int
    let xp: Int
    let xpToNextLevel: Int
    let streak: Int
    let title: String
}

enum GamificationEngine {

    static func title(for level: Int) -> String {
        switch level {
        case 1...5:   return String(localized: "Foundation building")
        case 6...10:  return String(localized: "Steady control")
        case 11...20: return String(localized: "Healthy momentum")
        case 21...35: return String(localized: "Long-range planning")
        default:      return String(localized: "Financial resilience")
        }
    }

    /// XP required to reach the given level (cumulative total from level 1).
    private static func cumulativeXP(upToLevel level: Int) -> Int {
        // Each level L requires L*100 XP to unlock.
        // Cumulative XP to reach level N = sum of 100 + 200 + ... + N*100 = 100 * N*(N+1)/2
        let n = max(0, level - 1)
        return 100 * n * (n + 1) / 2
    }

    static func streak(from dates: [Date]) -> Int {
        let cal = Calendar.current
        // Collect unique calendar days that have a transaction
        var daySet = Set<Int>()
        for d in dates {
            let ord = cal.ordinality(of: .day, in: .era, for: d) ?? 0
            daySet.insert(ord)
        }
        guard !daySet.isEmpty else { return 0 }

        let todayOrd = cal.ordinality(of: .day, in: .era, for: Date()) ?? 0
        var consecutive = 0
        var current = todayOrd
        while daySet.contains(current) {
            consecutive += 1
            current -= 1
        }
        // If today has no transaction, check if yesterday started the streak
        if consecutive == 0 {
            current = todayOrd - 1
            while daySet.contains(current) {
                consecutive += 1
                current -= 1
            }
        }
        return consecutive
    }

    static func compute(
        transactions: [Transaction],
        goals: [Goal],
        debts: [Debt]
    ) -> HeroStats {
        let currentStreak = streak(from: transactions.map { $0.date })

        let transactionXP = transactions.count * 10
        let completedGoalsXP = goals.filter { $0.progress >= 1.0 }.count * 100
        let paidDebtsXP = debts.filter { $0.remainingAmount <= 0 }.count * 200
        let streakBonusXP = currentStreak * 5

        let totalXP = transactionXP + completedGoalsXP + paidDebtsXP + streakBonusXP

        // Find level: highest level whose cumulative XP threshold we've exceeded
        var level = 1
        for l in 1...50 {
            if totalXP >= cumulativeXP(upToLevel: l + 1) {
                level = l + 1
            } else {
                break
            }
        }
        level = min(50, level)

        let xpForCurrentLevel = cumulativeXP(upToLevel: level)
        let xpForNextLevel = cumulativeXP(upToLevel: level + 1)
        let xpInCurrentLevel = totalXP - xpForCurrentLevel
        let xpNeededForNext = xpForNextLevel - xpForCurrentLevel

        return HeroStats(
            level: level,
            xp: xpInCurrentLevel,
            xpToNextLevel: xpNeededForNext,
            streak: currentStreak,
            title: title(for: level)
        )
    }
}

enum CoachAdvicePriority: Int, Codable, Comparable, CaseIterable {
    case low = 0
    case medium = 1
    case high = 2
    case critical = 3

    static func < (lhs: CoachAdvicePriority, rhs: CoachAdvicePriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum CoachAdviceKind: String, Codable, Hashable {
    case budgetPressure
    case essentialProtection
    case subscriptionReview
    case debtFocus
    case goalMomentum
    case consistency
    case steadyState
}

enum CoachAdviceCTA: String, Codable, Hashable {
    case budgets
    case subscriptions
    case debts
    case goals
    case transactions
    case analytics
    case none

    var title: String {
        switch self {
        case .budgets:
            return String(localized: "Review budgets")
        case .subscriptions:
            return String(localized: "Review subscriptions")
        case .debts:
            return String(localized: "Review debts")
        case .goals:
            return String(localized: "Review goals")
        case .transactions:
            return String(localized: "Open transactions")
        case .analytics:
            return String(localized: "Open analytics")
        case .none:
            return String(localized: "Stay on plan")
        }
    }
}

struct CoachAdvice: Identifiable, Hashable {
    let id: String
    let kind: CoachAdviceKind
    let priority: CoachAdvicePriority
    let title: String
    let message: String
    let reason: String
    let alternative: String
    let cta: CoachAdviceCTA
}

struct CoachProgressSummary: Hashable {
    let focusTitle: String
    let consistencyDays: Int
    let activePlans: Int
    let completedMilestones: Int
    let budgetStability: Int
}

struct FinancialVitals: Hashable {
    let readiness: Int
    let pressure: Int
    let reserve: Int
    let runwayDays: Int
    let leftToPayNext7Days: Decimal
    let budgetStability: Int
    let acuteLoadIndex: Double
    let dueSoonCount: Int
}

enum FinancialVitalsZone {
    case green
    case yellow
    case red

    static func from(score: Int, reversed: Bool = false) -> FinancialVitalsZone {
        let normalized = max(0, min(100, score))
        if reversed {
            switch normalized {
            case ..<31: return .green
            case ..<61: return .yellow
            default: return .red
            }
        }
        switch normalized {
        case 70...: return .green
        case 45...: return .yellow
        default: return .red
        }
    }
}

enum FinancialVitalMetric: String, CaseIterable, Hashable {
    case readiness
    case pressure
    case reserve

    var title: String {
        switch self {
        case .readiness:
            return String(localized: "Readiness")
        case .pressure:
            return String(localized: "Pressure")
        case .reserve:
            return String(localized: "Reserve")
        }
    }

    var reversed: Bool {
        self == .pressure
    }

    func zone(for score: Int) -> FinancialVitalsZone {
        .from(score: score, reversed: reversed)
    }

    var directionLabel: String {
        reversed ? String(localized: "Lower is better") : String(localized: "Higher is better")
    }

    func stateLabel(for score: Int) -> String {
        let zone = zone(for: score)
        switch self {
        case .pressure:
            switch zone {
            case .green:
                return String(localized: "Light")
            case .yellow:
                return String(localized: "Watch")
            case .red:
                return String(localized: "High")
            }
        case .readiness, .reserve:
            switch zone {
            case .green:
                return String(localized: "Good")
            case .yellow:
                return String(localized: "Watch")
            case .red:
                return String(localized: "Low")
            }
        }
    }
}

enum CoachAdviceEngine {
    static func progressSummary(
        transactions: [Transaction],
        categories: [Category],
        budgets: [Budget],
        goals: [Goal],
        debts: [Debt],
        month: Int,
        year: Int
    ) -> CoachProgressSummary {
        let stats = GamificationEngine.compute(transactions: transactions, goals: goals, debts: debts)
        let completedMilestones = goals.filter { $0.progress >= 1.0 }.count + debts.filter { $0.remainingAmount <= 0 }.count
        let activePlans = goals.filter { $0.progress < 1.0 }.count
            + debts.filter { $0.remainingAmount > 0 }.count
            + budgets.filter { $0.month == month && $0.year == year }.count

        let stability = budgetStability(
            transactions: transactions,
            budgets: budgets,
            month: month,
            year: year
        )

        return CoachProgressSummary(
            focusTitle: stats.title,
            consistencyDays: stats.streak,
            activePlans: activePlans,
            completedMilestones: completedMilestones,
            budgetStability: stability
        )
    }

    static func recommendations(
        transactions: [Transaction],
        categories: [Category],
        budgets: [Budget],
        goals: [Goal],
        debts: [Debt],
        subscriptions: [Subscription],
        month: Int,
        year: Int,
        now: Date = Date()
    ) -> [CoachAdvice] {
        var advice: [CoachAdvice] = []
        let categoryById = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        let expenseTransactions = transactions.filter {
            let comps = Calendar.current.dateComponents([.year, .month], from: $0.date)
            return comps.year == year && comps.month == month && $0.type == .expense
        }

        let spentByCategory = expenseTransactions.reduce(into: [UUID: Decimal]()) { partial, txn in
            guard let categoryId = txn.categoryId else { return }
            partial[categoryId, default: .zero] += txn.amount
        }

        let activeBudgets = budgets.filter { $0.month == month && $0.year == year }
        let sortedRisks = activeBudgets.compactMap { budget -> (Category, Decimal, Decimal, Int)? in
            guard let category = categoryById[budget.categoryId], budget.limitAmount > 0 else { return nil }
            let spent = spentByCategory[budget.categoryId, default: .zero]
            let percent = Int((NSDecimalNumber(decimal: (spent / budget.limitAmount) * 100).doubleValue).rounded())
            return (category, spent, budget.limitAmount, percent)
        }
        .sorted { lhs, rhs in lhs.3 > rhs.3 }

        if let topRisk = sortedRisks.first, topRisk.3 >= 75 {
            let daysLeft = daysLeftInMonth(from: now)
            let role = topRisk.0.adviceRole
            switch role {
            case .essential:
                let alternative: String
                if isFoodCategory(topRisk.0.name) {
                    alternative = String(localized: "Use home meals or fewer deliveries before cutting food outright.")
                } else {
                    alternative = String(localized: "Keep this essential covered and offset it with a flexible category this week.")
                }
                advice.append(
                    CoachAdvice(
                        id: "essential-\(topRisk.0.id.uuidString)",
                        kind: .essentialProtection,
                        priority: topRisk.3 >= 100 ? .critical : .high,
                        title: String(localized: "Protect essentials"),
                        message: String(
                            format: String(localized: "%@ is already at %lld%% of plan."),
                            topRisk.0.name,
                            Int64(topRisk.3)
                        ),
                        reason: String(
                            format: String(localized: "There are %lld days left in this month."),
                            Int64(max(0, daysLeft))
                        ),
                        alternative: alternative,
                        cta: .budgets
                    )
                )
            case .fixed:
                advice.append(
                    CoachAdvice(
                        id: "fixed-\(topRisk.0.id.uuidString)",
                        kind: .budgetPressure,
                        priority: topRisk.3 >= 100 ? .critical : .high,
                        title: String(localized: "Review a fixed cost"),
                        message: String(
                            format: String(localized: "%@ is already at %lld%% of plan."),
                            topRisk.0.name,
                            Int64(topRisk.3)
                        ),
                        reason: String(localized: "Fixed costs are safer to review early than to scramble for later."),
                        alternative: String(localized: "Renegotiate timing, amount, or provider before it lands."),
                        cta: .budgets
                    )
                )
            case .flexible:
                advice.append(
                    CoachAdvice(
                        id: "flex-\(topRisk.0.id.uuidString)",
                        kind: .budgetPressure,
                        priority: topRisk.3 >= 100 ? .critical : .high,
                        title: String(localized: "Trim flexible spending"),
                        message: String(
                            format: String(localized: "%@ is already at %lld%% of plan."),
                            topRisk.0.name,
                            Int64(topRisk.3)
                        ),
                        reason: String(localized: "Flexible categories can absorb the cut with less stress."),
                        alternative: String(localized: "Pause or shrink this category before touching essentials."),
                        cta: .budgets
                    )
                )
            case .income:
                break
            }
        }

        let upcomingSubscriptions = subscriptions
            .filter { $0.isActive && $0.nextBillingDate >= now }
            .sorted {
                if $0.nextBillingDate == $1.nextBillingDate {
                    return $0.amount > $1.amount
                }
                return $0.nextBillingDate < $1.nextBillingDate
            }

        if let subscription = upcomingSubscriptions.first {
            let days = daysUntil(subscription.nextBillingDate, from: now)
            if days <= 7 {
                advice.append(
                    CoachAdvice(
                        id: "subscription-\(subscription.id.uuidString)",
                        kind: .subscriptionReview,
                        priority: .high,
                        title: String(localized: "Review a renewal"),
                        message: String(
                            format: String(localized: "%@ renews in %lld days for %@."),
                            subscription.name,
                            Int64(max(0, days)),
                            currencyString(subscription.amount)
                        ),
                        reason: String(localized: "Subscriptions are easier to stop before the charge lands."),
                        alternative: String(localized: "If it still matters, move the cut to entertainment or shopping instead."),
                        cta: .subscriptions
                    )
                )
            }
        }

        let debtWindows = debts
            .filter { $0.remainingAmount > 0 }
            .map { ($0, daysUntilNextDue(day: $0.dueDay, from: now)) }
            .sorted { lhs, rhs in lhs.1 < rhs.1 }

        if let debtWindow = debtWindows.first, debtWindow.1 <= 7 {
            advice.append(
                CoachAdvice(
                    id: "debt-\(debtWindow.0.id.uuidString)",
                    kind: .debtFocus,
                    priority: .high,
                    title: String(localized: "Stay ahead of debt"),
                    message: String(
                        format: String(localized: "%@ is due in %lld days. Keep at least %@ ready."),
                        debtWindow.0.name,
                        Int64(max(0, debtWindow.1)),
                        currencyString(debtWindow.0.minimumPayment)
                    ),
                    reason: String(localized: "Debt pressure compounds when the minimum slips."),
                    alternative: String(localized: "Protect the minimum first, then cut a flexible category if you need room."),
                    cta: .debts
                )
            )
        }

        if let goal = goals
            .filter({ $0.progress > 0 && $0.progress < 1.0 })
            .sorted(by: { $0.progress > $1.progress })
            .first {
            advice.append(
                CoachAdvice(
                    id: "goal-\(goal.id.uuidString)",
                    kind: .goalMomentum,
                    priority: .medium,
                    title: String(localized: "Keep the goal moving"),
                    message: String(
                        format: String(localized: "%@ is %lld%% funded. One more transfer keeps the trend alive."),
                        goal.name,
                        Int64((goal.progress * 100).rounded())
                    ),
                    reason: String(localized: "Small scheduled transfers are safer than waiting for a perfect month."),
                    alternative: String(localized: "Even a small top-up keeps motivation high without stressing the budget."),
                    cta: .goals
                )
            )
        }

        let streak = GamificationEngine.streak(from: transactions.map { $0.date })
        if streak >= 3 {
            advice.append(
                CoachAdvice(
                    id: "consistency-\(streak)",
                    kind: .consistency,
                    priority: .medium,
                    title: String(localized: "Hold course"),
                    message: String(
                        format: String(localized: "You have %lld active days in a row. The best move today is consistency, not a big reset."),
                        Int64(streak)
                    ),
                    reason: String(localized: "You are already moving in the right direction."),
                    alternative: String(localized: "Capture the next transaction cleanly and leave the big adjustments for planning time."),
                    cta: .transactions
                )
            )
        }

        if advice.isEmpty {
            advice.append(
                CoachAdvice(
                    id: "steady-state",
                    kind: .steadyState,
                    priority: .low,
                    title: String(localized: "Hold course"),
                    message: String(localized: "No sharp intervention today. Stay on plan and keep capture clean."),
                    reason: String(localized: "Your current signals do not call for a heavy adjustment."),
                    alternative: String(localized: "Use planning time for one thoughtful change instead of many reactive ones."),
                    cta: .transactions
                )
            )
        }

        let deduped = Dictionary(grouping: advice, by: \.id).compactMap { $0.value.first }
        return deduped.sorted { lhs, rhs in
            if lhs.priority == rhs.priority {
                return lhs.title < rhs.title
            }
            return lhs.priority > rhs.priority
        }
    }

    private static func budgetStability(
        transactions: [Transaction],
        budgets: [Budget],
        month: Int,
        year: Int
    ) -> Int {
        let activeBudgets = budgets.filter { $0.month == month && $0.year == year && $0.limitAmount > 0 }
        guard !activeBudgets.isEmpty else { return 0 }

        let spentByCategory = transactions.reduce(into: [UUID: Decimal]()) { partial, txn in
            guard txn.type == .expense else { return }
            let comps = Calendar.current.dateComponents([.year, .month], from: txn.date)
            guard comps.year == year, comps.month == month, let categoryId = txn.categoryId else { return }
            partial[categoryId, default: .zero] += txn.amount
        }

        let onTrack = activeBudgets.filter {
            let spent = spentByCategory[$0.categoryId, default: .zero]
            guard $0.limitAmount > 0 else { return false }
            let ratio = NSDecimalNumber(decimal: spent / $0.limitAmount).doubleValue
            return ratio <= 0.8
        }.count

        return Int((Double(onTrack) / Double(activeBudgets.count) * 100).rounded())
    }

    private static func daysLeftInMonth(from now: Date) -> Int {
        let calendar = Calendar.current
        guard let range = calendar.range(of: .day, in: .month, for: now) else {
            return 0
        }
        let day = calendar.component(.day, from: now)
        return max(0, range.count - day)
    }

    private static func daysUntil(_ date: Date, from now: Date) -> Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        let end = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }

    private static func daysUntilNextDue(day: Int, from now: Date) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let currentComponents = calendar.dateComponents([.year, .month], from: today)

        var dueComponents = DateComponents()
        dueComponents.year = currentComponents.year
        dueComponents.month = currentComponents.month
        dueComponents.day = min(day, 28)
        let thisMonthDue = calendar.date(from: dueComponents) ?? today

        if thisMonthDue >= today {
            return daysUntil(thisMonthDue, from: today)
        }

        guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: today) else {
            return 0
        }
        let nextComponents = calendar.dateComponents([.year, .month], from: nextMonth)
        dueComponents.year = nextComponents.year
        dueComponents.month = nextComponents.month
        let followingDue = calendar.date(from: dueComponents) ?? nextMonth
        return daysUntil(followingDue, from: today)
    }

    private static func isFoodCategory(_ name: String) -> Bool {
        let normalized = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased()
        return ["food", "grocery", "grocer", "meal", "restaurant", "delivery", "еда", "продукт", "доставка", "кафе"]
            .contains(where: normalized.contains)
    }

    private static func currencyString(_ decimal: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale.current
        return formatter.string(from: NSDecimalNumber(decimal: decimal))
            ?? "\(formatter.currencySymbol ?? "$")0"
    }
}

enum FinancialVitalsEngine {
    static func compute(
        accounts: [Account],
        transactions: [Transaction],
        categories: [Category],
        budgets: [Budget],
        debts: [Debt],
        subscriptions: [Subscription],
        month: Int,
        year: Int,
        now: Date = Date()
    ) -> FinancialVitals {
        let categoryById = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        let balances = balancesByAccount(accounts: accounts, transactions: transactions, now: now)

        let liquidBalance = balances.reduce(Decimal.zero) { partial, pair in
            guard let account = accounts.first(where: { $0.id == pair.key }) else { return partial }
            switch account.type {
            case .checking, .savings, .cash, .card:
                return partial + pair.value
            case .deposit:
                return partial + (pair.value * Decimal(string: "0.6")!)
            case .crypto:
                return partial + (pair.value * Decimal(string: "0.35")!)
            }
        }

        let expenses30 = expenseTransactions(inLastDays: 30, transactions: transactions, now: now)
        let expenses7 = expenseTransactions(inLastDays: 7, transactions: transactions, now: now)
        let expenses42 = expenseTransactions(inLastDays: 42, transactions: transactions, now: now)

        let essentialDaily = averageDailySpend(
            transactions: expenses30,
            categoryById: categoryById,
            roles: [.essential, .fixed]
        )
        let flexible7 = totalSpend(
            transactions: expenses7,
            categoryById: categoryById,
            roles: [.flexible]
        )
        let flexible42 = totalSpend(
            transactions: expenses42,
            categoryById: categoryById,
            roles: [.flexible]
        )
        let baselineFlexible7 = flexible42 / Decimal(6)
        let acuteLoadIndex = NSDecimalNumber(
            decimal: flexible7 / max(baselineFlexible7, Decimal(string: "1")!)
        ).doubleValue

        let dueNext7 = upcomingCommitments(
            debts: debts,
            subscriptions: subscriptions,
            withinDays: 7,
            now: now
        )
        let leftToPayNext7Days = dueNext7.reduce(Decimal.zero) { $0 + $1.amount }
        let dueSoonCount = dueNext7.count

        let budgetStability = budgetStability(
            budgets: budgets,
            transactions: transactions,
            month: month,
            year: year
        )

        let runwayDays = {
            guard essentialDaily > 0 else { return 30 }
            let days = NSDecimalNumber(decimal: liquidBalance / essentialDaily).doubleValue
            return max(0, Int(days.rounded(.down)))
        }()

        let reserve = reserveScore(
            liquidBalance: liquidBalance,
            essentialDaily: essentialDaily,
            leftToPayNext7Days: leftToPayNext7Days,
            budgetStability: budgetStability
        )
        let pressure = pressureScore(
            budgets: budgets,
            transactions: transactions,
            categoryById: categoryById,
            month: month,
            year: year,
            liquidBalance: liquidBalance,
            leftToPayNext7Days: leftToPayNext7Days,
            acuteLoadIndex: acuteLoadIndex
        )
        let readiness = readinessScore(
            reserve: reserve,
            pressure: pressure,
            budgetStability: budgetStability
        )

        return FinancialVitals(
            readiness: readiness,
            pressure: pressure,
            reserve: reserve,
            runwayDays: runwayDays,
            leftToPayNext7Days: leftToPayNext7Days,
            budgetStability: budgetStability,
            acuteLoadIndex: acuteLoadIndex,
            dueSoonCount: dueSoonCount
        )
    }

    private static func balancesByAccount(
        accounts: [Account],
        transactions: [Transaction],
        now: Date
    ) -> [UUID: Decimal] {
        var balances = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.openingBalance) })
        for transaction in transactions where BalanceCalculator.isPosted(transaction, asOf: now) {
            switch transaction.type {
            case .income:
                balances[transaction.accountId, default: .zero] += transaction.amount
            case .expense:
                balances[transaction.accountId, default: .zero] -= transaction.amount
            case .transfer:
                balances[transaction.accountId, default: .zero] -= transaction.amount
                if let toAccountId = transaction.toAccountId {
                    balances[toAccountId, default: .zero] += transaction.amount
                }
            }
        }
        return balances
    }

    private static func expenseTransactions(
        inLastDays days: Int,
        transactions: [Transaction],
        now: Date
    ) -> [Transaction] {
        guard let start = Calendar.current.date(byAdding: .day, value: -days + 1, to: now) else {
            return []
        }
        return transactions.filter { transaction in
            transaction.type == .expense && transaction.date >= start && transaction.date <= now
        }
    }

    private static func averageDailySpend(
        transactions: [Transaction],
        categoryById: [UUID: Category],
        roles: Set<CategoryAdviceRole>
    ) -> Decimal {
        let total = totalSpend(transactions: transactions, categoryById: categoryById, roles: roles)
        return total / Decimal(30)
    }

    private static func totalSpend(
        transactions: [Transaction],
        categoryById: [UUID: Category],
        roles: Set<CategoryAdviceRole>
    ) -> Decimal {
        transactions.reduce(Decimal.zero) { partial, transaction in
            guard
                let categoryId = transaction.categoryId,
                let category = categoryById[categoryId],
                roles.contains(category.adviceRole)
            else {
                return partial
            }
            return partial + transaction.amount
        }
    }

    private static func upcomingCommitments(
        debts: [Debt],
        subscriptions: [Subscription],
        withinDays: Int,
        now: Date
    ) -> [(title: String, amount: Decimal)] {
        let debtCommitments = debts.compactMap { debt -> (String, Decimal)? in
            guard debt.remainingAmount > 0 else { return nil }
            let daysUntilDue = daysUntilNextDue(day: debt.dueDay, from: now)
            guard daysUntilDue <= withinDays else { return nil }
            return (debt.name, debt.minimumPayment)
        }

        let subscriptionCommitments = subscriptions.compactMap { subscription -> (String, Decimal)? in
            guard subscription.isActive else { return nil }
            let days = daysUntil(subscription.nextBillingDate, from: now)
            guard days >= 0, days <= withinDays else { return nil }
            return (subscription.name, subscription.amount)
        }

        return (debtCommitments + subscriptionCommitments)
            .sorted { $0.amount > $1.amount }
    }

    private static func budgetStability(
        budgets: [Budget],
        transactions: [Transaction],
        month: Int,
        year: Int
    ) -> Int {
        let monthBudgets = budgets.filter { $0.month == month && $0.year == year && $0.limitAmount > 0 }
        guard !monthBudgets.isEmpty else { return 50 }

        let spentByCategory = transactions.reduce(into: [UUID: Decimal]()) { partial, transaction in
            guard transaction.type == .expense else { return }
            let comps = Calendar.current.dateComponents([.year, .month], from: transaction.date)
            guard comps.year == year, comps.month == month, let categoryId = transaction.categoryId else { return }
            partial[categoryId, default: .zero] += transaction.amount
        }

        let onTrackCount = monthBudgets.filter { budget in
            let spent = spentByCategory[budget.categoryId, default: .zero]
            let ratio = NSDecimalNumber(decimal: spent / budget.limitAmount).doubleValue
            return ratio <= 0.8
        }.count

        return Int((Double(onTrackCount) / Double(monthBudgets.count) * 100).rounded())
    }

    private static func reserveScore(
        liquidBalance: Decimal,
        essentialDaily: Decimal,
        leftToPayNext7Days: Decimal,
        budgetStability: Int
    ) -> Int {
        let runwayRatio = max(0, min(1, NSDecimalNumber(decimal: liquidBalance / max(essentialDaily * 21, Decimal(string: "1")!)).doubleValue))
        let needs7Days = max(essentialDaily * 7 + leftToPayNext7Days, Decimal(string: "1")!)
        let bufferRatio = max(0, min(1, NSDecimalNumber(decimal: liquidBalance / needs7Days).doubleValue))
        let stabilityRatio = Double(budgetStability) / 100.0
        let score = Int((45 * runwayRatio + 35 * bufferRatio + 20 * stabilityRatio).rounded())
        return max(0, min(100, score))
    }

    private static func pressureScore(
        budgets: [Budget],
        transactions: [Transaction],
        categoryById: [UUID: Category],
        month: Int,
        year: Int,
        liquidBalance: Decimal,
        leftToPayNext7Days: Decimal,
        acuteLoadIndex: Double
    ) -> Int {
        let monthBudgets = budgets.filter { $0.month == month && $0.year == year && $0.limitAmount > 0 }
        let spentByCategory = transactions.reduce(into: [UUID: Decimal]()) { partial, transaction in
            guard transaction.type == .expense else { return }
            let comps = Calendar.current.dateComponents([.year, .month], from: transaction.date)
            guard comps.year == year, comps.month == month, let categoryId = transaction.categoryId else { return }
            partial[categoryId, default: .zero] += transaction.amount
        }

        let overspendRatio: Double = {
            let flexibleBudgets = monthBudgets.filter { budget in
                guard let category = categoryById[budget.categoryId] else { return false }
                return category.adviceRole == .flexible
            }
            guard !flexibleBudgets.isEmpty else { return 0 }
            let elevated = flexibleBudgets.filter { budget in
                let spent = spentByCategory[budget.categoryId, default: .zero]
                let ratio = NSDecimalNumber(decimal: spent / budget.limitAmount).doubleValue
                return ratio >= 0.9
            }.count
            return Double(elevated) / Double(flexibleBudgets.count)
        }()

        let dueRatio = max(0, min(1, NSDecimalNumber(decimal: leftToPayNext7Days / max(liquidBalance, Decimal(string: "1")!)).doubleValue))
        let volatility = spendingVolatility(transactions: transactions)
        let acuteRatio = max(0, min(1, (acuteLoadIndex - 1) / 0.8))

        let score = Int((35 * overspendRatio + 25 * acuteRatio + 25 * dueRatio + 15 * volatility).rounded())
        return max(0, min(100, score))
    }

    private static func readinessScore(
        reserve: Int,
        pressure: Int,
        budgetStability: Int
    ) -> Int {
        let score = Int((0.45 * Double(reserve) + 0.35 * Double(100 - pressure) + 0.20 * Double(budgetStability)).rounded())
        return max(0, min(100, score))
    }

    private static func spendingVolatility(transactions: [Transaction]) -> Double {
        let last30 = expenseTransactions(inLastDays: 30, transactions: transactions, now: Date())
        guard !last30.isEmpty else { return 0 }

        let calendar = Calendar.current
        let grouped = Dictionary(grouping: last30) { transaction in
            calendar.startOfDay(for: transaction.date)
        }
        let dailySums = grouped.values.map { items in
            items.reduce(Decimal.zero) { $0 + $1.amount }
        }.map { NSDecimalNumber(decimal: $0).doubleValue }

        guard !dailySums.isEmpty else { return 0 }
        let mean = dailySums.reduce(0, +) / Double(dailySums.count)
        guard mean > 0 else { return 0 }
        let variance = dailySums.reduce(0) { partial, value in
            partial + pow(value - mean, 2)
        } / Double(dailySums.count)
        return max(0, min(1, sqrt(variance) / mean))
    }

    private static func daysUntil(_ date: Date, from now: Date) -> Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        let end = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }

    private static func daysUntilNextDue(day: Int, from now: Date) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let currentComponents = calendar.dateComponents([.year, .month], from: today)

        var dueComponents = DateComponents()
        dueComponents.year = currentComponents.year
        dueComponents.month = currentComponents.month
        dueComponents.day = min(day, 28)
        let thisMonthDue = calendar.date(from: dueComponents) ?? today

        if thisMonthDue >= today {
            return daysUntil(thisMonthDue, from: today)
        }

        guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: today) else {
            return 0
        }
        let nextComponents = calendar.dateComponents([.year, .month], from: nextMonth)
        dueComponents.year = nextComponents.year
        dueComponents.month = nextComponents.month
        let followingDue = calendar.date(from: dueComponents) ?? nextMonth
        return daysUntil(followingDue, from: today)
    }
}

// MARK: - Vitals Analytics Presentation Types

struct FinancialVitalsPoint {
    let date: Date
    let readiness: Int
    let pressure: Int
    let reserve: Int
}

struct FinancialVitalsTimeline {
    let points: [FinancialVitalsPoint]
    let period: AnalyticsPeriod
}

struct FinancialVitalsDriver: Identifiable {
    enum Impact: Equatable { case helps, hurts }
    let id: String
    let title: String
    let explanation: String
    let impact: Impact
    let cta: CoachAdviceCTA
}

struct FinancialVitalsAnalyticsSummary {
    let vitals: FinancialVitals
    let timeline: FinancialVitalsTimeline
    let drivers: [FinancialVitalsDriver]
    let acuteLoadIndex: Double
    let acuteIsElevated: Bool
}
