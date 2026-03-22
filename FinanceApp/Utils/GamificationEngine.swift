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
        case 1...5:   return String(localized: "Beginner Saver")
        case 6...10:  return String(localized: "Budget Apprentice")
        case 11...20: return String(localized: "Money Mage")
        case 21...35: return String(localized: "Finance Warrior")
        default:      return String(localized: "Wealth Master")
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
