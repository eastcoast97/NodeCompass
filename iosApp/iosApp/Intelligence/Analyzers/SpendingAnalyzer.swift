import Foundation

/// Analyzes transaction events to produce spending insights.
/// Runs against the EventStore and produces Insight objects for the PatternEngine.
struct SpendingAnalyzer {

    /// Analyze recent transactions and return any notable insights.
    ///
    /// - Parameter cancelledSubscriptionKeys: set of `"<merchant-lower>|<amount 2dp>"`
    ///   strings that the user has marked as cancelled or flagged as
    ///   not-a-subscription — these are suppressed from ghost-subscription alerts.
    ///   PatternEngine fetches this once from `CancelledSubscriptionsStore` and
    ///   passes it in so `analyze` stays synchronous.
    static func analyze(
        events: [LifeEvent],
        profile: UserProfile,
        cancelledSubscriptionKeys: Set<String> = []
    ) -> [Insight] {
        let txnEvents = events.compactMap { event -> TransactionEvent? in
            if case .transaction(let t) = event.payload, !t.isCredit { return t }
            return nil
        }
        guard !txnEvents.isEmpty else { return [] }

        var insights: [Insight] = []

        // 1. Week-over-week spending trend
        if let trend = weekOverWeekTrend(events: events) {
            insights.append(trend)
        }

        // 2. Category spike detection
        insights.append(contentsOf: categorySpikeInsights(events: events))

        // 3. Top merchant this month
        if let topMerchant = topMerchantInsight(txnEvents: txnEvents) {
            insights.append(topMerchant)
        }

        // 4. Ghost subscriptions (filtered by user's cancellations)
        insights.append(contentsOf: ghostSubscriptionInsights(
            txnEvents: txnEvents,
            events: events,
            cancelledKeys: cancelledSubscriptionKeys
        ))

        return insights
    }

    /// Compute the match key for a (merchant, amount) pair — shared with
    /// `CancelledSubscriptionsStore` so filtering is consistent.
    static func subscriptionMatchKey(merchant: String, amount: Double) -> String {
        let m = merchant.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let a = (amount * 100).rounded() / 100
        return "\(m)|\(String(format: "%.2f", a))"
    }

    // MARK: - Week-over-Week Trend

