import SwiftUI
import SwiftData

struct GoalsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Goal.createdDate) private var goals: [Goal]
    @State private var showAdd = false
    @State private var editingGoal: Goal?
    @State private var showSuccess = false
    @State private var successGoalName = ""

    private var activeGoals: [Goal] {
        goals
            .filter { $0.progress < 1.0 }
            .sorted { $0.progress > $1.progress }
    }

    private var completedGoals: [Goal] {
        goals
            .filter { $0.progress >= 1.0 }
            .sorted { $0.createdDate > $1.createdDate }
    }

    private var completedCount: Int { completedGoals.count }

    private var totalTarget: Decimal {
        goals.reduce(.zero) { $0 + $1.targetAmount }
    }

    private var totalSaved: Decimal {
        goals.reduce(.zero) { $0 + $1.currentAmount }
    }

    private var totalRemaining: Decimal {
        let remaining = totalTarget - totalSaved
        return remaining > .zero ? remaining : .zero
    }

    private var averageProgress: Int {
        guard !goals.isEmpty, totalTarget > .zero else { return 0 }
        let ratio = NSDecimalNumber(decimal: totalSaved / totalTarget).doubleValue
        return Int((min(max(ratio, 0), 1) * 100).rounded())
    }

    private var statusBadge: String {
        if goals.isEmpty {
            return String(localized: "No goals yet")
        }
        if completedGoals.isEmpty {
            return String(format: String(localized: "%lld active"), activeGoals.count)
        }
        return String(format: String(localized: "%lld completed"), completedGoals.count)
    }

    private let summaryColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.canvas
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        heroSection

                        if goals.isEmpty {
                            emptyStateSection
                        } else {
                            overviewSection
                            activeGoalsSection

                            if !completedGoals.isEmpty {
                                completedGoalsSection
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle(String(localized: "Goals"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                GoalFormView(goal: nil)
            }
            .sheet(item: $editingGoal) { goal in
                GoalFormView(goal: goal)
            }
            .onChange(of: completedCount) { old, new in
                guard new > old else { return }
                if let justCompleted = completedGoals.first {
                    successGoalName = justCompleted.name
                }
                HapticManager.success()
                showSuccess = true
                triggerLiveActivityCelebration()
            }
            .overlay {
                if showSuccess {
                    SuccessOverlayView(
                        message: String(localized: "Goal completed"),
                        subtitle: successGoalName
                    ) { showSuccess = false }
                }
            }
        }
    }

    private var heroSection: some View {
        HeroMetricCard(
            title: String(localized: "Saved toward goals"),
            value: CurrencyFormatter.string(from: totalSaved),
            supportingTitle: String(localized: "Remaining"),
            supportingValue: CurrencyFormatter.string(from: totalRemaining),
            note: String(localized: "Long-term progress across your savings targets."),
            badgeText: statusBadge
        )
    }

    private var overviewSection: some View {
        LazyVGrid(columns: summaryColumns, spacing: 12) {
            CompactSummaryCard(
                title: String(localized: "Active"),
                value: "\(activeGoals.count)",
                detail: String(localized: "Goals in progress"),
                systemImage: "flag.2.crossed.fill",
                tint: AppTheme.primaryAccent
            )

            CompactSummaryCard(
                title: String(localized: "Completed"),
                value: "\(completedGoals.count)",
                detail: String(localized: "Targets already closed"),
                systemImage: "checkmark.seal.fill",
                tint: AppTheme.success
            )

            CompactSummaryCard(
                title: String(localized: "Average progress"),
                value: "\(averageProgress)%",
                detail: String(localized: "Across all current goals"),
                systemImage: "chart.line.uptrend.xyaxis",
                tint: AppTheme.info
            )

            CompactSummaryCard(
                title: String(localized: "Target"),
                value: CurrencyFormatter.string(from: totalTarget),
                detail: String(localized: "Combined goal value"),
                systemImage: "target",
                tint: AppTheme.warning
            )
        }
    }

    private var emptyStateSection: some View {
        SectionShell(
            title: String(localized: "Start a goal"),
            subtitle: String(localized: "Turn big purchases and savings plans into a trackable target.")
        ) {
            VStack(spacing: 12) {
                InsightCard(
                    title: String(localized: "No active goals"),
                    value: String(localized: "Add your first target"),
                    message: String(localized: "Track progress with one clear number instead of guessing how much is still missing."),
                    systemImage: "flag.fill",
                    tint: AppTheme.info
                )

                ActionTile(
                    title: String(localized: "Add Goal"),
                    subtitle: String(localized: "Create a target and start tracking progress."),
                    systemImage: "plus.circle.fill",
                    tint: AppTheme.primaryAccent
                ) {
                    showAdd = true
                }
            }
        }
    }

    private var activeGoalsSection: some View {
        SectionShell(
            title: String(localized: "In progress"),
            subtitle: String(localized: "Open targets with the most immediate progress to track.")
        ) {
            VStack(spacing: 12) {
                ForEach(activeGoals) { goal in
                    Button {
                        editingGoal = goal
                    } label: {
                        GoalCard(goal: goal, completed: false)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(String(localized: "Edit")) {
                            editingGoal = goal
                        }
                        Button(String(localized: "Delete"), role: .destructive) {
                            HapticManager.impact(.medium)
                            context.delete(goal)
                        }
                    }
                }
            }
        }
    }

    private var completedGoalsSection: some View {
        SectionShell(
            title: String(localized: "Completed"),
            subtitle: String(localized: "Finished targets stay here as a quiet record of progress.")
        ) {
            VStack(spacing: 12) {
                ForEach(completedGoals) { goal in
                    GoalCard(goal: goal, completed: true)
                        .contextMenu {
                            Button(String(localized: "Edit")) {
                                editingGoal = goal
                            }
                            Button(String(localized: "Delete"), role: .destructive) {
                                HapticManager.impact(.medium)
                                context.delete(goal)
                            }
                        }
                }
            }
        }
    }

    private func triggerLiveActivityCelebration() {
#if canImport(ActivityKit)
        if #available(iOS 16.2, *) {
            LiveActivityManager.triggerCelebration(.goalReached)
        }
#endif
    }
}

