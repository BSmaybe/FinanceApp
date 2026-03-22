import AppIntents
import Foundation

struct PendingCapturePayload: Codable, Equatable, Identifiable {
    let captureId: String
    let amount: Decimal?
    let merchant: String?
    let date: Date
    let currency: String?
    let source: String
    let createdAt: Date

    var id: String { captureId }

    init(
        captureId: String = UUID().uuidString,
        amount: Decimal?,
        merchant: String?,
        date: Date = Date(),
        currency: String? = nil,
        source: String,
        createdAt: Date = Date()
    ) {
        self.captureId = captureId
        self.amount = amount
        self.merchant = merchant?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.date = date
        self.currency = currency?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.source = source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.createdAt = createdAt
    }

    var sourceDisplayName: String {
        switch source {
        case "apple_pay", "apple_pay_tap", "wallet":
            return String(localized: "Apple Pay")
        case "shortcut", "shortcuts", "shortcut_capture":
            return String(localized: "Shortcut Capture")
        case "deep_link", "deeplink":
            return String(localized: "Deep Link Capture")
        default:
            return String(localized: "Shortcut Capture")
        }
    }

    var sourceSystemImageName: String {
        switch source {
        case "apple_pay", "apple_pay_tap", "wallet":
            return "apple.logo"
        case "deep_link", "deeplink":
            return "link.circle.fill"
        default:
            return "bolt.horizontal.circle.fill"
        }
    }
}

enum PendingCaptureStore {
    private static let pendingPayloadKey = "pendingCapturePayload.v1"
    private static let lastConsumedCaptureIdKey = "pendingCaptureLastConsumedId.v1"
    private static let lastReceivedPayloadKey = "pendingCaptureLastReceivedPayload.v1"
    private static let lastReceivedAtKey = "pendingCaptureLastReceivedAt.v1"
    private static let lastConsumedAtKey = "pendingCaptureLastConsumedAt.v1"
    private static let maxPayloadAge: TimeInterval = 60 * 60 * 24

    struct Diagnostics {
        let pendingPayload: PendingCapturePayload?
        let lastReceivedPayload: PendingCapturePayload?
        let lastReceivedAt: Date?
        let lastConsumedAt: Date?
    }

    static func queue(_ payload: PendingCapturePayload) {
        guard let data = encode(payload) else { return }
        let defaults = defaultsStore()
        defaults.set(data, forKey: pendingPayloadKey)
        defaults.set(data, forKey: lastReceivedPayloadKey)
        defaults.set(Date().timeIntervalSince1970, forKey: lastReceivedAtKey)
    }

    static func consumePendingIfAvailable(now: Date = Date()) -> PendingCapturePayload? {
        let defaults = defaultsStore()
        guard let data = defaults.data(forKey: pendingPayloadKey) else {
            return nil
        }

        guard let payload = decode(data) else {
            defaults.removeObject(forKey: pendingPayloadKey)
            return nil
        }

        if now.timeIntervalSince(payload.createdAt) > maxPayloadAge {
            defaults.removeObject(forKey: pendingPayloadKey)
            return nil
        }

        let lastConsumedId = defaults.string(forKey: lastConsumedCaptureIdKey)
        if lastConsumedId == payload.captureId {
            defaults.removeObject(forKey: pendingPayloadKey)
            return nil
        }

        defaults.set(payload.captureId, forKey: lastConsumedCaptureIdKey)
        defaults.set(now.timeIntervalSince1970, forKey: lastConsumedAtKey)
        defaults.removeObject(forKey: pendingPayloadKey)
        return payload
    }

    static func diagnostics() -> Diagnostics {
        let defaults = defaultsStore()
        let pending = defaults.data(forKey: pendingPayloadKey).flatMap(decode(_:))
        let lastReceivedPayload = defaults.data(forKey: lastReceivedPayloadKey).flatMap(decode(_:))

        let lastReceivedTs = defaults.double(forKey: lastReceivedAtKey)
        let lastConsumedTs = defaults.double(forKey: lastConsumedAtKey)

        return Diagnostics(
            pendingPayload: pending,
            lastReceivedPayload: lastReceivedPayload,
            lastReceivedAt: lastReceivedTs > 0 ? Date(timeIntervalSince1970: lastReceivedTs) : nil,
            lastConsumedAt: lastConsumedTs > 0 ? Date(timeIntervalSince1970: lastConsumedTs) : nil
        )
    }

    static func clearAll() {
        for defaults in allStores() {
            defaults.removeObject(forKey: pendingPayloadKey)
            defaults.removeObject(forKey: lastConsumedCaptureIdKey)
            defaults.removeObject(forKey: lastReceivedPayloadKey)
            defaults.removeObject(forKey: lastReceivedAtKey)
            defaults.removeObject(forKey: lastConsumedAtKey)
        }
    }

    private static func defaultsStore() -> UserDefaults {
        UserDefaults(suiteName: WidgetDataProvider.suiteName) ?? .standard
    }

    private static func allStores() -> [UserDefaults] {
        var stores: [UserDefaults] = [.standard]
        if let suiteDefaults = UserDefaults(suiteName: WidgetDataProvider.suiteName),
           !stores.contains(where: { $0 === suiteDefaults }) {
            stores.append(suiteDefaults)
        }
        return stores
    }

    private static func encode(_ payload: PendingCapturePayload) -> Data? {
        try? JSONEncoder().encode(payload)
    }

    private static func decode(_ data: Data) -> PendingCapturePayload? {
        try? JSONDecoder().decode(PendingCapturePayload.self, from: data)
    }
}

enum CaptureDeepLinkParser {
    static func payload(from url: URL) -> PendingCapturePayload? {
        guard let scheme = url.scheme?.lowercased(), scheme == "financeapp" else {
            return nil
        }

        let host = url.host?.lowercased()
        let path = url.path.lowercased()
        let isCaptureRoute = host == "capture" || path == "/capture"
        guard isCaptureRoute else {
            return nil
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        func value(_ name: String) -> String? {
            components.queryItems?.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
        }

        let amount = parseDecimal(value("amount"))
        let merchant = value("merchant")
        let date = parseDate(value("date")) ?? Date()
        let currency = value("currency")
        let source = value("source") ?? "deep_link"

        return PendingCapturePayload(
            amount: amount,
            merchant: merchant,
            date: date,
            currency: currency,
            source: source
        )
    }

    private static func parseDecimal(_ raw: String?) -> Decimal? {
        guard let raw, !raw.isEmpty else { return nil }
        return Decimal(string: raw.replacingOccurrences(of: ",", with: "."))
    }

    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        if let timestamp = TimeInterval(raw) {
            return Date(timeIntervalSince1970: timestamp)
        }
        let isoWithFraction = ISO8601DateFormatter()
        isoWithFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoWithFraction.date(from: raw) {
            return date
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: raw)
    }
}

struct AddTransactionIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Transaction"
    static var description = IntentDescription("Quickly add a new expense transaction, optionally with amount and merchant from Apple Pay")
    static var openAppWhenRun = true

    @Parameter(title: "Amount", description: "Transaction amount")
    var amount: Double?

    @Parameter(title: "Merchant", description: "Merchant or store name")
    var merchant: String?

    @MainActor
    func perform() async throws -> some IntentResult {
        let payload = PendingCapturePayload(
            amount: amount.map { Decimal($0) },
            merchant: merchant,
            source: "shortcut_capture"
        )
        PendingCaptureStore.queue(payload)
        return .result()
    }
}
