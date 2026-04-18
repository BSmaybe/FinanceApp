import SwiftUI
import SwiftData

struct DebtsView: View {
    @Query private var debts: [Debt]
    @Environment(\.modelContext) private var modelContext
    @State private var showingAdd = false
    @State private var showingPayoff = false
    @State private var editingDebt: Debt?
    @State private var showSuccess = false
    @State private var successDebtName = ""

    private var activeDebts: [Debt] {
        debts
            .filter { $0.remainingAmount > 0 }
            .sorted { $0.remainingAmount > $1.remainingAmount }
    }

    private var paidDebts: [Debt] {
        debts
            .filter { $0.remainingAmount <= 0 }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var paidDebtsCount: Int { paidDebts.count }

    private var totalRemaining: Decimal {
        activeDebts.reduce(.zero) { $0 + $1.remainingAmount }
    }

    private var totalMinPayment: Decimal {
        activeDebts.reduce(.zero) { $0 + $1.minimumPayment }
    }

    private var dueSoonCount: Int {
        activeDebts.filter { isDueSoon(day: $0.dueDay, within: 7) }.count
    }

    private var averageRateLabel: String {
        let ratedDebts = activeDebts.filter { $0.interestRate > .zero }
        guard !ratedDebts.isEmpty else { return String(localized: "No APR") }
        let total = ratedDebts.reduce(Decimal.zero) { $0 + $1.interestRate }
        let average = total / Decimal(ratedDebts.count)
        let percent = NSDecimalNumber(decimal: average * 100).doubleValue
        return String(format: "%.1f%%", percent)
    }

    private var statusBadge: String {
        if activeDebts.isEmpty {
            return String(localized: "No active debt")
        }
        if dueSoonCount > 0 {
            return String(format: String(localized: "%lld due soon"), dueSoonCount)
        }
        return String(localized: "Payments in rhythm")
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

                        if debts.isEmpty {
                            emptyStateSection
                        } else {
                            overviewSection
                            activeSection

                            if !paidDebts.isEmpty {
                                paidSection
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle(String(localized: "Debts"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddEditDebtView()
            }
            .sheet(item: $editingDebt) { debt in
                AddEditDebtView(debt: debt)
            }
            .sheet(isPresented: $showingPayoff) {
                DebtPayoffView()
            }
            .onChange(of: paidDebtsCount) { old, new in
                guard new > old else { return }
                successDebtName = paidDebts.last?.name ?? ""
                HapticManager.success()
                showSuccess = true
                triggerLiveActivityCelebration()
            }
            .overlay {
                if showSuccess {
                    SuccessOverlayView(
                        message: String(localized: "Debt closed"),
                        subtitle: successDebtName
                    ) { showSuccess = false }
                }
            }
        }
    }

    private var heroSection: some View {
        HeroMetricCard(
            title: String(localized: "Debt payoff"),
            value: CurrencyFormatter.string(from: totalRemaining),
            supportingTitle: String(localized: "Monthly payments"),
            supportingValue: CurrencyFormatter.string(from: totalMinPayment),
            note: String(localized: "Track balances, due days and repayment pace in one place."),
            badgeText: statusBadge
        )
    }

    private var overviewSection: some View {
        LazyVGrid(columns: summaryColumns, spacing: 12) {
            CompactSummaryCard(
                title: String(localized: "Active"),
                value: "\(activeDebts.count)",
                detail: String(localized: "Balances still open"),
                systemImage: "creditcard.trianglebadge.exclamationmark",
                tint: AppTheme.danger
            )

            CompactSummaryCard(
                title: String(localized: "Due soon"),
                value: "\(dueSoonCount)",
                detail: String(localized: "Payments in 7 days"),
                systemImage: "calendar.badge.clock",
                tint: AppTheme.warning
            )

            CompactSummaryCard(
                title: String(localized: "Paid off"),
                value: "\(paidDebts.count)",
                detail: String(localized: "Closed balances"),
                systemImage: "checkmark.seal.fill",
                tint: AppTheme.success
            )

            CompactSummaryCard(
                title: String(localized: "Average APR"),
                value: averageRateLabel,
                detail: String(localized: "Across balances with interest"),
                systemImage: "percent",
                tint: AppTheme.info
            )
        }
    }

    private var emptyStateSection: some View {
        SectionShell(
            title: String(localized: "Add your balances"),
            subtitle: String(localized: "Keep loans, cards and installment plans in one payoff view.")
        ) {
            VStack(spacing: 12) {
                InsightCard(
                    title: String(localized: "No debts tracked"),
                    value: String(localized: "Start with one balance"),
                    message: String(localized: "Once a debt is entered, you can watch repayment pace, due pressure and minimum payments from one screen."),
                    systemImage: "creditcard.fill",
                    tint: AppTheme.warning
                )

                ActionTile(
                    title: String(localized: "Add Debt"),
                    subtitle: String(localized: "Track a loan, card or installment plan."),
                    systemImage: "plus.circle.fill",
                    tint: AppTheme.danger
                ) {
                    showingAdd = true
                }
            }
        }
    }

    private var activeSection: some View {
        SectionShell(
            title: String(localized: "Open balances"),
            subtitle: String(localized: "Focus on upcoming payments and remaining balances."),
            trailing: {
                if !activeDebts.isEmpty {
                    smallActionButton(
                        title: String(localized: "Payoff Calculator"),
                        systemImage: "chart.line.downtrend.xyaxis",
                        tint: AppTheme.warning
                    ) {
                        showingPayoff = true
                    }
                }
            }
        ) {
            VStack(spacing: 12) {
                if activeDebts.isEmpty {
                    InsightCard(
                        title: String(localized: "No open balances"),
                        value: String(localized: "Everything here is closed"),
                        message: String(localized: "Any debts you finish paying will stay in the history section below."),
                        systemImage: "checkmark.circle.fill",
                        tint: AppTheme.success
                    )
                } else {
                    ForEach(activeDebts) { debt in
                        NavigationLink(destination: DebtDetailView(debt: debt)) {
                            DebtCard(debt: debt, closed: false)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(String(localized: "Edit Debt")) {
                                editingDebt = debt
                            }
                            Button(String(localized: "Delete"), role: .destructive) {
                                HapticManager.impact(.medium)
                                modelContext.delete(debt)
                            }
                        }
                    }
                }
            }
        }
    }

    private var paidSection: some View {
        SectionShell(
            title: String(localized: "Closed balances"),
            subtitle: String(localized: "Finished debts stay here as a clean payoff record.")
        ) {
            VStack(spacing: 12) {
                ForEach(paidDebts) { debt in
                    DebtCard(debt: debt, closed: true)
                        .contextMenu {
                            Button(String(localized: "Delete"), role: .destructive) {
                                HapticManager.impact(.medium)
                                modelContext.delete(debt)
                            }
                        }
                }
            }
        }
    }

    private func triggerLiveActivityCelebration() {
#if canImport(ActivityKit)
        if #available(iOS 16.2, *) {
            LiveActivityManager.triggerCelebration(.debtPaidOff)
        }
#endif
    }

    private func isDueSoon(day: Int, within limit: Int) -> Bool {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        var thisMonth = calendar.dateComponents([.year, .month], from: startOfToday)
        thisMonth.day = min(max(day, 1), 28)

        let nextDueDate: Date
        if let candidate = calendar.date(from: thisMonth), candidate >= startOfToday {
            nextDueDate = candidate
        } else {
            nextDueDate = calendar.date(byAdding: .month, value: 1, to: calendar.date(from: thisMonth) ?? startOfToday) ?? startOfToday
        }

        let delta = calendar.dateComponents([.day], from: startOfToday, to: nextDueDate).day ?? (limit + 1)
        return delta <= limit
    }

    private func smallActionButton(title: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(tint.opacity(0.12))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct DebtCard: View {
    let debt: Debt
    let closed: Bool

    private var tint: Color {
        closed ? AppTheme.success : AppTheme.danger
    }

    private var paidAmount: Decimal {
        let paid = debt.totalAmount - debt.remainingAmount
        return paid > .zero ? paid : .zero
    }

    private var dueLabel: String {
        String(format: String(localized: "Day %lld"), debt.dueDay)
    }

    private var rateLabel: String {
        let percent = NSDecimalNumber(decimal: debt.interestRate * 100).doubleValue
        return String(format: "%.1f%%", percent)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(debt.name)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)

                    HStack(spacing: 6) {
                        DebtTag(label: debt.type.localizedName, tint: tint)
                        DebtTag(label: dueLabel, tint: AppTheme.info)
                    }
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(CurrencyFormatter.string(from: closed ? debt.totalAmount : debt.remainingAmount))
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                    Text(closed ? String(localized: "Closed") : String(localized: "Remaining"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !closed {
                ProgressView(value: debt.progress)
                    .tint(tint)

                HStack(spacing: 12) {
                    debtMetric(title: String(localized: "Paid"), value: CurrencyFormatter.string(from: paidAmount))
                    Spacer(minLength: 0)
                    debtMetric(title: String(localized: "Min"), value: CurrencyFormatter.string(from: debt.minimumPayment))
                    Spacer(minLength: 0)
                    debtMetric(
                        title: debt.interestRate > .zero ? String(localized: "APR") : String(localized: "Due"),
                        value: debt.interestRate > .zero ? rateLabel : dueLabel,
                        tint: debt.interestRate > .zero ? AppTheme.warning : .primary
                    )
                }
            } else {
                HStack(spacing: 12) {
                    debtMetric(title: String(localized: "Original"), value: CurrencyFormatter.string(from: debt.totalAmount))
                    Spacer(minLength: 0)
                    debtMetric(title: String(localized: "Status"), value: String(localized: "Paid off"), tint: AppTheme.success)
                }
            }

            if !debt.note.isEmpty {
                Text(debt.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cockpitSurface(cornerRadius: 24, elevated: true)
    }

    private func debtMetric(title: String, value: String, tint: Color = .primary) -> some View {
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

private struct DebtTag: View {
    let label: String
    let tint: Color

    var body: some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
    }
}
