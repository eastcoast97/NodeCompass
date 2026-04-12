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
    func detectSubscriptions() async -> [Subscription] {
        let transactions = await MainActor.run {
            TransactionStore.shared.transactions
        }

        // Only debits
        let debits = transactions.filter { $0.type.uppercased() == "DEBIT" }

        // Group by merchant (normalized)
        var byMerchant: [String: [StoredTransaction]] = [:]
        for txn in debits {
            let key = txn.merchant.lowercased().trimmingCharacters(in: .whitespaces)
            byMerchant[key, default: []].append(txn)
        }

        var detected: [Subscription] = []
        let cal = Calendar.current

        for (_, txns) in byMerchant {
            // Need at least 2 charges to detect a pattern
            guard txns.count >= 2 else { continue }

            let sorted = txns.sorted { $0.date < $1.date }

            // Check amount consistency: amounts within 20% of median
            let amounts = sorted.map(\.amount)
            let sortedAmounts = amounts.sorted()
            let median = sortedAmounts[sortedAmounts.count / 2]
            let consistent = amounts.allSatisfy { abs($0 - median) / max(median, 1) < 0.2 }
            guard consistent else { continue }

            // Determine frequency from intervals between charges
            var intervals: [Int] = []
            for i in 1..<sorted.count {
                let days = cal.dateComponents([.day], from: sorted[i - 1].date, to: sorted[i].date).day ?? 0
                intervals.append(days)
            }

            guard !intervals.isEmpty else { continue }
            let avgInterval = intervals.reduce(0, +) / intervals.count

            let frequency: BillingFrequency
            if avgInterval <= 10 {
                frequency = .weekly
            } else if avgInterval <= 45 {
                frequency = .monthly
            } else if avgInterval <= 120 {
                frequency = .quarterly
            } else {
                frequency = .yearly
            }

            // Calculate next charge date
            let lastDate = sorted.last!.date
            let nextDate: Date?
            switch frequency {
            case .weekly:
                nextDate = cal.date(byAdding: .day, value: 7, to: lastDate)
            case .monthly:
                nextDate = cal.date(byAdding: .month, value: 1, to: lastDate)
            case .quarterly:
                nextDate = cal.date(byAdding: .month, value: 3, to: lastDate)
            case .yearly:
                nextDate = cal.date(byAdding: .year, value: 1, to: lastDate)
            }

            // Check if we already track this merchant
            let merchantName = sorted.first!.merchant
            if let idx = subscriptions.firstIndex(where: { $0.merchant.lowercased() == merchantName.lowercased() }) {
                // Update existing subscription with latest data
                subscriptions[idx].amount = median
                subscriptions[idx].lastChargeDate = lastDate
                subscriptions[idx].nextChargeDate = nextDate
                subscriptions[idx].frequency = frequency
                detected.append(subscriptions[idx])
            } else {
                let sub = Subscription(
                    id: UUID().uuidString,
                    merchant: merchantName,
                    amount: median,
                    frequency: frequency,
                    category: sorted.first?.category ?? "Subscriptions",
                    lastChargeDate: lastDate,
                    nextChargeDate: nextDate,
                    isActive: true,
                    cancelReminder: nil,
                    notes: nil
                )
                detected.append(sub)
            }
        }

        // Merge new detections with existing user-modified subs
        mergeDetected(detected)
        saveToDisk()

        return subscriptions.filter(\.isActive)
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
            let alreadyTracked = subscriptions.contains {
                $0.id == sub.id || $0.merchant.lowercased() == sub.merchant.lowercased()
            }
            if !alreadyTracked {
                subscriptions.append(sub)
            }
        }
        // Deduplicate by merchant name
        var seen = Set<String>()
        subscriptions = subscriptions.filter { sub in
            let key = sub.merchant.lowercased()
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
