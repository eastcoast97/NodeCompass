import Foundation
import UserNotifications

/// Detects and manages recurring subscriptions from transaction history.
/// Analyzes merchant frequency and amount patterns to surface active subscriptions.
actor SubscriptionManager {
    static let shared = SubscriptionManager()

    private let storeKey = "user_subscriptions"
    private var subscriptions: [Subscription] = []
    private var lastDetectionDate: String?

    // MARK: - Models

    struct Subscription: Codable, Identifiable {
        let id: String
        var merchant: String
        var amount: Double
        var frequency: BillingFrequency
        var category: String
        var lastChargeDate: Date?
        var nextChargeDate: Date?
        var isActive: Bool
        var cancelReminder: Date?     // user-set reminder to cancel
        var notes: String?
    }

    enum BillingFrequency: String, Codable, CaseIterable {
        case weekly, monthly, quarterly, yearly

        var monthlyEquivalent: Double {
            switch self {
            case .weekly: return 4.33
            case .monthly: return 1.0
            case .quarterly: return 1.0 / 3.0
            case .yearly: return 1.0 / 12.0
            }
        }

        var label: String {
            switch self {
            case .weekly: return "Weekly"
            case .monthly: return "Monthly"
            case .quarterly: return "Quarterly"
            case .yearly: return "Yearly"
            }
        }

        var icon: String {
            switch self {
            case .weekly: return "calendar.badge.clock"
            case .monthly: return "calendar"
            case .quarterly: return "calendar.badge.plus"
            case .yearly: return "calendar.circle"
            }
        }
    }

    // MARK: - Init

    private init() {
        subscriptions = loadFromDisk()
    }

    // MARK: - Detection

    /// Analyze transaction history to detect subscription-like patterns.
    /// Uses two detection paths:
    /// 1. Full interval analysis (merchant grouping + frequency detection)
    /// 2. Ghost subscription bridge (imports from TransactionStore.ghostSubscriptions)
    /// This ensures subscriptions shown on Dashboard always appear here too.
    func detectSubscriptions() async -> [Subscription] {
        var detected: [Subscription] = []
        let cal = Calendar.current

        // --- Path 1: Full interval analysis from raw transactions ---
        let transactions = await MainActor.run {
            TransactionStore.shared.transactions
        }

        // All non-credit transactions (handles "DEBIT", "debit", "Debit", etc.)
        let debits = transactions.filter { $0.type.lowercased() != "credit" }

        // Group by merchant (aggressively normalized)
        var byMerchant: [String: [StoredTransaction]] = [:]
        for txn in debits {
            let key = normalizeMerchant(txn.merchant)
            byMerchant[key, default: []].append(txn)
        }

        for (_, txns) in byMerchant {
            guard txns.count >= 2 else { continue }

            let sorted = txns.sorted { $0.date < $1.date }

            // Check amount consistency: amounts within 30% of median (relaxed from 20%)
            let amounts = sorted.map(\.amount)
            let sortedAmounts = amounts.sorted()
            let median = sortedAmounts[sortedAmounts.count / 2]
            let consistent = amounts.allSatisfy { abs($0 - median) / max(median, 1) < 0.3 }
            guard consistent else { continue }

            // Determine frequency from intervals
            var intervals: [Int] = []
            for i in 1..<sorted.count {
                let days = cal.dateComponents([.day], from: sorted[i - 1].date, to: sorted[i].date).day ?? 0
                intervals.append(days)
            }

            guard !intervals.isEmpty else { continue }
            let avgInterval = intervals.reduce(0, +) / intervals.count
            let totalSpanDays = intervals.reduce(0, +)

            let frequency: BillingFrequency
            // Weekly requires 3+ data points AND short average interval AND
            // enough span to confirm the pattern. Without this, a monthly sub
            // with 2 charges close together (prorated + regular) gets misclassified.
            if avgInterval <= 10 && sorted.count >= 3 && totalSpanDays >= 14 {
                frequency = .weekly
            } else if avgInterval <= 45 || totalSpanDays < 14 {
                frequency = .monthly
            } else if avgInterval <= 120 {
                frequency = .quarterly
            } else {
                frequency = .yearly
            }

            let lastDate = sorted.last!.date
            let nextDate = nextChargeDate(from: lastDate, frequency: frequency, cal: cal)
            let merchantName = sorted.first!.merchant

            if let sub = upsertSubscription(merchant: merchantName, amount: median, frequency: frequency,
                                             category: sorted.first?.category ?? "Subscriptions",
                                             lastCharge: lastDate, nextCharge: nextDate) {
                detected.append(sub)
            }
        }

        // --- Path 2: Bridge ghost subscriptions from TransactionStore ---
        // Ghost subs use exact amount matching (merchant_AMOUNTINCENTS).
        // If TransactionStore sees them, SubscriptionManager should too.
        let ghosts = await MainActor.run {
            TransactionStore.shared.ghostSubscriptions
        }

        for ghost in ghosts {
            let normalizedKey = normalizeMerchant(ghost.merchant)
            // Skip if we already detected this merchant via Path 1
            let alreadyDetected = detected.contains { normalizeMerchant($0.merchant) == normalizedKey }
            let alreadyTracked = subscriptions.contains { normalizeMerchant($0.merchant) == normalizedKey }
            if alreadyDetected || alreadyTracked { continue }

            let frequency = ghostFrequencyToBilling(ghost.frequency)
            let lastCharge = debits
                .filter { normalizeMerchant($0.merchant) == normalizedKey }
                .sorted { $0.date > $1.date }
                .first?.date ?? Date()
            let nextDate = nextChargeDate(from: lastCharge, frequency: frequency, cal: cal)

            let sub = Subscription(
                id: UUID().uuidString,
                merchant: ghost.merchant,
                amount: ghost.amount,
                frequency: frequency,
                category: "Subscriptions",
                lastChargeDate: lastCharge,
                nextChargeDate: nextDate,
                isActive: true,
                cancelReminder: nil,
                notes: nil
            )
            detected.append(sub)
        }

        // Merge and persist
        mergeDetected(detected)
        saveToDisk()

        return subscriptions.filter(\.isActive)
    }

    // MARK: - Detection Helpers

    /// Normalize merchant name for grouping (strip suffixes, lowercase, trim)
    private func normalizeMerchant(_ name: String) -> String {
        var n = name.lowercased().trimmingCharacters(in: .whitespaces)
        // Strip common suffixes: "Inc", "LLC", "Ltd", "Co", trailing numbers
        let suffixes = [" inc", " llc", " ltd", " co", " corp", " inc.", " llc.", " ltd."]
        for suffix in suffixes {
            if n.hasSuffix(suffix) { n = String(n.dropLast(suffix.count)) }
        }
        return n.trimmingCharacters(in: .whitespaces)
    }

    private func nextChargeDate(from lastDate: Date, frequency: BillingFrequency, cal: Calendar) -> Date? {
        switch frequency {
        case .weekly:    return cal.date(byAdding: .day, value: 7, to: lastDate)
        case .monthly:   return cal.date(byAdding: .month, value: 1, to: lastDate)
        case .quarterly: return cal.date(byAdding: .month, value: 3, to: lastDate)
        case .yearly:    return cal.date(byAdding: .year, value: 1, to: lastDate)
        }
    }

    private func ghostFrequencyToBilling(_ freq: String) -> BillingFrequency {
        switch freq.lowercased() {
        case "weekly":    return .weekly
        case "monthly":   return .monthly
        case "quarterly": return .quarterly
        case "yearly":    return .yearly
        default:          return .monthly
        }
    }

    /// Upsert a subscription (update existing or create new). Returns the subscription.
    private func upsertSubscription(merchant: String, amount: Double, frequency: BillingFrequency,
                                     category: String, lastCharge: Date, nextCharge: Date?) -> Subscription? {
        if let idx = subscriptions.firstIndex(where: { normalizeMerchant($0.merchant) == normalizeMerchant(merchant) }) {
            subscriptions[idx].amount = amount
            subscriptions[idx].lastChargeDate = lastCharge
            subscriptions[idx].nextChargeDate = nextCharge
            subscriptions[idx].frequency = frequency
            return subscriptions[idx]
        } else {
            return Subscription(
                id: UUID().uuidString,
                merchant: merchant,
                amount: amount,
                frequency: frequency,
                category: category,
                lastChargeDate: lastCharge,
                nextChargeDate: nextCharge,
                isActive: true,
                cancelReminder: nil,
                notes: nil
            )
        }
    }

    // MARK: - Queries

    /// All subscriptions (active and inactive), detecting if stale.
    func allSubscriptions() async -> [Subscription] {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let todayKey = dateFormatter.string(from: Date())

        // Re-detect periodically (once a day)
        if lastDetectionDate != todayKey {
            _ = await detectSubscriptions()
            lastDetectionDate = todayKey
        }

        return subscriptions
    }

    /// Sum of all active subscriptions normalized to a monthly cost.
    func monthlyTotal() async -> Double {
        let active = subscriptions.filter(\.isActive)
        return active.reduce(0) { total, sub in
            total + (sub.amount * sub.frequency.monthlyEquivalent)
        }
    }

    /// Sum of all active subscriptions normalized to a yearly cost.
    func yearlyTotal() async -> Double {
        let monthly = await monthlyTotal()
        return monthly * 12
    }

    // MARK: - User Actions

    /// Set a reminder date to cancel a subscription.
    func setCancelReminder(id: String, date: Date) {
        guard let idx = subscriptions.firstIndex(where: { $0.id == id }) else { return }
        subscriptions[idx].cancelReminder = date
        saveToDisk()

        // Schedule a local notification for the reminder
        let sub = subscriptions[idx]
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "Cancel Reminder"
        content.body = "Reminder: Consider cancelling \(sub.merchant) (\(NC.money(sub.amount))/mo)"
        content.sound = .default

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: "cancel_\(sub.id)", content: content, trigger: trigger)
        center.add(request)
    }

    /// Mark a subscription as inactive (cancelled / no longer recurring).
    func markInactive(id: String) {
        guard let idx = subscriptions.firstIndex(where: { $0.id == id }) else { return }
        subscriptions[idx].isActive = false
        saveToDisk()
    }

    /// Mark a subscription as active again.
    func markActive(id: String) {
        guard let idx = subscriptions.firstIndex(where: { $0.id == id }) else { return }
        subscriptions[idx].isActive = true
        saveToDisk()
    }

    /// Remove all subscription data.
    func clearAll() {
        subscriptions = []
        lastDetectionDate = nil
        saveToDisk()
    }

    // MARK: - Helpers

    private func mergeDetected(_ detected: [Subscription]) {
        for sub in detected {
            let normalizedNew = normalizeMerchant(sub.merchant)
            let alreadyTracked = subscriptions.contains {
                $0.id == sub.id || normalizeMerchant($0.merchant) == normalizedNew
            }
            if !alreadyTracked {
                subscriptions.append(sub)
            }
        }
        // Deduplicate by normalized merchant name
        var seen = Set<String>()
        subscriptions = subscriptions.filter { sub in
            let key = normalizeMerchant(sub.merchant)
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
    }

    // MARK: - Persistence

    private func saveToDisk() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(subscriptions) {
            UserDefaults.standard.set(data, forKey: storeKey)
        }
    }

    private func loadFromDisk() -> [Subscription] {
        guard let data = UserDefaults.standard.data(forKey: storeKey) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([Subscription].self, from: data)) ?? []
    }
}
