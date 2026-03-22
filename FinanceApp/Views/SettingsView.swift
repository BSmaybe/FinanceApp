import SwiftUI
import SwiftData
import UserNotifications

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var themeStore = ThemeStore.shared
    @AppStorage("budgetRollover") private var rolloverEnabled = false
    @AppStorage("budgetNotificationsEnabled") private var budgetNotificationsEnabled = true
    @AppStorage("subscriptionRemindersEnabled") private var subscriptionRemindersEnabled = true
    @AppStorage("debtRemindersEnabled") private var debtRemindersEnabled = true
    @State private var notificationsAuthorized = false
    @State private var showingCategories = false
    @State private var showingSubscriptions = false
    @State private var showingDebts = false
    @State private var showingExport = false
    @State private var showingBackupExport = false
    @State private var showingBackupImport = false
    @State private var showingRestoreConfirm = false
    @State private var backupDocument: BackupDocument?
    @State private var pendingImportData: Data?
    @State private var backupError: String?
    @State private var showingBackupError = false
    @State private var showingRestoreSuccess = false
    @State private var showingCSVImport = false
    @State private var csvImportResult: String?
    @State private var showingCSVResult = false
    @AppStorage("autoBackupInterval") private var autoBackupInterval = "off"
    @AppStorage("lastAutoBackupDate") private var lastAutoBackupTimestamp: Double = 0
    @AppStorage("liveActivityEnabled") private var liveActivityEnabled = false
    @State private var captureDiagnostics = PendingCaptureStore.diagnostics()

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "Appearance")) {
                    ForEach(ThemePalette.allCases, id: \.id) { palette in
                        Button {
                            themeStore.selectedTheme = palette.id
                        } label: {
                            HStack(spacing: 12) {
                                ZStack(alignment: .bottomTrailing) {
                                    Circle()
                                        .fill(palette.primaryAccent)
                                        .frame(width: 28, height: 28)
                                    Circle()
                                        .fill(palette.secondaryAccent)
                                        .frame(width: 13, height: 13)
                                        .offset(x: 4, y: 4)
                                }
                                .frame(width: 32, height: 32)
                                HStack(spacing: 4) {
                                    Text(palette.name)
                                        .foregroundStyle(.primary)
                                    if palette.isDark {
                                        Image(systemName: "moon.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if themeStore.selectedTheme == palette.id {
                                    Image(systemName: "checkmark")
                                        .fontWeight(.semibold)
                                        .foregroundStyle(AppTheme.primaryAccent)
                                }
                            }
                        }
                    }
                }

                Section(String(localized: "Categories")) {
                    Button {
                        showingCategories = true
                    } label: {
                        Label(String(localized: "Manage Categories"), systemImage: "square.grid.2x2")
                    }
                }

                Section(String(localized: "Budget")) {
                    Toggle(String(localized: "Rollover unused budget"), isOn: $rolloverEnabled)
                }

                Section(String(localized: "Manage")) {
                    Button {
                        showingSubscriptions = true
                    } label: {
                        Label(String(localized: "Subscriptions"), systemImage: "repeat.circle")
                            .foregroundStyle(AppTheme.primaryAccent)
                    }
                    Button {
                        showingDebts = true
                    } label: {
                        Label(String(localized: "Debts"), systemImage: "creditcard.trianglebadge.exclamationmark")
                            .foregroundStyle(.red)
                    }
                }

                Section(String(localized: "Data")) {
                    Button {
                        showingExport = true
                    } label: {
                        Label(String(localized: "Export Data"), systemImage: "square.and.arrow.up")
                            .foregroundStyle(AppTheme.primaryAccent)
                    }
                    Button {
                        showingCSVImport = true
                    } label: {
                        Label(String(localized: "Import CSV"), systemImage: "arrow.down.doc.fill")
                            .foregroundStyle(AppTheme.secondaryAccent)
                    }
                }

                Section(String(localized: "Backup")) {
                    Button {
                        createBackup()
                    } label: {
                        Label(String(localized: "Create Backup"), systemImage: "arrow.down.doc")
                            .foregroundStyle(AppTheme.primaryAccent)
                    }
                    Button {
                        showingBackupImport = true
                    } label: {
                        Label(String(localized: "Restore from Backup"), systemImage: "arrow.up.doc")
                            .foregroundStyle(AppTheme.secondaryAccent)
                    }
                    Picker(String(localized: "Auto-Backup"), selection: $autoBackupInterval) {
                        ForEach(AutoBackupInterval.allCases, id: \.self) { interval in
                            Text(interval.localizedName).tag(interval.rawValue)
                        }
                    }
                    if lastAutoBackupTimestamp > 0 {
                        LabeledContent(String(localized: "Last Auto-Backup"),
                            value: Date(timeIntervalSince1970: lastAutoBackupTimestamp)
                                .formatted(date: .abbreviated, time: .shortened))
                    }
                }

                Section(String(localized: "Notifications")) {
                    Toggle(String(localized: "Budget alerts"), isOn: $budgetNotificationsEnabled)
                    Toggle(String(localized: "Subscription reminders"), isOn: $subscriptionRemindersEnabled)
                    Toggle(String(localized: "Debt payment reminders"), isOn: $debtRemindersEnabled)
                    if !notificationsAuthorized {
                        Button(String(localized: "Enable in Settings")) {
                            openSystemNotificationSettings()
                        }
                        .foregroundStyle(AppTheme.primaryAccent)
                    }
                }

                Section(String(localized: "Live Activity")) {
                    Toggle(String(localized: "Daily Budget in Dynamic Island"), isOn: $liveActivityEnabled)
                    Text(String(localized: "Shows today's spending progress in Dynamic Island and Lock Screen."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section(String(localized: "Auto-Capture Purchases")) {
                    if let shortcutsURL = URL(string: "shortcuts://") {
                        Link(destination: shortcutsURL) {
                            Label(String(localized: "Open Shortcuts"), systemImage: "square.grid.2x2")
                                .foregroundStyle(AppTheme.primaryAccent)
                        }
                    }

                    if let testURL = URL(string: "financeapp://capture?amount=1290.5&merchant=Coffee%20Shop&currency=USD&source=shortcut_capture") {
                        Link(destination: testURL) {
                            Label(String(localized: "Run Capture Test"), systemImage: "checkmark.bubble")
                                .foregroundStyle(AppTheme.secondaryAccent)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "1) In Shortcuts create Personal Automation with Transaction trigger."))
                        Text(String(localized: "2) Select cards and map Amount/Merchant/Date/Currency to URL query fields."))
                        Text(String(localized: "3) Use URL financeapp://capture and run a test payment flow."))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 2)
                }

                Section(String(localized: "Capture Diagnostics")) {
                    LabeledContent(String(localized: "Last Received"), value: formattedCaptureTimestamp(captureDiagnostics.lastReceivedAt))
                    LabeledContent(String(localized: "Last Opened in Quick Add"), value: formattedCaptureTimestamp(captureDiagnostics.lastConsumedAt))

                    if let payload = captureDiagnostics.lastReceivedPayload {
                        LabeledContent(String(localized: "Source"), value: payload.sourceDisplayName)
                        LabeledContent(String(localized: "Merchant"), value: payload.merchant ?? String(localized: "No merchant"))
                        LabeledContent(String(localized: "Amount"), value: formattedAmount(payload.amount))
                        LabeledContent(String(localized: "Payment Date"), value: formattedCaptureTimestamp(payload.date))
                    } else {
                        Text(String(localized: "No captures yet"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if captureDiagnostics.pendingPayload != nil {
                        Label(String(localized: "Pending capture is waiting to be opened"), systemImage: "clock.arrow.circlepath")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryAccent)
                    }

                    Button(String(localized: "Refresh Diagnostics")) {
                        refreshCaptureDiagnostics()
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(String(localized: "Quick Add on Home Screen"), systemImage: "plus.app")
                            .font(.body)
                        Text(String(localized: "Open Shortcuts app → tap + → search \"Add Transaction\" → tap Add to Home Screen"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text(String(localized: "Home Screen"))
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.canvas)
            .tint(AppTheme.primaryAccent)
            .navigationTitle(String(localized: "Settings"))
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(AppTheme.surface, for: .navigationBar)
            .sheet(isPresented: $showingCategories) {
                CategoriesView()
            }
            .sheet(isPresented: $showingSubscriptions) {
                SubscriptionsView()
            }
            .sheet(isPresented: $showingDebts) {
                DebtsView()
            }
            .sheet(isPresented: $showingExport) {
                ExportView()
            }
            .fileExporter(
                isPresented: $showingBackupExport,
                document: backupDocument,
                contentType: .json,
                defaultFilename: "FinanceApp_Backup_\(Self.dateString()).json"
            ) { result in
                if case .failure(let error) = result {
                    backupError = error.localizedDescription
                    showingBackupError = true
                }
            }
            .fileImporter(
                isPresented: $showingBackupImport,
                allowedContentTypes: [.json]
            ) { result in
                handleImport(result)
            }
            .fileImporter(
                isPresented: $showingCSVImport,
                allowedContentTypes: [.commaSeparatedText, .plainText]
            ) { result in
                handleCSVImport(result)
            }
            .alert(String(localized: "Import Result"), isPresented: $showingCSVResult) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(csvImportResult ?? "")
            }
            .alert(String(localized: "Restore Backup?"), isPresented: $showingRestoreConfirm) {
                Button(String(localized: "Cancel"), role: .cancel) {
                    pendingImportData = nil
                }
                Button(String(localized: "Restore"), role: .destructive) {
                    restoreBackup()
                }
            } message: {
                Text(String(localized: "This will replace all current data. This cannot be undone."))
            }
            .alert(String(localized: "Error"), isPresented: $showingBackupError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(backupError ?? "")
            }
            .alert(String(localized: "Backup Restored"), isPresented: $showingRestoreSuccess) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(String(localized: "All data has been restored successfully."))
            }
            .onAppear {
                refreshCaptureDiagnostics()
                Task { await checkNotificationStatus() }
            }
            .onChange(of: scenePhase) { _, newValue in
                guard newValue == .active else { return }
                refreshCaptureDiagnostics()
                Task { await checkNotificationStatus() }
            }
        }
    }

    private func createBackup() {
        do {
            let data = try BackupService.exportData(context: modelContext)
            backupDocument = BackupDocument(data: data)
            showingBackupExport = true
        } catch {
            backupError = error.localizedDescription
            showingBackupError = true
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            guard url.startAccessingSecurityScopedResource() else {
                backupError = String(localized: "Cannot access file")
                showingBackupError = true
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            do {
                let data = try Data(contentsOf: url)
                // Validate JSON before confirming
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                _ = try decoder.decode(BackupData.self, from: data)
                pendingImportData = data
                showingRestoreConfirm = true
            } catch {
                backupError = String(localized: "Invalid backup file: \(error.localizedDescription)")
                showingBackupError = true
            }
        case .failure(let error):
            backupError = error.localizedDescription
            showingBackupError = true
        }
    }

    private func handleCSVImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            guard url.startAccessingSecurityScopedResource() else {
                backupError = String(localized: "Cannot access file")
                showingBackupError = true
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            do {
                let data = try Data(contentsOf: url)
                let importResult = try CSVImportService.importCSV(data, context: modelContext)
                var msg = String(localized: "Imported: \(importResult.imported)")
                if importResult.skipped > 0 {
                    msg += "\n" + String(localized: "Skipped: \(importResult.skipped)")
                }
                if !importResult.errors.isEmpty {
                    msg += "\n" + importResult.errors.prefix(3).joined(separator: "\n")
                }
                csvImportResult = msg
                showingCSVResult = true
            } catch {
                backupError = error.localizedDescription
                showingBackupError = true
            }
        case .failure(let error):
            backupError = error.localizedDescription
            showingBackupError = true
        }
    }

    private func restoreBackup() {
        guard let data = pendingImportData else { return }
        do {
            try BackupService.importData(data, context: modelContext)
            showingRestoreSuccess = true
        } catch {
            backupError = error.localizedDescription
            showingBackupError = true
        }
        pendingImportData = nil
    }

    private func refreshCaptureDiagnostics() {
        captureDiagnostics = PendingCaptureStore.diagnostics()
    }

    private func checkNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsAuthorized = settings.authorizationStatus == .authorized
    }

    private func openSystemNotificationSettings() {
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private func formattedCaptureTimestamp(_ date: Date?) -> String {
        guard let date else { return String(localized: "Never") }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func formattedAmount(_ amount: Decimal?) -> String {
        guard let amount else { return "—" }
        return CurrencyFormatter.string(from: amount)
    }

    private static func dateString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}
