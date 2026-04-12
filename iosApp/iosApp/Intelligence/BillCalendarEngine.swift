import Foundation

/// Auto-detects recurring bills from transaction history by analyzing
/// merchant frequency, amount consistency, and date patterns.
actor BillCalendarEngine {
    static let shared = BillCalendarEngine()

    private let storeKey = "hidden_bills"
    private var hiddenBillIDs: Set<String> = []

    // MARK: - Models

    struct RecurringBill: Codable, Identifiable {
        let id: String
        let merchant: String
        let estimatedAmount: Double
        let category: String
        let typicalDayOfMonth: Int   // 1-31
        let frequency: BillFrequency // .monthly, .weekly, .quarterly, .yearly
        let lastPaidDate: Date?
        let nextDueDate: Date?
        let confidence: Double       // 0-1 how confident we are this is recurring
        var isHidden: Bool           // user can dismiss
    }

    enum BillFrequency: String, Codable {
        case weekly, biweekly, monthly, quarterly, yearly
    }

    // MARK: - Init

    private init() {
        loadHiddenIDs()
    }

    // MARK: - Detection

    /// Analyze all transactions and detect recurring bill patterns.
    func detectBills() async -> [RecurringBill] {
        let transactions = await MainActor.run {
            TransactionStore.shared.transactions
        }

        // Only look at debits
        let debits = transactions.filter { $0.type.uppercased() == "DEBIT" }

        // Group by merchant (lowercased)
        var byMerchant: [String: [StoredTransaction]] = [:]
        for txn in debits {
            let key = txn.merchant.lowercased().trimmingCharacters(in: .whitespaces)
            byMerchant[key, default: []].append(txn)
        }

        var bills: [RecurringBill] = []

        for (_, txns) in byMerchant {
            guard txns.count >= 2 else { continue }

            // Sort by date ascending
            let sorted = txns.sorted { $0.date < $1.date }

            // Check amount consistency: are amounts within 10% of median?
            let amounts = sorted.map(\.amount)
            let median = amounts.sorted()[amounts.count / 2]
            let consistentAmounts = amounts.filter { abs($0 - median) / max(median, 1) <= 0.10 }
            let amountConsistency = Double(consistentAmounts.count) / Double(amounts.count)

            guard amountConsistency >= 0.6 else { continue }

            // Detect frequency from intervals between charges
            let calendar = Calendar.current
            var intervals: [Int] = [] // in days
            for i in 1..<sorted.count {
                let days = calendar.dateComponents([.day], from: sorted[i-1].date, to: sorted[i].date).day ?? 0
                intervals.append(abs(days))
            }

            guard !intervals.isEmpty else { continue }
            let avgInterval = intervals.reduce(0, +) / intervals.count

            let frequency: BillFrequency
            let intervalConsistency: Double

            if avgInterval <= 10 {
                // Too frequent to be a bill (likely regular purchases)
                continue
            } else if avgInterval <= 21 {
                frequency = .biweekly
                let deviations = intervals.map { abs($0 - 14) }
                intervalConsistency = 1.0 - (Double(deviations.reduce(0, +)) / Double(deviations.count) / 14.0)
            } else if avgInterval <= 45 {
                frequency = .monthly
                let deviations = intervals.map { abs($0 - 30) }
                intervalConsistency = 1.0 - (Double(deviations.reduce(0, +)) / Double(deviations.count) / 30.0)
            } else if avgInterval <= 120 {
                frequency = .quarterly
                let deviations = intervals.map { abs($0 - 90) }
                intervalConsistency = 1.0 - (Double(deviations.reduce(0, +)) / Double(deviations.count) / 90.0)
            } else if avgInterval <= 400 {
                frequency = .yearly
                let deviations = intervals.map { abs($0 - 365) }
                intervalConsistency = 1.0 - (Double(deviations.reduce(0, +)) / Double(deviations.count) / 365.0)
            } else {
                continue
            }

            guard intervalConsistency > 0.3 else { continue }

            // Calculate typical day of month
            let daysOfMonth = sorted.map { calendar.component(.day, from: $0.date) }
            let typicalDay = daysOfMonth.reduce(0, +) / daysOfMonth.count

            // Calculate next due date
            let lastDate = sorted.last!.date
            let nextDue = calculateNextDueDate(from: lastDate, frequency: frequency, typicalDay: typicalDay)

            // Confidence = average of amount consistency + interval consistency
            let confidence = min(1.0, max(0, (amountConsistency + max(0, intervalConsistency)) / 2.0))

            let merchantName = sorted.last!.merchant // Use most recent name
            let billID = "bill_\(merchantName.lowercased().replacingOccurrences(of: " ", with: "_"))"

            let bill = RecurringBill(
                id: billID,
                merchant: merchantName,
                estimatedAmount: median,
                category: sorted.last!.category,
                typicalDayOfMonth: typicalDay,
                frequency: frequency,
                lastPaidDate: sorted.last?.date,
                nextDueDate: nextDue,
                confidence: confidence,
                isHidden: hiddenBillIDs.contains(billID)
            )

            bills.append(bill)
        }

        return bills
            .filter { !$0.isHidden && $0.confidence >= 0.4 }
            .sorted { ($0.nextDueDate ?? .distantFuture) < ($1.nextDueDate ?? .distantFuture) }
    }

    /// Bills due in the next N days.
    func upcomingBills(days: Int = 7) async -> [RecurringBill] {
        let all = await detectBills()
        let cutoff = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
        let now = Date()
        return all.filter { bill in
            guard let due = bill.nextDueDate else { return false }
            return due >= now && due <= cutoff
        }
    }

    /// Total amount of bills due this month.
    func totalDueThisMonth() async -> Double {
        let all = await detectBills()
        let calendar = Calendar.current
        let now = Date()
        return all
            .filter { bill in
                guard let due = bill.nextDueDate else { return false }
                return calendar.isDate(due, equalTo: now, toGranularity: .month)
            }
            .reduce(0) { $0 + $1.estimatedAmount }
    }

    /// Hide a bill (user dismissed it).
    func hideBill(id: String) {
        hiddenBillIDs.insert(id)
        saveHiddenIDs()
    }

    func clearAll() {
        hiddenBillIDs = []
        saveHiddenIDs()
    }

    // MARK: - Helpers

    private func calculateNextDueDate(from lastDate: Date, frequency: BillFrequency, typicalDay: Int) -> Date? {
        let calendar = Calendar.current
        var components = DateComponents()

        switch frequency {
        case .weekly:
            components.day = 7
        case .biweekly:
            components.day = 14
        case .monthly:
            components.month = 1
        case .quarterly:
            components.month = 3
        case .yearly:
            components.year = 1
        }

        guard var nextDate = calendar.date(byAdding: components, to: lastDate) else { return nil }

        // For monthly/quarterly/yearly, snap to typical day
        if frequency == .monthly || frequency == .quarterly || frequency == .yearly {
            var comps = calendar.dateComponents([.year, .month], from: nextDate)
            let range = calendar.range(of: .day, in: .month, for: nextDate)
            comps.day = min(typicalDay, range?.count ?? 28)
            if let snapped = calendar.date(from: comps) {
                nextDate = snapped
            }
        }

        // If the calculated date is in the past, advance one more cycle
        if nextDate < Date() {
            if let advanced = calendar.date(byAdding: components, to: nextDate) {
                return advanced
            }
        }

        return nextDate
    }

    // MARK: - Persistence (hidden bill IDs only)

    private func saveHiddenIDs() {
        let array = Array(hiddenBillIDs)
        UserDefaults.standard.set(array, forKey: storeKey)
    }

    private func loadHiddenIDs() {
        if let array = UserDefaults.standard.stringArray(forKey: storeKey) {
            hiddenBillIDs = Set(array)
        }
    }
}
