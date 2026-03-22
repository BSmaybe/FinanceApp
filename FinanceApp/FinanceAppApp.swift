import SwiftUI
import SwiftData

@main
struct FinanceAppApp: App {
    private static let uiTestResetArgument = "UITEST_RESET"

    @Environment(\.scenePhase) private var scenePhase

    let container: ModelContainer
    let isUITestMode: Bool

    init() {
        isUITestMode = ProcessInfo.processInfo.arguments.contains(Self.uiTestResetArgument)

        // Ensure Application Support directory exists before SwiftData tries to write there
        let appSupport = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)

        let schema = Schema([Account.self, Category.self, Transaction.self, Budget.self, RecurringTransaction.self, Goal.self, Subscription.self, Debt.self])
        let config = ModelConfiguration(schema: schema)

        if isUITestMode {
            Self.removeStoreFiles(at: config.url)
            UserDefaults.standard.removeObject(forKey: SeedData.seededKey)
            UserDefaults.standard.removeObject(forKey: SeedData.seededV2Key)
            PendingCaptureStore.clearAll()
        }

        do {
            container = try ModelContainer(for: schema, configurations: config)
        } catch {
            // Schema changed (e.g. tags [String] → tagsRaw String). Delete store and start fresh.
            let url = config.url
            Self.removeStoreFiles(at: url)
            do {
                container = try ModelContainer(for: schema, configurations: config)
            } catch {
                fatalError("Failed to create ModelContainer: \(error)")
            }
        }
    }

    private static func removeStoreFiles(at url: URL) {
        try? FileManager.default.removeItem(at: url)
        let wal = url.deletingLastPathComponent().appending(path: url.lastPathComponent + "-wal")
        let shm = url.deletingLastPathComponent().appending(path: url.lastPathComponent + "-shm")
        try? FileManager.default.removeItem(at: wal)
        try? FileManager.default.removeItem(at: shm)
    }

    @AppStorage("autoBackupInterval") private var autoBackupInterval = "off"
    @AppStorage("lastAutoBackupDate") private var lastAutoBackupTimestamp: Double = 0

    @State private var captureQuickAddPayload: PendingCapturePayload?

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    SeedData.seedIfNeeded(context: container.mainContext)
                    RecurringTransactionProcessor.process(context: container.mainContext)
                    if !isUITestMode {
                        BudgetNotificationHelper.requestPermissionIfNeeded()
                    }
                    consumePendingCaptureIfNeeded()
                    runAutoBackupIfNeeded()
                }
                .onChange(of: scenePhase) { _, newValue in
                    guard newValue == .active else { return }
                    RecurringTransactionProcessor.process(context: container.mainContext)
                    consumePendingCaptureIfNeeded()
                    runAutoBackupIfNeeded()
                }
                .onOpenURL { url in
                    guard let payload = CaptureDeepLinkParser.payload(from: url) else { return }
                    PendingCaptureStore.queue(payload)
                    consumePendingCaptureIfNeeded()
                }
                .sheet(item: $captureQuickAddPayload) { payload in
                    QuickAddView(capturePayload: payload)
                }
        }
        .modelContainer(container)
    }

    private func runAutoBackupIfNeeded() {
        guard let interval = AutoBackupInterval(rawValue: autoBackupInterval), interval != .off else { return }
        let lastDate = lastAutoBackupTimestamp > 0 ? Date(timeIntervalSince1970: lastAutoBackupTimestamp) : nil
        if let newDate = AutoBackupManager.performBackupIfNeeded(context: container.mainContext, interval: interval, lastBackupDate: lastDate) {
            lastAutoBackupTimestamp = newDate.timeIntervalSince1970
        }
    }

    private func consumePendingCaptureIfNeeded() {
        guard let payload = PendingCaptureStore.consumePendingIfAvailable() else { return }
        if captureQuickAddPayload?.captureId == payload.captureId {
            return
        }
        captureQuickAddPayload = payload
    }
}
