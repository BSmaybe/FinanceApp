import SwiftUI
import SwiftData

struct HeroProfileCardView: View {
    let stats: HeroStats

    @AppStorage("heroName") private var heroName = "Trader"
    @AppStorage("heroEmoji") private var heroEmoji = "🦸"
    @State private var showingProfile = false

    var body: some View {
        Button {
            showingProfile = true
        } label: {
            cardContent
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingProfile) {
            HeroProfileView(stats: stats)
        }
    }

    private var cardContent: some View {
        HStack(spacing: 12) {
            avatarCircle
            infoColumn
            Spacer()
            streakBadge
            levelBadge
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.outline.opacity(0.4), lineWidth: 1)
        )
    }

    private var avatarCircle: some View {
        Text(heroEmoji)
            .font(.system(size: 22))
            .frame(width: 44, height: 44)
            .background(AppTheme.primaryAccent.opacity(0.15))
            .clipShape(Circle())
    }

    private var infoColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(heroName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text(stats.title)
                .font(.caption)
                .foregroundStyle(.secondary)
            xpBar
        }
    }

    private var xpBar: some View {
        let progress = stats.xpToNextLevel > 0
            ? Double(stats.xp) / Double(stats.xpToNextLevel)
            : 1.0
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(AppTheme.outline.opacity(0.3))
                    .frame(height: 4)
                Capsule()
                    .fill(AppTheme.primaryAccent)
                    .frame(width: geo.size.width * min(1, max(0, progress)), height: 4)
            }
        }
        .frame(width: 80, height: 4)
    }

    private var levelBadge: some View {
        Text(String(format: String(localized: "Lv.%d"), stats.level))
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AppTheme.primaryAccent)
            .clipShape(Capsule())
    }

    private var streakBadge: some View {
        HStack(spacing: 2) {
            Text("🔥")
                .font(.caption)
            Text("\(stats.streak)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(AppTheme.warning.opacity(0.15))
        .clipShape(Capsule())
    }
}
