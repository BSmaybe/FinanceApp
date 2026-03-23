import SwiftUI
import SwiftData

struct QuickAddDetailedDraft: Identifiable {
    let id = UUID()
    let type: TransactionType
    let amount: Decimal?
    let date: Date
    let accountId: UUID?
    let categoryId: UUID?
    let note: String?
}

struct QuickAddView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var accounts: [Account]
    @Query private var categories: [Category]
    @Query(sort: \Transaction.date, order: .reverse) private var recentTransactions: [Transaction]

    @State private var type: TransactionType = .expense
    @State private var amountString: String = ""
    @State private var selectedAccountId: UUID?
    @State private var selectedCategoryId: UUID?
    @State private var note: String = ""
    @State private var isFromApplePay = false
    @State private var captureSourceLabel: String?
    @State private var captureSourceSystemImage = "bolt.horizontal.circle.fill"
    @State private var captureDate: Date = Date()
    @State private var captureCurrencyCode: String?
    @State private var duplicateCandidate: Transaction?
    @State private var showingDuplicateAlert = false
    @State private var userPickedCategory = false
    @State private var showSavedCheck = false
    @State private var swipeOffset: CGFloat = 0
    @State private var swipeCompleted = false
    @State private var detailedDraft: QuickAddDetailedDraft?

    var capturePayload: PendingCapturePayload?
    var onOpenDetailed: ((QuickAddDetailedDraft) -> Void)?
    var prefillAmount: Decimal?
    var prefillNote: String?
    var prefillCategoryId: UUID?

    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let successFeedback = UINotificationFeedbackGenerator()

    private var filteredCategories: [Category] {
        categories.filter { $0.type == (type == .income ? .income : .expense) }
    }

    private var localDecimalSeparator: String {
        Locale.current.decimalSeparator ?? "."
    }

    private var normalizedAmountString: String {
        amountString.replacingOccurrences(of: localDecimalSeparator, with: ".")
    }

    private var displayAmount: String {
        guard !amountString.isEmpty else { return "0" }
        guard let decimal = Decimal(string: normalizedAmountString) else { return amountString }
        return formattedNumber(from: decimal as NSDecimalNumber, minimumFractionDigits: 0, maximumFractionDigits: 2) ?? amountString
    }

    private var parsedAmount: Decimal {
        Decimal(string: normalizedAmountString) ?? .zero
    }

    private var canSave: Bool {
        parsedAmount > .zero && selectedAccountId != nil
    }

    private var isCaptureFlow: Bool {
        capturePayload != nil || captureSourceLabel != nil
    }

    private var transactionDateForSave: Date {
        isCaptureFlow ? captureDate : Date()
    }

    private var duplicateAlertMessage: String {
        guard let duplicateCandidate else {
            return String(localized: "A similar transaction already exists.")
        }
        let dateText = duplicateCandidate.date.formatted(date: .abbreviated, time: .shortened)
        let noteText = duplicateCandidate.note.isEmpty ? String(localized: "No note") : duplicateCandidate.note
        return "\(dateText) · \(noteText)"
    }

    private let quickAmounts: [Int] = [500, 1000, 2000, 5000, 10000]

    private var currentDetailedDraft: QuickAddDetailedDraft {
        QuickAddDetailedDraft(
            type: type,
            amount: parsedAmount > 0 ? parsedAmount : nil,
            date: transactionDateForSave,
            accountId: selectedAccountId,
            categoryId: selectedCategoryId,
            note: note.isEmpty ? nil : note
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.canvas.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Type picker — compact, no header label
                    Picker("", selection: $type) {
                        Text(String(localized: "Expense")).tag(TransactionType.expense)
                        Text(String(localized: "Income")).tag(TransactionType.income)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                    .onChange(of: type) { _, _ in
                        selectedCategoryId = filteredCategories.first?.id
                        userPickedCategory = false
                        refreshDuplicateCandidate()
                    }

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 10) {
                            amountDisplaySection
                            chipsRow
                            categoryRow
                            noteRow
                            quickAmountsRow
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                    }
                    .keyboardDismissable()

                    numpad.padding(.horizontal, 16)

                    swipeToSave
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
            }
            .navigationTitle(String(localized: "Quick Add"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                        .accessibilityIdentifier("quickAdd.cancelButton")
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button(String(localized: "Detailed")) {
                        let draft = currentDetailedDraft
                        if let onOpenDetailed {
                            onOpenDetailed(draft)
                        } else {
                            detailedDraft = draft
                        }
                    }
                    .font(.subheadline)
                    .accessibilityIdentifier("quickAdd.detailedButton")

                    Button(String(localized: "Save")) { attemptSave() }
                        .disabled(!canSave)
                        .accessibilityIdentifier("quickAdd.saveButton")
                }
            }
            .onAppear {
                selectedAccountId = accounts.first?.id
                selectedCategoryId = filteredCategories.first?.id
                let incomingAmount = capturePayload?.amount ?? prefillAmount
                if let incomingAmount, incomingAmount > 0 {
                    let formatted = (incomingAmount as NSDecimalNumber).stringValue
                    amountString = formatted.replacingOccurrences(of: ".", with: localDecimalSeparator)
                    isFromApplePay = true
                }
                let incomingMerchant = capturePayload?.merchant ?? prefillNote
                if let incomingMerchant, !incomingMerchant.isEmpty {
                    note = incomingMerchant
                    isFromApplePay = true
                }
                if let prefillCategoryId {
                    selectedCategoryId = prefillCategoryId
                    userPickedCategory = true
                }
                if let capturePayload {
                    captureSourceLabel = capturePayload.sourceDisplayName
                    captureSourceSystemImage = capturePayload.sourceSystemImageName
                    captureDate = capturePayload.date
                    captureCurrencyCode = capturePayload.currency?.uppercased()
                    isFromApplePay = true
                } else if isFromApplePay {
                    captureSourceLabel = String(localized: "Apple Pay")
                    captureSourceSystemImage = "apple.logo"
                }
                refreshDuplicateCandidate()
                lightImpact.prepare()
                mediumImpact.prepare()
            }
            .onChange(of: amountString) { _, _ in refreshDuplicateCandidate() }
            .alert(String(localized: "Possible duplicate"), isPresented: $showingDuplicateAlert) {
                Button(String(localized: "Cancel"), role: .cancel) { resetSwipeState() }
                Button(String(localized: "Save Anyway")) { save() }
            } message: {
                Text(duplicateAlertMessage)
            }
            .sheet(item: $detailedDraft) { draft in
                NavigationStack {
                    AddEditTransactionView(
                        prefillType: draft.type,
                        prefillAmount: draft.amount,
                        prefillDate: draft.date,
                        prefillAccountId: draft.accountId,
                        prefillCategoryId: draft.categoryId,
                        prefillNote: draft.note
                    )
                }
            }
        }
    }

    // MARK: - Amount display

    private var amountDisplaySection: some View {
        HStack(alignment: .lastTextBaseline) {
            if showSavedCheck {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(AppTheme.success)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityIdentifier("quickAdd.savedIndicator")
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(displayAmount)
                    .font(.system(size: 48, weight: .thin, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("quickAdd.amountDisplay")
            }
            VStack(alignment: .trailing, spacing: 3) {
                if let captureSourceLabel {
                    Label(captureSourceLabel, systemImage: captureSourceSystemImage)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppTheme.primaryAccent)
                        .clipShape(Capsule())
                }
                Text(captureCurrencyCode ?? Locale.current.currency?.identifier ?? "")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if duplicateCandidate != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(AppTheme.warning)
                        .accessibilityIdentifier("quickAdd.duplicateWarning")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .animation(.easeInOut(duration: 0.2), value: displayAmount)
        .animation(.spring(duration: 0.4), value: showSavedCheck)
    }

    // MARK: - Account chips

    private var chipsRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "Account"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(accounts) { account in
                        FilterChip(
                            label: account.name,
                            systemImage: "creditcard",
                            selected: selectedAccountId == account.id,
                            tint: AppTheme.info
                        ) { selectedAccountId = account.id }
                    }
                }
            }
        }
    }

    // MARK: - Category chips

    private var categoryRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "Category"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            if filteredCategories.isEmpty {
                Text(String(localized: "No categories yet"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(filteredCategories) { category in
                            FilterChip(
                                label: category.name,
                                systemImage: category.iconName,
                                selected: selectedCategoryId == category.id,
                                tint: Color(hex: category.colorHex)
                            ) {
                                selectedCategoryId = category.id
                                userPickedCategory = true
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Note

    private var noteRow: some View {
        TextField(String(localized: "Note (merchant, memo...)"), text: $note)
            .font(.subheadline)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityIdentifier("quickAdd.noteField")
            .onChange(of: note) { _, newValue in
                autoSelectCategory(for: newValue)
                refreshDuplicateCandidate()
            }
    }

    // MARK: - Quick amounts

    private var quickAmountsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(quickAmounts, id: \.self) { amount in
                    let str = String(amount)
                    FilterChip(
                        label: formatQuickAmount(amount),
                        selected: amountString == str,
                        tint: AppTheme.primaryAccent
                    ) {
                        mediumImpact.impactOccurred()
                        withAnimation(.easeInOut(duration: 0.15)) { amountString = str }
                    }
                }
            }
        }
    }

    // MARK: - Numpad

    private var keys: [[String]] {
        [
            ["7", "8", "9"],
            ["4", "5", "6"],
            ["1", "2", "3"],
            [localDecimalSeparator, "0", "⌫"]
        ]
    }

    private var numpad: some View {
        VStack(spacing: 5) {
            ForEach(keys, id: \.self) { row in
                HStack(spacing: 5) {
                    ForEach(row, id: \.self) { key in
                        Button {
                            lightImpact.impactOccurred()
                            withAnimation(.easeInOut(duration: 0.1)) { handleKey(key) }
                        } label: {
                            Text(key)
                                .font(.title3.weight(.medium))
                                .frame(maxWidth: .infinity)
                                .frame(height: 46)
                                .background(AppTheme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Swipe to save

    private var swipeToSave: some View {
        SwipeToSaveButton(
            enabled: canSave,
            offset: $swipeOffset,
            completed: $swipeCompleted,
            onSave: attemptSave
        )
        .accessibilityIdentifier("quickAdd.swipeToSave")
        .frame(height: 54)
    }

    // MARK: - Helpers

    private func formatQuickAmount(_ amount: Int) -> String {
        formattedNumber(from: NSNumber(value: amount), minimumFractionDigits: 0, maximumFractionDigits: 0) ?? "\(amount)"
    }

    private func formattedNumber(from number: NSNumber, minimumFractionDigits: Int, maximumFractionDigits: Int) -> String? {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = minimumFractionDigits
        formatter.maximumFractionDigits = maximumFractionDigits
        formatter.locale = Locale.current
        return formatter.string(from: number)
    }

    private func handleKey(_ key: String) {
        switch key {
        case "⌫":
            if !amountString.isEmpty { amountString.removeLast() }
        case localDecimalSeparator:
            if !amountString.contains(localDecimalSeparator) {
                amountString += amountString.isEmpty ? "0\(localDecimalSeparator)" : localDecimalSeparator
            }
        default:
            if amountString == "0" {
                amountString = key
            } else {
                if let sepIndex = amountString.range(of: localDecimalSeparator)?.lowerBound {
                    let decimals = amountString.distance(from: amountString.index(after: sepIndex), to: amountString.endIndex)
                    if decimals >= 2 { return }
                }
                amountString += key
            }
        }
        refreshDuplicateCandidate()
    }

    private func autoSelectCategory(for input: String) {
        guard !userPickedCategory else { return }
        let trimmed = input.trimmingCharacters(in: .whitespaces).lowercased()
        guard trimmed.count >= 2 else { return }
        if let match = recentTransactions.first(where: { txn in
            guard !txn.note.isEmpty else { return false }
            let txnNote = txn.note.lowercased()
            return txnNote.contains(trimmed) || trimmed.contains(txnNote)
        }), let catId = match.categoryId {
            withAnimation(.easeInOut(duration: 0.2)) { selectedCategoryId = catId }
        }
    }

    private func attemptSave() {
        guard canSave else { return }
        refreshDuplicateCandidate()
        if duplicateCandidate != nil {
            showingDuplicateAlert = true
            resetSwipeState()
            return
        }
        save()
    }

    private func resetSwipeState() {
        withAnimation(.spring(duration: 0.25)) { swipeOffset = 0; swipeCompleted = false }
    }

    private func refreshDuplicateCandidate() {
        guard isCaptureFlow, type == .expense, parsedAmount > .zero else {
            duplicateCandidate = nil
            return
        }
        let merchant = normalizedMerchant(note)
        guard !merchant.isEmpty else { duplicateCandidate = nil; return }
        let targetDate = transactionDateForSave
        let threshold: TimeInterval = 15 * 60
        duplicateCandidate = recentTransactions.first(where: { transaction in
            guard transaction.type == .expense else { return false }
            guard transaction.amount == parsedAmount else { return false }
            guard abs(transaction.date.timeIntervalSince(targetDate)) <= threshold else { return false }
            return merchantMatches(input: merchant, transactionNote: transaction.note)
        })
    }

    private func normalizedMerchant(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }

    private func merchantMatches(input normalizedInput: String, transactionNote: String) -> Bool {
        let n = normalizedMerchant(transactionNote)
        guard !n.isEmpty else { return false }
        return n == normalizedInput || n.contains(normalizedInput) || normalizedInput.contains(n)
    }

    private func save() {
        guard canSave, let accountId = selectedAccountId else { return }
        successFeedback.notificationOccurred(.success)
        let txn = Transaction(
            date: transactionDateForSave,
            amount: parsedAmount,
            type: type,
            accountId: accountId,
            categoryId: selectedCategoryId,
            note: note
        )
        modelContext.insert(txn)
        do {
            try modelContext.save()
        } catch {
            print("QuickAdd save error: \(error)")
        }
        if type == .expense {
            BudgetNotificationHelper.checkLimits(categoryId: selectedCategoryId, context: modelContext)
        }
        withAnimation(.spring(duration: 0.4)) { showSavedCheck = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { dismiss() }
    }
}

// MARK: - Swipe to Save Button

private struct SwipeToSaveButton: View {
    let enabled: Bool
    @Binding var offset: CGFloat
    @Binding var completed: Bool
    let onSave: () -> Void

    private let thumbSize: CGFloat = 46
    private let threshold: CGFloat = 0.65
    private let haptic = UIImpactFeedbackGenerator(style: .medium)

    var body: some View {
        GeometryReader { geo in
            let maxOffset = geo.size.width - thumbSize - 8
            let labelOpacity = max(0, Double(1 - offset / (maxOffset * 0.5)))

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(enabled ? AppTheme.surface : AppTheme.surfaceMuted)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(AppTheme.outline.opacity(0.45), lineWidth: 1)
                    )
                Text(enabled ? String(localized: "Swipe to save") : String(localized: "Add amount and account"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(enabled ? .secondary : Color.gray)
                    .frame(maxWidth: .infinity)
                    .opacity(labelOpacity)
                Circle()
                    .fill(enabled ? AppTheme.primaryAccent : AppTheme.chartNeutral)
                    .frame(width: thumbSize, height: thumbSize)
                    .overlay(
                        Image(systemName: completed ? "checkmark" : "arrow.right")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                    )
                    .padding(.leading, 4)
                    .offset(x: offset)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                guard enabled else { return }
                                let newOffset = max(0, min(value.translation.width, maxOffset))
                                offset = newOffset
                                if newOffset >= maxOffset * threshold && !completed {
                                    haptic.impactOccurred()
                                }
                            }
                            .onEnded { _ in
                                guard enabled else { return }
                                if offset >= maxOffset * threshold {
                                    withAnimation(.spring(duration: 0.2)) { offset = maxOffset; completed = true }
                                    onSave()
                                } else {
                                    withAnimation(.spring(duration: 0.3)) { offset = 0 }
                                }
                            }
                    )
            }
        }
    }
}
