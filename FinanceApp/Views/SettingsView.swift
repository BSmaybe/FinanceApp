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
    @State private var showingDebts = false
    @State private var showingGoals = false
    @State private var showingSubscriptions = false
    @State private var showingRecurring = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true
    @AppStorage("selectedLanguage") private var selectedLanguage = "system"
    @State private var showingLanguageRestart = false
    @State private var pendingLanguage = ""
    @State private var pickerLanguage = "system"

    private static let languages: [(code: String, label: String, native: String)] = [
        ("system", "System",   "Авто"),
        ("en",     "English",  "English"),
        ("ru",     "Russian",  "Русский"),
        ("kk",     "Kazakh",   "Қазақша")
    ]

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    settingsHeroSection
                    personalizationSection
                    planningRulesSection
                    notificationsSection
                    dataBackupSection
                    captureShortcutsSection
                    onboardingSection
                    diagnosticsSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 32)
            }
            .financeNavigationSurface()
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
                pickerLanguage = selectedLanguage
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

    private var currentLanguageName: String {
        Self.languages.first(where: { $0.code == selectedLanguage })?.native ?? "Auto"
    }

    private var currentThemeName: String {
        themeStore.palette.name
    }

    private var liveStatusLabel: String {
        liveActivityEnabled ? String(localized: "Enabled") : String(localized: "Off")
    }

    private var settingsHeroSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "System control"))
                        .font(.system(.title3, design: .rounded).weight(.bold))
                    Text(String(localized: "Personalisation, alerts, capture and backup in one place."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Image(systemName: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryAccent)
                    .frame(width: 36, height: 36)
                    .background(AppTheme.surfaceMuted)
                    .clipShape(Circle())
            }

            HStack(spacing: 10) {
                settingsStatusPill(title: String(localized: "Theme"), value: currentThemeName, tint: AppTheme.primaryAccent)
                settingsStatusPill(title: String(localized: "Language"), value: currentLanguageName, tint: AppTheme.info)
                settingsStatusPill(title: String(localized: "Live Activity"), value: liveStatusLabel, tint: liveActivityEnabled ? AppTheme.success : AppTheme.warning)
            }
        }
        .cockpitSurface(cornerRadius: 28, elevated: true)
    }

    private var personalizationSection: some View {
        SectionShell(
            title: String(localized: "Personalization"),
            subtitle: String(localized: "Theme, language and app surfaces")
        ) {
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

            VStack(spacing: 10) {
                NavigationLink {
                    DashboardSettingsView()
                } label: {
                    SettingsAccessoryRow(
                        title: String(localized: "Dashboard Sections"),
                        subtitle: String(localized: "Choose what appears on the home overview."),
                        systemImage: "square.grid.3x1.below.line.grid.1x2",
                        tint: AppTheme.primaryAccent
                    ) {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)

                NavigationLink {
                    FeaturesSettingsView()
                } label: {
                    SettingsAccessoryRow(
                        title: String(localized: "Features"),
                        subtitle: String(localized: "Turn optional product modules on or off."),
                        systemImage: "square.stack.3d.up",
                        tint: AppTheme.info
                    ) {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)

                SettingsAccessoryRow(
                    title: String(localized: "Language"),
                    subtitle: String(localized: "Change labels and restart the app to apply."),
                    systemImage: "globe",
                    tint: AppTheme.sectionAccent
                ) {
                    Picker("", selection: $pickerLanguage) {
                        ForEach(Self.languages, id: \.code) { lang in
                            Text(lang.native).tag(lang.code)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .onChange(of: pickerLanguage) { _, newValue in
                        guard newValue != selectedLanguage else { return }
                        pendingLanguage = newValue
                        pickerLanguage = selectedLanguage
                        HapticManager.impact(.light)
                        showingLanguageRestart = true
                    }
                }
            }
        }
    }

    private var planningRulesSection: some View {
        SectionShell(
            title: String(localized: "Planning Rules"),
            subtitle: String(localized: "App-wide rules that affect monthly planning.")
        ) {
            SettingsAccessoryRow(
                title: String(localized: "Rollover unused budget"),
                subtitle: String(localized: "Carry unused room into the next month."),
                systemImage: "arrow.uturn.forward.circle",
                tint: AppTheme.warning
            ) {
                Toggle("", isOn: $rolloverEnabled)
                    .labelsHidden()
                    .tint(AppTheme.primaryAccent)
            }
        }
    }

    private var notificationsSection: some View {
        SectionShell(
            title: String(localized: "Notifications & Live Activity"),
            subtitle: String(localized: "Controls reminders, budget alerts, and Dynamic Island progress surfaces.")
        ) {
            VStack(spacing: 10) {
                SettingsAccessoryRow(
                    title: String(localized: "Budget alerts"),
                    subtitle: String(localized: "Warn when flexible spending is pushing the month."),
                    systemImage: "bell.badge.fill",
                    tint: AppTheme.warning
                ) {
                    Toggle("", isOn: $budgetNotificationsEnabled)
                        .labelsHidden()
                        .tint(AppTheme.primaryAccent)
                }

                SettingsAccessoryRow(
                    title: String(localized: "Subscription reminders"),
                    subtitle: String(localized: "Nudge before recurring payments land."),
                    systemImage: "repeat.circle.fill",
                    tint: AppTheme.primaryAccent
                ) {
                    Toggle("", isOn: $subscriptionRemindersEnabled)
                        .labelsHidden()
                        .tint(AppTheme.primaryAccent)
                }

                SettingsAccessoryRow(
                    title: String(localized: "Debt reminders"),
                    subtitle: String(localized: "Keep minimum payments visible before due dates."),
                    systemImage: "creditcard.circle.fill",
                    tint: AppTheme.danger
                ) {
                    Toggle("", isOn: $debtRemindersEnabled)
                        .labelsHidden()
                        .tint(AppTheme.primaryAccent)
                }

                if debtRemindersEnabled {
                    SettingsAccessoryRow(
                        title: String(localized: "Reminder lead time"),
                        subtitle: String(format: String(localized: "%lld days before"), Int64(debtReminderDays)),
                        systemImage: "calendar.badge.clock",
                        tint: AppTheme.info
                    ) {
                        Stepper("", value: $debtReminderDays, in: 1...14)
                            .labelsHidden()
                            .fixedSize()
                    }
                }

                SettingsAccessoryRow(
                    title: String(localized: "Daily Budget in Dynamic Island"),
                    subtitle: String(localized: "Show the current budget state outside the app."),
                    systemImage: "dynamicisland",
                    tint: liveActivityEnabled ? AppTheme.success : AppTheme.info
                ) {
                    Toggle("", isOn: $liveActivityEnabled)
                        .labelsHidden()
                        .tint(AppTheme.primaryAccent)
                }

                if !notificationsAuthorized {
                    Button(notificationPermissionButtonTitle) {
                        handleNotificationPermissionAction()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryAccent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
                }
            }
        }
    }

    private var dataBackupSection: some View {
        SectionShell(
            title: String(localized: "Data & Backup"),
            subtitle: String(localized: "Exports, imports and restore controls for your data.")
        ) {
            VStack(spacing: 10) {
                Button {
                    showingExport = true
                } label: {
                    SettingsAccessoryRow(
                        title: String(localized: "Export Data"),
                        subtitle: String(localized: "Create a shareable export of your data."),
                        systemImage: "square.and.arrow.up",
                        tint: AppTheme.primaryAccent
                    ) {
                        Image(systemName: "arrow.up.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)

                Button {
                    showingCSVImport = true
                } label: {
                    SettingsAccessoryRow(
                        title: String(localized: "Import CSV"),
                        subtitle: String(localized: "Bring transactions in from a CSV file."),
                        systemImage: "arrow.down.doc.fill",
                        tint: AppTheme.info
                    ) {
                        Image(systemName: "arrow.down.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)

                Button {
                    createBackup()
                } label: {
                    SettingsAccessoryRow(
                        title: String(localized: "Create Backup"),
                        subtitle: String(localized: "Save a full local snapshot before making changes."),
                        systemImage: "arrow.down.doc",
                        tint: AppTheme.success
                    ) {
                        Image(systemName: "arrow.down.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)

                Button {
                    showingBackupImport = true
                } label: {
                    SettingsAccessoryRow(
                        title: String(localized: "Restore from Backup"),
                        subtitle: String(localized: "Replace current data with a backup file."),
                        systemImage: "arrow.up.doc",
                        tint: AppTheme.warning
                    ) {
                        Image(systemName: "arrow.up.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)

                SettingsAccessoryRow(
                    title: String(localized: "Auto-Backup"),
                    subtitle: lastAutoBackupTimestamp > 0
                        ? Date(timeIntervalSince1970: lastAutoBackupTimestamp).formatted(date: .abbreviated, time: .shortened)
                        : String(localized: "No auto-backup yet"),
                    systemImage: "clock.arrow.circlepath",
                    tint: AppTheme.sectionAccent
                ) {
                    Picker("", selection: $autoBackupInterval) {
                        ForEach(AutoBackupInterval.allCases, id: \.self) { interval in
                            Text(interval.localizedName).tag(interval.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }
        }
    }

    private var captureShortcutsSection: some View {
        SectionShell(
            title: String(localized: "Capture & Shortcuts"),
            subtitle: String(localized: "Set up quick capture flows outside the app.")
        ) {
            VStack(spacing: 10) {
                if let shortcutsURL = URL(string: "shortcuts://") {
                    Link(destination: shortcutsURL) {
                        SettingsAccessoryRow(
                            title: String(localized: "Open Shortcuts"),
                            subtitle: String(localized: "Manage your personal automations and shortcuts."),
                            systemImage: "square.grid.2x2",
                            tint: AppTheme.primaryAccent
                        ) {
                            Image(systemName: "arrow.up.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                if let testURL = URL(string: "financeapp://capture?amount=1290.5&merchant=Coffee%20Shop&currency=USD&source=shortcut_capture") {
                    Link(destination: testURL) {
                        SettingsAccessoryRow(
                            title: String(localized: "Run Capture Test"),
                            subtitle: String(localized: "Verify that capture opens directly in Quick Add."),
                            systemImage: "checkmark.bubble",
                            tint: AppTheme.info
                        ) {
                            Image(systemName: "arrow.up.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "1) In Shortcuts create Personal Automation with Transaction trigger."))
                    Text(String(localized: "2) Select cards and map Amount/Merchant/Date/Currency to URL query fields."))
                    Text(String(localized: "3) Use URL financeapp://capture and run a test payment flow."))
                    Text(String(localized: "4) Add the Quick Add shortcut to Home Screen for faster capture."))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(AppTheme.surfaceMuted)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    Label(String(localized: "Quick Add on Home Screen"), systemImage: "plus.app")
                        .font(.body.weight(.semibold))
                    Text(String(localized: "Open Shortcuts app → tap + → search \"Add Transaction\" → tap Add to Home Screen"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(AppTheme.surfaceMuted)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    private var onboardingSection: some View {
        SectionShell(
            title: String(localized: "Onboarding"),
            subtitle: String(localized: "Replay the setup flow when you want a fresh walkthrough.")
        ) {
            Button {
                hasCompletedOnboarding = false
            } label: {
                SettingsAccessoryRow(
                    title: String(localized: "Replay Onboarding"),
                    subtitle: String(localized: "Start the guided setup again on next launch."),
                    systemImage: "arrow.counterclockwise",
                    tint: AppTheme.primaryAccent
                ) {
                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var diagnosticsSection: some View {
        SectionShell(
            title: String(localized: "Advanced & Diagnostics"),
            subtitle: String(localized: "Inspect capture status and last received payloads.")
        ) {
            VStack(spacing: 10) {
                SettingsAccessoryRow(
                    title: String(localized: "Last Received"),
                    subtitle: formattedCaptureTimestamp(captureDiagnostics.lastReceivedAt),
                    systemImage: "clock",
                    tint: AppTheme.info
                )

                SettingsAccessoryRow(
                    title: String(localized: "Last Opened in Quick Add"),
                    subtitle: formattedCaptureTimestamp(captureDiagnostics.lastConsumedAt),
                    systemImage: "bolt.horizontal.circle",
                    tint: AppTheme.primaryAccent
                )

                if let payload = captureDiagnostics.lastReceivedPayload {
                    SettingsAccessoryRow(
                        title: String(localized: "Source"),
                        subtitle: payload.sourceDisplayName,
                        systemImage: "tray.full.fill",
                        tint: AppTheme.sectionAccent
                    )
                    SettingsAccessoryRow(
                        title: String(localized: "Merchant"),
                        subtitle: payload.merchant ?? String(localized: "No merchant"),
                        systemImage: "building.2.crop.circle",
                        tint: AppTheme.success
                    )
                    SettingsAccessoryRow(
                        title: String(localized: "Amount"),
                        subtitle: formattedAmount(payload.amount),
                        systemImage: "banknote",
                        tint: AppTheme.success
                    )
                    SettingsAccessoryRow(
                        title: String(localized: "Payment Date"),
                        subtitle: formattedCaptureTimestamp(payload.date),
                        systemImage: "calendar",
                        tint: AppTheme.info
                    )
                } else {
                    SettingsAccessoryRow(
                        title: String(localized: "No captures yet"),
                        subtitle: String(localized: "Capture payloads will appear here after the first successful run."),
                        systemImage: "tray",
                        tint: AppTheme.warning
                    )
                }

                if captureDiagnostics.pendingPayload != nil {
                    SettingsAccessoryRow(
                        title: String(localized: "Pending capture"),
                        subtitle: String(localized: "Pending capture is waiting to be opened"),
                        systemImage: "clock.arrow.circlepath",
                        tint: AppTheme.warning
                    )
                }

                Button(String(localized: "Refresh Diagnostics")) {
                    refreshCaptureDiagnostics()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.primaryAccent)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func settingsStatusPill(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AppTheme.surfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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

private struct SettingsAccessoryRow<Accessory: View>: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    let tint: Color
    let accessory: Accessory

    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        tint: Color = AppTheme.primaryAccent,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 10)
            accessory
        }
        .padding(14)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(AppTheme.outline.opacity(0.45), lineWidth: 0.5)
        )
    }
}

extension SettingsAccessoryRow where Accessory == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        tint: Color = AppTheme.primaryAccent
    ) {
        self.init(title: title, subtitle: subtitle, systemImage: systemImage, tint: tint, accessory: { EmptyView() })
    }
}
