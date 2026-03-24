import SwiftUI
import SwiftData

struct GoalsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Goal.createdDate) private var goals: [Goal]
    @State private var showAdd = false
    @State private var editingGoal: Goal?
    @State private var showSuccess = false
    @State private var successGoalName = ""
    private var completedCount: Int { goals.filter { $0.progress >= 1.0 }.count }

    var body: some View {
        NavigationStack {
            List {
                if goals.isEmpty {
                    EmptyStateView(
                        icon: "flag.fill",
                        title: String(localized: "No Goals"),
                        subtitle: String(localized: "Set a financial goal to start saving")
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(goals) { goal in
                        Button {
                            editingGoal = goal
                        } label: {
                            GoalRow(goal: goal)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { indexSet in
                        HapticManager.impact(.medium)
                        for i in indexSet { context.delete(goals[i]) }
                    }
                }
            }
            .listStyle(.plain)
            .financeNavigationSurface()
            .navigationTitle(String(localized: "Goals"))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
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
                if let justCompleted = goals.first(where: { $0.progress >= 1.0 }) {
                    successGoalName = justCompleted.name
                }
                HapticManager.success()
                showSuccess = true
            }
            .overlay {
                if showSuccess {
                    SuccessOverlayView(
                        message: String(localized: "Goal Reached! 🎉"),
                        subtitle: successGoalName
                    ) { showSuccess = false }
                }
            }
        }
    }
}

private struct GoalRow: View {
    let goal: Goal

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(goal.name)
                    .font(.body)
                Spacer()
                Text("\(Int(goal.progress * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: goal.progress)
                .tint(goal.progress >= 1.0 ? .green : .blue)
            HStack {
                Text(CurrencyFormatter.string(from: goal.currentAmount))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text("/ \(CurrencyFormatter.string(from: goal.targetAmount))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                if !goal.note.isEmpty {
                    Text(goal.note)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
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
            Form {
                Section(String(localized: "Goal")) {
                    TextField(String(localized: "Name"), text: $name)
                    TextField(String(localized: "Target Amount"), text: $targetText)
                        .financeNumericKeyboard()
                    TextField(String(localized: "Current Amount"), text: $currentText)
                        .financeNumericKeyboard()
                }
                Section(String(localized: "Note")) {
                    TextField(String(localized: "Optional note"), text: $note)
                }
            }
            .keyboardDismissable()
            .financeNavigationSurface()
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
