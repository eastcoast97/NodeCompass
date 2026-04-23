import Foundation

/// Persistent store for subscriptions the user has either cancelled themselves
/// or flagged as not-a-subscription (false positive from ghost detection).
///
/// Once a (merchant + amount) pair is marked here, `SpendingAnalyzer` and the
/// dashboard ghost-subscription card filter it out of future detections, so
/// the user never sees the same alert twice.
///
/// Match key is `merchant.lowercased().trimmed` + `round(amount * 100) / 100`.
/// A new charge from the same merchant at a *different* amount is still
/// detected (treated as a new plan / upgrade / new sub).
actor CancelledSubscriptionsStore {
    static let shared = CancelledSubscriptionsStore()

    struct Entry: Codable, Identifiable, Hashable {
        let id: UUID
        let merchantKey: String    // merchant.lowercased().trimmed
        let displayMerchant: String // original casing for reference
        let amount: Double          // rounded to 2dp
        let cancelledAt: Date
        let reason: Reason
    }

    enum Reason: String, Codable {
        case cancelled          // user said "I've cancelled this"
        case notASubscription   // user said "this isn't a subscription"
    }

    private(set) var entries: [Entry] = []
    private var matchKeys: Set<String> = []
    private let fileName = "cancelled_subscriptions.json"
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private init() {
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        loadFromDisk()
    }

    // MARK: - Public API

    /// Mark a subscription as cancelled or as a false positive.
    /// No-op if already present for the same merchant+amount.
    @discardableResult
    func markCancelled(merchant: String, amount: Double, reason: Reason) -> Entry? {
        let key = Self.matchKey(merchant: merchant, amount: amount)
        guard !matchKeys.contains(key) else { return nil }

        let entry = Entry(
            id: UUID(),
            merchantKey: Self.normalizeMerchant(merchant),
            displayMerchant: merchant,
            amount: Self.roundAmount(amount),
            cancelledAt: Date(),
            reason: reason
        )
        entries.append(entry)
        matchKeys.insert(key)
        saveToDisk()

        // Notify observers (dashboard VM, insights pipeline) to refresh.
        Task { @MainActor in
            NotificationCenter.default.post(
                name: NSNotification.Name("CancelledSubscriptionsChanged"),
                object: nil
            )
        }

        return entry
    }

    /// Whether a (merchant + amount) pair is suppressed from ghost detection.
    func isCancelled(merchant: String, amount: Double) -> Bool {
        matchKeys.contains(Self.matchKey(merchant: merchant, amount: amount))
    }

    /// All cancelled entries (for debugging / settings screens).
    func all() -> [Entry] { entries }

    /// Clear all entries — called when the user clears app data.
    func clearAll() {
        entries = []
        matchKeys = []
        saveToDisk()
    }

    // MARK: - Key Normalization

    private static func normalizeMerchant(_ merchant: String) -> String {
        merchant
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func roundAmount(_ amount: Double) -> Double {
        (amount * 100).rounded() / 100
    }

    private static func matchKey(merchant: String, amount: Double) -> String {
        "\(normalizeMerchant(merchant))|\(String(format: "%.2f", roundAmount(amount)))"
    }

    // MARK: - Persistence

    private var fileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(fileName)
    }

    private func saveToDisk() {
        do {
            let data = try encoder.encode(entries)
            try data.write(to: fileURL, options: .atomicWrite)
        } catch {
        }
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            entries = try decoder.decode([Entry].self, from: data)
            matchKeys = Set(entries.map {
                Self.matchKey(merchant: $0.merchantKey, amount: $0.amount)
            })
        } catch {
            entries = []
            matchKeys = []
        }
    }
}
