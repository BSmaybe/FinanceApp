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

    private var activeDebts: [Debt] { debts.filter { $0.remainingAmount > 0 } }
    private var paidDebts: [Debt] { debts.filter { $0.remainingAmount <= 0 } }
    private var paidDebtsCount: Int { paidDebts.count }
    private var totalRemaining: Decimal { activeDebts.reduce(.zero) { $0 + $1.remainingAmount } }
    private var totalMinPayment: Decimal { activeDebts.reduce(.zero) { $0 + $1.minimumPayment } }

    var body: some View {
        NavigationStack {
            List {
                if !activeDebts.isEmpty {
                    summarySection
                }
                activeSection
                if !paidDebts.isEmpty {
                    paidSection
                }
            }
            .listStyle(.plain)
            .financeNavigationSurface()
            .navigationTitle(String(localized: "Debts"))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAdd = true } label: {
                        Image(systemName: "plus")
                    }
                }
                if !activeDebts.isEmpty {
                    ToolbarItem(placement: .bottomBar) {
                        Button {
                            showingPayoff = true
                        } label: {
                            Label(String(localized: "Payoff Calculator"), systemImage: "chart.line.downtrend.xyaxis")
                        }
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
            }
            .overlay {
                if showSuccess {
                    SuccessOverlayView(
                        message: String(localized: "Debt Paid Off! 🎉"),
                        subtitle: successDebtName
                    ) { showSuccess = false }
                }
            }
        }
    }

    // MARK: - Sections

    private var summarySection: some View {
        Section {
            VStack(spacing: 8) {
                HStack {
                    Text(String(localized: "Total Debt"))
                        .foregroundStyle(AppTheme.danger)
                    Spacer()
                    Text(CurrencyFormatter.string(from: totalRemaining))
                        .font(.title2.bold())
                        .foregroundStyle(.primary)
                }
                HStack {
                    Text(String(localized: "Monthly Payments"))
                        .foregroundStyle(AppTheme.danger)
                    Spacer()
                    Text(CurrencyFormatter.string(from: totalMinPayment))
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
            }
            .padding(.vertical, 4)
            .listRowBackground(
                RoundedRectangle(cornerRadius: 12)
                    .fill(AppTheme.debtGradient)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
            )
        }
    }

    private var activeSection: some View {
        Section(String(localized: "Active")) {
            if activeDebts.isEmpty && debts.isEmpty {
                EmptyStateView(
                    icon: "creditcard.circle.fill",
                    title: String(localized: "No Debts"),
                    subtitle: String(localized: "Add a loan or installment to track payments")
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else if activeDebts.isEmpty {
                Text(String(localized: "No debts — tap + to add"))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(activeDebts) { debt in
                    NavigationLink(destination: DebtDetailView(debt: debt)) {
                        debtRow(debt)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            HapticManager.impact(.medium)
                            modelContext.delete(debt)
                        } label: {
                            Label(String(localized: "Delete"), systemImage: "trash")
                        }
                        Button { editingDebt = debt } label: {
                            Label(String(localized: "Edit Debt"), systemImage: "pencil")
                        }
                        .tint(AppTheme.primaryAccent)
                    }
                }
            }
        }
    }

    private var paidSection: some View {
        Section(String(localized: "Paid Off")) {
            ForEach(paidDebts) { debt in
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(debt.name)
                        .strikethrough()
                    Spacer()
                    Text(CurrencyFormatter.string(from: debt.totalAmount))
                        .foregroundStyle(.secondary)
                }
            }
            .onDelete { offsets in
                HapticManager.impact(.medium)
                for i in offsets { modelContext.delete(paidDebts[i]) }
            }
        }
    }

    private func debtRow(_ debt: Debt) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(debt.name)
                    .font(.headline)
                Spacer()
                Text(debt.type.localizedName)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(Capsule())
            }
            HStack {
                Text(CurrencyFormatter.string(from: debt.remainingAmount))
                    .font(.subheadline.bold())
                Text("/ \(CurrencyFormatter.string(from: debt.totalAmount))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if debt.interestRate > 0 {
                    Text("\(NSDecimalNumber(decimal: debt.interestRate * 100).doubleValue, specifier: "%.1f")%")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            HStack(spacing: 6) {
                ProgressView(value: debt.progress)
                    .tint(debt.progress >= 1.0 ? .green : AppTheme.primaryAccent)
                if let paid = debt.paidPaymentsCount, let total = debt.totalPaymentsCount, total > 0 {
                    Text("\(paid)/\(total)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, 4)
    }
}
