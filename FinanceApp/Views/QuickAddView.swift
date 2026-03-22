import SwiftUI
import SwiftData

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
    @State private var showingDetailedForm = false

    var capturePayload: PendingCapturePayload?
    var onOpenDetailed: (() -> Void)?
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
        return formattedNumber(
            from: decimal as NSDecimalNumber,
            minimumFractionDigits: 0,
            maximumFractionDigits: 2
        ) ?? amountString
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

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.canvas
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    typePickerSection
                    amountDisplaySection
                    accountChipsSection
                    categoryChipsSection
                    noteFieldSection
                    quickAmountsSection
                    numpad
                        .padding(.horizontal)

                    swipeToSave
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }
            }
            .accessibilityIdentifier("quickAdd.screen")
            .navigationTitle(String(localized: "Quick Add"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(AppTheme.surface, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                        .accessibilityIdentifier("quickAdd.cancelButton")
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button(String(localized: "Detailed")) {
                        if let onOpenDetailed {
                            dismiss()
                            onOpenDetailed()
                        } else {
                            showingDetailedForm = true
                        }
                    }
                    .font(.subheadline)
                    .accessibilityIdentifier("quickAdd.detailedButton")

                    Button(String(localized: "Save")) {
                        attemptSave()
                    }
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
            .onChange(of: amountString) { _, _ in
                refreshDuplicateCandidate()
            }
            .alert(String(localized: "Possible duplicate"), isPresented: $showingDuplicateAlert) {
                Button(String(localized: "Cancel"), role: .cancel) {
                    resetSwipeState()
                }
                Button(String(localized: "Save Anyway")) {
                    save()
                }
            } message: {
                Text(duplicateAlertMessage)
            }
            .sheet(isPresented: $showingDetailedForm) {
                NavigationStack {
                    AddEditTransactionView(
                        prefillType: type,
                        prefillAmount: parsedAmount > 0 ? parsedAmount : nil,
                        prefillDate: transactionDateForSave,
                        prefillAccountId: selectedAccountId,
                        prefillCategoryId: selectedCategoryId,
                        prefillNote: note.isEmpty ? nil : note
                    )
                }
            }
        }
        .accessibilityIdentifier("quickAdd.screen")
    }

    private var typePickerSection: some View {
        Picker("", selection: $type) {
            Text(String(localized: "Expense")).tag(TransactionType.expense)
            Text(String(localized: "Income")).tag(TransactionType.income)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 2)
        .onChange(of: type) { _, _ in
            selectedCategoryId = filteredCategories.first?.id
            userPickedCategory = false
            refreshDuplicateCandidate()
        }
    }

    private var amountDisplaySection: some View {
        VStack(spacing: 4) {
            if showSavedCheck {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityIdentifier("quickAdd.savedIndicator")
            } else {
                Text(displayAmount)
                    .font(.system(size: 56, weight: .thin, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("quickAdd.amountDisplay")
            }

            if let captureSourceLabel {
                HStack(spacing: 8) {
                    Label(captureSourceLabel, systemImage: captureSourceSystemImage)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(AppTheme.primaryAccent)
                        .clipShape(Capsule())

                    if let captureCurrencyCode, !captureCurrencyCode.isEmpty {
                        Text(captureCurrencyCode)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            } else if isFromApplePay {
                Label(String(localized: "Apple Pay"), systemImage: "apple.logo")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(AppTheme.primaryAccent)
                    .clipShape(Capsule())
            }

            if duplicateCandidate != nil {
                Label(String(localized: "Possible duplicate found"), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.top, 2)
                    .accessibilityIdentifier("quickAdd.duplicateWarning")
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(AppTheme.outline.opacity(0.45), lineWidth: 1)
                )
        )
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
        .animation(.easeInOut(duration: 0.2), value: displayAmount)
        .animation(.spring(duration: 0.4), value: showSavedCheck)
    }

    private var accountChipsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(accounts) { account in
                    chip(
                        label: account.name,
                        selected: selectedAccountId == account.id
                    ) {
                        selectedAccountId = account.id
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.bottom, 8)
    }

    private var categoryChipsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(filteredCategories) { category in
                    chip(
                        label: category.name,
                        color: Color(hex: category.colorHex),
                        selected: selectedCategoryId == category.id
                    ) {
                        selectedCategoryId = category.id
                        userPickedCategory = true
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.bottom, 8)
    }

    private var noteFieldSection: some View {
        TextField(String(localized: "Note..."), text: $note)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(AppTheme.outline.opacity(0.4), lineWidth: 1)
            )
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
            .accessibilityIdentifier("quickAdd.noteField")
            .onChange(of: note) { _, newValue in
                autoSelectCategory(for: newValue)
                refreshDuplicateCandidate()
            }
    }

    private var quickAmountsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(quickAmounts, id: \.self) { amount in
                    let amountStringValue = String(amount)
                    let isSelected = amountString == amountStringValue
                    Button {
                        mediumImpact.impactOccurred()
                        withAnimation(.easeInOut(duration: 0.15)) {
                            amountString = amountStringValue
                        }
                    } label: {
                        Text(formatQuickAmount(amount))
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(isSelected ? AppTheme.primaryAccent : AppTheme.surface)
                            .foregroundStyle(isSelected ? .white : .primary)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(AppTheme.outline.opacity(isSelected ? 0 : 0.45), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
        }
        .padding(.bottom, 6)
    }

    // MARK: - Swipe to Save

    private var swipeToSave: some View {
        SwipeToSaveButton(
            enabled: canSave,
            offset: $swipeOffset,
            completed: $swipeCompleted,
            onSave: attemptSave
        )
        .accessibilityIdentifier("quickAdd.swipeToSave")
        .frame(height: 60)
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
        VStack(spacing: 6) {
            ForEach(keys, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(row, id: \.self) { key in
                        Button {
                            lightImpact.impactOccurred()
                            withAnimation(.easeInOut(duration: 0.1)) {
                                handleKey(key)
                            }
                        } label: {
                            Text(key)
                                .font(.title2.weight(.regular))
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(AppTheme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(AppTheme.outline.opacity(0.45), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func chip(
        label: String,
        color: Color = AppTheme.primaryAccent,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(selected ? color : AppTheme.surface)
                .foregroundStyle(selected ? .white : .primary)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(AppTheme.outline.opacity(selected ? 0 : 0.45), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func formatQuickAmount(_ amount: Int) -> String {
        formattedNumber(
            from: NSNumber(value: amount),
            minimumFractionDigits: 0,
            maximumFractionDigits: 0
        ) ?? "\(amount)"
    }

    private func formattedNumber(
        from number: NSNumber,
        minimumFractionDigits: Int,
        maximumFractionDigits: Int
    ) -> String? {
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
            if !amountString.isEmpty {
                amountString.removeLast()
            }
        case localDecimalSeparator:
            if !amountString.contains(localDecimalSeparator) {
                amountString += amountString.isEmpty ? "0\(localDecimalSeparator)" : localDecimalSeparator
            }
        default:
            if amountString == "0" {
                amountString = key
            } else {
                if let sepIndex = amountString.range(of: localDecimalSeparator)?.lowerBound {
                    let decimals = amountString.distance(
                        from: amountString.index(after: sepIndex),
                        to: amountString.endIndex
                    )
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

        // Search recent transactions for matching note
        if let match = recentTransactions.first(where: { txn in
            guard !txn.note.isEmpty else { return false }
            let txnNote = txn.note.lowercased()
            return txnNote.contains(trimmed) || trimmed.contains(txnNote)
        }) {
            if let catId = match.categoryId {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedCategoryId = catId
                }
            }
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
        withAnimation(.spring(duration: 0.25)) {
            swipeOffset = 0
            swipeCompleted = false
        }
    }

    private func refreshDuplicateCandidate() {
        guard isCaptureFlow else {
            duplicateCandidate = nil
            return
        }
        guard type == .expense else {
            duplicateCandidate = nil
            return
        }
        guard parsedAmount > .zero else {
            duplicateCandidate = nil
            return
        }

        let merchant = normalizedMerchant(note)
        guard !merchant.isEmpty else {
            duplicateCandidate = nil
            return
        }

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
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }

    private func merchantMatches(input normalizedInput: String, transactionNote: String) -> Bool {
        let normalizedTransactionNote = normalizedMerchant(transactionNote)
        guard !normalizedTransactionNote.isEmpty else { return false }
        return normalizedTransactionNote == normalizedInput
            || normalizedTransactionNote.contains(normalizedInput)
            || normalizedInput.contains(normalizedTransactionNote)
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

        // Show checkmark animation then dismiss
        withAnimation(.spring(duration: 0.4)) {
            showSavedCheck = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            dismiss()
        }
    }
}

// MARK: - Swipe to Save Button

private struct SwipeToSaveButton: View {
    let enabled: Bool
    @Binding var offset: CGFloat
    @Binding var completed: Bool
    let onSave: () -> Void

    private let thumbSize: CGFloat = 52
    private let threshold: CGFloat = 0.65
    private let haptic = UIImpactFeedbackGenerator(style: .medium)

    var body: some View {
        GeometryReader { geo in
            let maxOffset = geo.size.width - thumbSize - 8
            let labelOpacity = labelOpacityValue(maxOffset: maxOffset)

            ZStack(alignment: .leading) {
                trackBackground
                label(opacity: labelOpacity)
                thumb(maxOffset: maxOffset)
            }
        }
    }

    private var trackBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(enabled ? AppTheme.primaryAccent.opacity(0.14) : Color.gray.opacity(0.1))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(AppTheme.outline.opacity(0.45), lineWidth: 1)
            )
    }

    private func label(opacity: Double) -> some View {
        Text(String(localized: "Swipe to save"))
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundColor(enabled ? Color.secondary : Color.gray)
            .frame(maxWidth: .infinity)
            .opacity(opacity)
    }

    private func thumb(maxOffset: CGFloat) -> some View {
        Circle()
            .fill(enabled ? AppTheme.primaryAccent : Color.gray.opacity(0.3))
            .frame(width: thumbSize, height: thumbSize)
            .overlay(thumbIcon)
            .padding(.leading, 4)
            .offset(x: offset)
            .gesture(dragGesture(maxOffset: maxOffset))
    }

    private var thumbIcon: some View {
        Image(systemName: completed ? "checkmark" : "arrow.right")
            .font(.body)
            .fontWeight(.semibold)
            .foregroundColor(.white)
    }

    private func labelOpacityValue(maxOffset: CGFloat) -> Double {
        let halfMax = maxOffset * 0.5
        guard halfMax > 0 else { return 1 }
        let value = 1 - offset / halfMax
        return max(0, Double(value))
    }

    private func dragGesture(maxOffset: CGFloat) -> some Gesture {
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
                    withAnimation(.spring(duration: 0.2)) {
                        offset = maxOffset
                        completed = true
                    }
                    onSave()
                } else {
                    withAnimation(.spring(duration: 0.3)) {
                        offset = 0
                    }
                }
            }
    }
}
