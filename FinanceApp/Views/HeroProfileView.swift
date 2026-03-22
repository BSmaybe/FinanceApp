import SwiftUI
import SwiftData

struct HeroProfileView: View {
    let stats: HeroStats

    @AppStorage("heroName") private var heroName = "Trader"
    @AppStorage("heroEmoji") private var heroEmoji = "🦸"
    @AppStorage("unlockedAchievements") private var unlockedAchievements = ""

    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]

    @Environment(\.dismiss) private var dismiss

    @State private var editingName = false
    @State private var nameInput = ""

    private let emojiOptions = ["🦸", "🧙", "🦊", "🐉", "🤖", "🎩", "🦁", "🦄", "🐺", "🔱"]

    private var unlockedSet: Set<String> {
        Set(unlockedAchievements.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    profileHeader
                    levelSection
                    streakSection
                    achievementsSection
                }
                .padding(16)
            }
            .background(AppTheme.canvas)
            .navigationTitle(String(localized: "Hero Profile"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(String(localized: "Done")) { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Profile Header

    private var profileHeader: some View {
        VStack(spacing: 12) {
            Text(heroEmoji)
                .font(.system(size: 64))
                .frame(width: 90, height: 90)
                .background(AppTheme.primaryAccent.opacity(0.15))
                .clipShape(Circle())

            emojiPicker

            if editingName {
                nameEditField
            } else {
                nameDisplay
            }

            Text(stats.title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .cockpitSurface()
    }

    private var emojiPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(emojiOptions, id: \.self) { emoji in
                    Button {
                        heroEmoji = emoji
                    } label: {
                        Text(emoji)
                            .font(.title2)
                            .frame(width: 40, height: 40)
                            .background(heroEmoji == emoji
                                ? AppTheme.primaryAccent.opacity(0.2)
                                : AppTheme.surfaceMuted)
                            .clipShape(Circle())
                            .overlay(
                                Circle().stroke(
                                    heroEmoji == emoji ? AppTheme.primaryAccent : Color.clear,
                                    lineWidth: 2
                                )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private var nameDisplay: some View {
        HStack(spacing: 6) {
            Text(heroName)
                .font(.title3.weight(.bold))
            Button {
                nameInput = heroName
                editingName = true
            } label: {
                Image(systemName: "pencil.circle.fill")
                    .foregroundStyle(AppTheme.primaryAccent)
            }
            .buttonStyle(.plain)
        }
    }

    private var nameEditField: some View {
        HStack {
            TextField(String(localized: "Your name"), text: $nameInput)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)
            Button(String(localized: "Save")) {
                let trimmed = nameInput.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { heroName = trimmed }
                editingName = false
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.primaryAccent)
        }
    }

    // MARK: - Level Section

    private var levelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(String(localized: "Level Progress"), systemImage: "star.fill")
                .font(.headline.weight(.semibold))

            HStack {
                Text(String(format: String(localized: "Level %d"), stats.level))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.primaryAccent)
                Spacer()
                Text(String(format: String(localized: "%d / %d XP"), stats.xp, stats.xpToNextLevel))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            xpProgressBar
        }
        .padding(16)
        .cockpitSurface()
    }

    private var xpProgressBar: some View {
        let progress = stats.xpToNextLevel > 0
            ? Double(stats.xp) / Double(stats.xpToNextLevel)
            : 1.0
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(AppTheme.outline.opacity(0.3))
                    .frame(height: 10)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.primaryAccent, AppTheme.secondaryAccent],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * min(1, max(0, progress)), height: 10)
            }
        }
        .frame(height: 10)
    }

    // MARK: - Streak Section

    private var streakSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                String(format: String(localized: "%d Day Streak 🔥"), stats.streak),
                systemImage: "flame.fill"
            )
            .font(.headline.weight(.semibold))
            .foregroundStyle(AppTheme.warning)

            streakDots
        }
        .padding(16)
        .cockpitSurface()
    }

    private var streakDots: some View {
        let cal = Calendar.current
        let today = Date()
        let txnDays: Set<Int> = Set(transactions.map {
            cal.ordinality(of: .day, in: .era, for: $0.date) ?? 0
        })

        return HStack(spacing: 8) {
            ForEach(0..<7, id: \.self) { offset in
                let date = cal.date(byAdding: .day, value: -(6 - offset), to: today) ?? today
                let ord = cal.ordinality(of: .day, in: .era, for: date) ?? 0
                let hasTx = txnDays.contains(ord)
                let isToday = offset == 6

                VStack(spacing: 4) {
                    Circle()
                        .fill(hasTx ? AppTheme.warning : AppTheme.outline.opacity(0.3))
                        .frame(width: 28, height: 28)
                        .overlay(
                            Text(hasTx ? "🔥" : "")
                                .font(.caption2)
                        )
                        .overlay(
                            Circle()
                                .stroke(isToday ? AppTheme.primaryAccent : Color.clear, lineWidth: 2)
                        )
                    Text(dayLabel(date))
                        .font(.system(size: 9).weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func dayLabel(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE"
        return fmt.string(from: date)
    }

    // MARK: - Achievements Section

    private struct BadgeInfo: Identifiable {
        let id: String
        let icon: String
        let name: String
    }

    private let badgePlaceholders: [BadgeInfo] = [
        BadgeInfo(id: "first_transaction", icon: "🥇", name: "First Transaction"),
        BadgeInfo(id: "first_goal", icon: "🎯", name: "First Goal"),
        BadgeInfo(id: "debt_slayer", icon: "💪", name: "Debt Slayer"),
        BadgeInfo(id: "seven_day_streak", icon: "📅", name: "7-Day Streak"),
        BadgeInfo(id: "budget_hero", icon: "💰", name: "Budget Hero"),
        BadgeInfo(id: "wealth_master", icon: "🏆", name: "Wealth Master"),
    ]

    private var achievementsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(String(localized: "Achievements"), systemImage: "trophy.fill")
                .font(.headline.weight(.semibold))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], spacing: 12) {
                ForEach(badgePlaceholders) { badge in
                    let unlocked = unlockedSet.contains(badge.id)
                    badgeView(badge: badge, unlocked: unlocked)
                }
            }
        }
        .padding(16)
        .cockpitSurface()
    }

    private func badgeView(badge: BadgeInfo, unlocked: Bool) -> some View {
        VStack(spacing: 6) {
            Text(badge.icon)
                .font(.title)
                .opacity(unlocked ? 1.0 : 0.3)
                .frame(width: 52, height: 52)
                .background(
                    Circle().fill(
                        unlocked
                            ? AppTheme.primaryAccent.opacity(0.15)
                            : AppTheme.surfaceMuted
                    )
                )
            Text(badge.name)
                .font(.system(size: 10).weight(.medium))
                .foregroundStyle(unlocked ? .primary : .secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
    }
}