private struct GoalCard: View {
    let goal: Goal
    let completed: Bool
    @State private var appeared = false

    private var tint: Color {
        completed ? AppTheme.success : AppTheme.primaryAccent
    }

    private var remainingAmount: Decimal {
        let remaining = goal.targetAmount - goal.currentAmount
        return remaining > .zero ? remaining : .zero
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(goal.name)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)

                    if !goal.note.isEmpty {
                        Text(goal.note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 8)

                Text("\(Int((goal.progress * 100).rounded()))%")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(tint.opacity(0.12))
                    .clipShape(Capsule())
            }

            ProgressView(value: appeared ? goal.progress : 0)
                .tint(tint)
                .animation(.spring(response: 0.7, dampingFraction: 0.76), value: appeared)
                .animation(.spring(response: 0.5, dampingFraction: 0.82), value: goal.progress)

            HStack(spacing: 12) {
                goalMetric(
                    title: String(localized: "Saved"),
                    value: CurrencyFormatter.string(from: goal.currentAmount)
                )

                Spacer(minLength: 0)

                goalMetric(
                    title: String(localized: "Target"),
                    value: CurrencyFormatter.string(from: goal.targetAmount)
                )

                Spacer(minLength: 0)

                goalMetric(
                    title: completed ? String(localized: "Status") : String(localized: "Remaining"),
                    value: completed ? String(localized: "Complete") : CurrencyFormatter.string(from: remainingAmount),
                    tint: completed ? AppTheme.success : .primary
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cockpitSurface(cornerRadius: 24, elevated: true)
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.76).delay(0.08)) {
                appeared = true
            }
        }
    }

    private func goalMetric(title: String, value: String, tint: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .contentTransition(.numericText())
        }
    }
}

private struct GoalFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let goal: Goal?

    @State private var name: String = ""
    @State private var targetText: String = ""
    @State private var currentText: String = ""
    @State private var note: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.canvas.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        HeroMetricCard(
                            title: goal == nil ? String(localized: "New Goal") : String(localized: "Edit Goal"),
                            value: name.isEmpty ? String(localized: "Untitled") : name,
                            supportingTitle: String(localized: "Target"),
                            supportingValue: targetDecimal > 0 ? CurrencyFormatter.string(from: targetDecimal) : String(localized: "Set target"),
                            note: String(localized: "Goals work best when the target and current amount are realistic."),
                            badgeText: String(localized: "Goal")
                        )

                        SectionShell(
                            title: String(localized: "Goal"),
                            subtitle: String(localized: "Set a clear target and current balance before tracking progress.")
                        ) {
                            VStack(spacing: 14) {
                                goalField(title: String(localized: "Name"), text: $name, prompt: String(localized: "Name"))
                                goalField(title: String(localized: "Target Amount"), text: $targetText, prompt: "0.00", numeric: true)
                                goalField(title: String(localized: "Current Amount"), text: $currentText, prompt: "0.00", numeric: true)
                            }
                        }

                        SectionShell(
                            title: String(localized: "Note"),
                            subtitle: String(localized: "Keep a short reminder for purpose or timing.")
                        ) {
                            goalField(title: String(localized: "Note"), text: $note, prompt: String(localized: "Optional note"))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .financeNavigationSurface()
            .keyboardDismissable()
            .navigationTitle(goal == nil ? String(localized: "New Goal") : String(localized: "Edit Goal"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || targetDecimal <= 0)
                }
            }
        }
        .onAppear {
            if let goal {
                name = goal.name
                targetText = (goal.targetAmount as NSDecimalNumber).stringValue
                currentText = (goal.currentAmount as NSDecimalNumber).stringValue
                note = goal.note
            }
        }
    }

    private var targetDecimal: Decimal { Decimal(string: targetText) ?? .zero }
    private var currentDecimal: Decimal { Decimal(string: currentText) ?? .zero }

    private func goalField(title: String, text: Binding<String>, prompt: String, numeric: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if numeric {
                TextField(prompt, text: text)
                    .financeNumericKeyboard()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .background(AppTheme.elevatedSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                TextField(prompt, text: text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .background(AppTheme.elevatedSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        if let goal {
            goal.name = trimmedName
            goal.targetAmount = targetDecimal
            goal.currentAmount = currentDecimal
            goal.note = note
        } else {
            let g = Goal(name: trimmedName, targetAmount: targetDecimal, currentAmount: currentDecimal, note: note)
            context.insert(g)
        }
        HapticManager.success()
        dismiss()
    }
}