    private static func weekOverWeekTrend(events: [LifeEvent]) -> Insight? {
        let cal = Calendar.current
        let now = Date()
        guard let thisWeekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)),
              let lastWeekStart = cal.date(byAdding: .weekOfYear, value: -1, to: thisWeekStart) else { return nil }

        let thisWeekSpend = spendTotal(events: events, from: thisWeekStart, to: now)
        let lastWeekSpend = spendTotal(events: events, from: lastWeekStart, to: thisWeekStart)

        guard lastWeekSpend > 0 else { return nil }

        let change = (thisWeekSpend - lastWeekSpend) / lastWeekSpend
        let pct = Int(abs(change) * 100)

        // Only surface if meaningful change (>20%)
        guard pct >= 20 else { return nil }

        if change > 0 {
            return Insight(
                type: .spendingTrend,
                title: "Spending up \(pct)% this week",
                body: "You've spent \(formatAmount(thisWeekSpend)) so far this week, compared to \(formatAmount(lastWeekSpend)) all of last week.",
                priority: pct >= 50 ? .high : .medium,
                category: "spending"
            )
        } else {
            return Insight(
                type: .milestone,
                title: "Spending down \(pct)% this week",
                body: "You've spent \(formatAmount(thisWeekSpend)) this week — \(pct)% less than last week's \(formatAmount(lastWeekSpend)).",
                priority: .medium,
                category: "spending"
            )
        }
    }

    // MARK: - Category Spike

    private static func categorySpikeInsights(events: [LifeEvent]) -> [Insight] {
        let cal = Calendar.current
        let now = Date()
        guard let thisWeekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)),
              let fourWeeksAgo = cal.date(byAdding: .weekOfYear, value: -4, to: thisWeekStart) else { return [] }

        // This week by category
        let thisWeek = debitEvents(events: events, from: thisWeekStart, to: now)
        let thisWeekByCategory = Dictionary(grouping: thisWeek, by: { $0.category })
            .mapValues { $0.reduce(0.0) { $0 + $1.amount } }

        // Past 4 weeks average by category
        let pastWeeks = debitEvents(events: events, from: fourWeeksAgo, to: thisWeekStart)
        let pastByCategory = Dictionary(grouping: pastWeeks, by: { $0.category })
            .mapValues { $0.reduce(0.0) { $0 + $1.amount } / 4.0 }

        var insights: [Insight] = []
        for (category, thisWeekAmount) in thisWeekByCategory {
            guard let avg = pastByCategory[category], avg > 10 else { continue }
            let ratio = thisWeekAmount / avg
            if ratio >= 2.0 {
                insights.append(Insight(
                    type: .categorySpike,
                    title: "\(category) spending is \(String(format: "%.0f", ratio))x average",
                    body: "You've spent \(formatAmount(thisWeekAmount)) on \(category) this week — your average is \(formatAmount(avg))/week.",
                    priority: ratio >= 3.0 ? .high : .medium,
                    category: category
                ))
            }
        }
        return insights
    }

    // MARK: - Top Merchant

    private static func topMerchantInsight(txnEvents: [TransactionEvent]) -> Insight? {
        let cal = Calendar.current
        let startOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: Date()))!
        let thisMonth = txnEvents.filter { _ in true } // Already filtered to debits
        guard thisMonth.count >= 3 else { return nil }

        let byMerchant = Dictionary(grouping: thisMonth, by: { $0.merchant.lowercased() })
        guard let top = byMerchant.max(by: { $0.value.count < $1.value.count }),
              top.value.count >= 3 else { return nil }

        let total = top.value.reduce(0.0) { $0 + $1.amount }
        let merchantName = top.value.first?.merchant ?? top.key

        return Insight(
            type: .spendingTrend,
            title: "\(merchantName) is your top spot",
            body: "You've visited \(merchantName) \(top.value.count) times this month, spending \(formatAmount(total)) total.",
            priority: .low,
            category: "spending"
        )
    }

    // MARK: - Ghost Subscriptions

    private static func ghostSubscriptionInsights(
        txnEvents: [TransactionEvent],
        events: [LifeEvent],
        cancelledKeys: Set<String>
    ) -> [Insight] {
        // Group by merchant + rounded amount
        var groups: [String: [TransactionEvent]] = [:]
        for txn in txnEvents {
            let key = "\(txn.merchant.lowercased())_\(Int(txn.amount * 100))"
            groups[key, default: []].append(txn)
        }

        return groups.compactMap { _, txns -> Insight? in
            guard txns.count >= 2 else { return nil }
            let merchant = txns.first!.merchant
            let amount = txns.first!.amount
            // Skip if user has marked this (merchant, amount) as cancelled or not-a-sub.
            let matchKey = subscriptionMatchKey(merchant: merchant, amount: amount)
            if cancelledKeys.contains(matchKey) { return nil }
            return Insight(
                type: .ghostSubscription,
                title: "Recurring: \(merchant)",
                body: "\(formatAmount(amount)) charged \(txns.count) times. Is this a subscription you still use?",
                priority: .low,
                category: "subscriptions"
            )
        }
    }

    // MARK: - Helpers

    private static func spendTotal(events: [LifeEvent], from start: Date, to end: Date) -> Double {
        debitEvents(events: events, from: start, to: end).reduce(0.0) { $0 + $1.amount }
    }

    private static func debitEvents(events: [LifeEvent], from start: Date, to end: Date) -> [TransactionEvent] {
        events.compactMap { event -> TransactionEvent? in
            guard event.timestamp >= start && event.timestamp <= end else { return nil }
            if case .transaction(let t) = event.payload, !t.isCredit { return t }
            return nil
        }
    }

    private static func formatAmount(_ amount: Double) -> String {
        "\(NC.currencySymbol)\(String(format: "%.0f", amount))"
    }
}
