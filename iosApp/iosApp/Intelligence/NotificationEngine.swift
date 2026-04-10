import Foundation
import UserNotifications

/// Smart notification delivery with anti-spam controls.
/// - Max 3 notifications per day
/// - Minimum 2-hour gap between notifications
/// - Per-type cooldowns (same insight type won't fire twice in 12h)
actor NotificationEngine {
    static let shared = NotificationEngine()

    private let maxPerDay = 3
    private let minimumGapSeconds: TimeInterval = 7200     // 2 hours
    private let perTypeCooldownSeconds: TimeInterval = 43200 // 12 hours

    private var deliveryLog: [DeliveryRecord] = []
    private let logKey = "notification_delivery_log"

    private init() {
        loadLog()
    }

    // MARK: - Public API

    /// Request notification permission (call once on first insight).
    func requestPermissionIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
    }

    /// Schedule a notification for an insight, respecting anti-spam rules.
    func scheduleIfAllowed(_ insight: Insight) async {
        await requestPermissionIfNeeded()

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        pruneOldRecords()

        // Check daily limit
        let todayRecords = deliveryLog.filter { Calendar.current.isDateInToday($0.date) }
        if todayRecords.count >= maxPerDay && insight.priority != .urgent {
            return
        }

        // Check minimum gap
        if let lastDelivery = deliveryLog.last {
            let gap = Date().timeIntervalSince(lastDelivery.date)
            if gap < minimumGapSeconds && insight.priority != .urgent {
                return
            }
        }

        // Check per-type cooldown
        let recentSameType = deliveryLog.filter {
            $0.type == insight.type.rawValue &&
            Date().timeIntervalSince($0.date) < perTypeCooldownSeconds
        }
        if !recentSameType.isEmpty && insight.priority != .urgent {
            return
        }

        // All checks passed — deliver
        let content = UNMutableNotificationContent()
        content.title = insight.title
        content.body = insight.body
        content.sound = insight.priority == .urgent ? .defaultCritical : .default
        content.categoryIdentifier = insight.type.rawValue

        let request = UNNotificationRequest(
            identifier: insight.id,
            content: content,
            trigger: nil // Deliver immediately
        )

        do {
            try await center.add(request)
            deliveryLog.append(DeliveryRecord(
                date: Date(),
                insightId: insight.id,
                type: insight.type.rawValue,
                priority: insight.priority.rawValue
            ))
            saveLog()
        } catch {
            print("[NotificationEngine] Failed to deliver: \(error)")
        }
    }

    // MARK: - Persistence

    private struct DeliveryRecord: Codable {
        let date: Date
        let insightId: String
        let type: String
        let priority: Int
    }

    private func saveLog() {
        if let data = try? JSONEncoder().encode(deliveryLog) {
            UserDefaults.standard.set(data, forKey: logKey)
        }
    }

    private func loadLog() {
        guard let data = UserDefaults.standard.data(forKey: logKey),
              let log = try? JSONDecoder().decode([DeliveryRecord].self, from: data) else { return }
        deliveryLog = log
    }

    private func pruneOldRecords() {
        // Keep last 7 days of records
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        deliveryLog.removeAll { $0.date < cutoff }
    }
}
