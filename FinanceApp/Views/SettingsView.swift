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
    @AppStorage("debtReminderDays") private var debtReminderDays = 3
    @State private var notificationsAuthorized = false
    @State private var notificationAuthorizationStatus: UNAuthorizationStatus = .notDetermined
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
    @AppStorage("selectedLanguage") private var selectedLanguage = "system"
    @State private var showingLanguageRestart = false
    @State private var pendingLanguage = ""

    private static let languages: [(code: String, label: String, native: String)] = [
        ("system", "System",   "Авто"),
        ("en",     "English",  "English"),
        ("ru",     "Russian",  "Русский"),
        ("kk",     "Kazakh",   "Қазақша")
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "Personalization")) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(ThemePalette.allCases, id: \.id) { palette in
                                Button {
                                    themeStore.selectedTheme = palette.id
                                } label: {
                                    VStack(spacing: 6) {
                                        ZStack {
                                            Circle()
                                                .fill(palette.primaryAccent)
                                                .frame(width: 36, height: 36)
                                            Circle()
                                                .fill(palette.secondaryAccent)
                                                .frame(width: 14, height: 14)
                                                .offset(x: 10, y: 10)
                                            if palette.isDark {
                                                Image(systemName: "moon.fill")
                                                    .font(.system(size: 10))
                                                    .foregroundStyle(.white)
                                                    .offset(x: -8, y: -8)
                                            }
                                            if themeStore.selectedTheme == palette.id {
                                                Circle()
                                                    .stroke(AppTheme.primaryAccent, lineWidth: 2.5)
                                                    .frame(width: 44, height: 44)
                                            }
                                        }
                                        .frame(width: 44, height: 44)
                                        Text(palette.name)
                                            .font(.caption2)
                                            .foregroundStyle(themeStore.selectedTheme == palette.id ? AppTheme.primaryAccent : .secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 6)
                    }

                    NavigationLink {
                        DashboardSettingsView()
                    } label: {
                        Label(String(localized: "Dashboard Sections"), systemImage: "square.grid.3x1.below.line.grid.1x2")
                    }
                }

                Section(String(localized: "Language")) {
                    ForEach(Self.languages, id: \.code) { lang in
                        Button {
                            guard lang.code != selectedLanguage else { return }
                            pendingLanguage = lang.code
                            HapticManager.impact(.light)
                            showingLanguageRestart = true
                        } label: {
                            HStack {
                                Text(lang.native)
                                    .foregroundStyle(.primary)
                                if lang.code != "system" {
                                    Text("· \(lang.label)")
                                        .foregroundStyle(.secondary)
                                        .font(.subheadline)
                                }
                                Spacer()
                                if selectedLanguage == lang.code {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(AppTheme.primaryAccent)
                                        .fontWeight(.semibold)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section(String(localized: "Planning Rules")) {
                    Toggle(String(localized: "Rollover unused budget"), isOn: $rolloverEnabled)
                }

                Section(String(localized: "Notifications & Live Activity")) {
                    Toggle(String(localized: "Budget alerts"), isOn: $budgetNotificationsEnabled)
                    Toggle(String(localized: "Subscription reminders"), isOn: $subscriptionRemindersEnabled)
                    Toggle(String(localized: "Debt reminders"), isOn: $debtRemindersEnabled)
                    if debtRemindersEnabled {
                        Stepper(
                            String(format: String(localized: "%lld days before"), Int64(debtReminderDays)),
                            value: $debtReminderDays,
                            in: 1...14
                        )
                    }
                    Toggle(String(localized: "Daily Budget in Dynamic Island"), isOn: $liveActivityEnabled)
                    Text(String(localized: "Controls reminders, budget alerts, and Dynamic Island progress surfaces."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !notificationsAuthorized {
                        Button(notificationPermissionButtonTitle) {
                            handleNotificationPermissionAction()
                        }
                        .foregroundStyle(AppTheme.primaryAccent)
                    }
                }

                Section(String(localized: "Data & Backup")) {
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
                        LabeledContent(
                            String(localized: "Last Auto-Backup"),
                            value: Date(timeIntervalSince1970: lastAutoBackupTimestamp)
                                .formatted(date: .abbreviated, time: .shortened)
                        )
                    }
                }

                Section(String(localized: "Capture & Shortcuts")) {
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
                        Text(String(localized: "4) Add the Quick Add shortcut to Home Screen for faster capture."))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 2)

                    VStack(alignment: .leading, spacing: 8) {
                        Label(String(localized: "Quick Add on Home Screen"), systemImage: "plus.app")
                            .font(.body)
                        Text(String(localized: "Open Shortcuts app → tap + → search \"Add Transaction\" → tap Add to Home Screen"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section(String(localized: "Advanced & Diagnostics")) {
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
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.canvas)
            .tint(AppTheme.primaryAccent)
            .accessibilityIdentifier("settings.screen")
            .navigationTitle(String(localized: "Settings"))
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(AppTheme.surface, for: .navigationBar)
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
            .alert(String(localized: "Restart Required"), isPresented: $showingLanguageRestart) {
                Button(String(localized: "Restart Now"), role: .destructive) {
                    applyLanguage(pendingLanguage)
                }
                Button(String(localized: "Cancel"), role: .cancel) {
                    pendingLanguage = ""
                }
            } message: {
                Text(String(localized: "The app will restart to apply the new language."))
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
        notificationAuthorizationStatus = settings.authorizationStatus
        notificationsAuthorized = settings.authorizationStatus == .authorized
    }

    private var notificationPermissionButtonTitle: String {
        notificationAuthorizationStatus == .notDetermined
            ? String(localized: "Allow Notifications")
            : String(localized: "Enable in Settings")
    }

    private func handleNotificationPermissionAction() {
        if notificationAuthorizationStatus == .notDetermined {
            Task {
                _ = await NotificationService.requestPermission()
                await checkNotificationStatus()
            }
        } else {
            openSystemNotificationSettings()
        }
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

    private func applyLanguage(_ code: String) {
        selectedLanguage = code
        if code == "system" {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
        }
        UserDefaults.standard.synchronize()
        // Force restart to apply new language — acceptable for personal local-only app
        exit(0)
    }
}
