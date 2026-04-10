import Foundation

/// Detects anomalous transactions using Z-score against a rolling 30-day baseline.
/// Flags unusual amounts, times, or merchants.
struct AnomalyDetector {

    /// Analyze recent transactions for anomalies.
    static func analyze(events: [LifeEvent]) -> [Insight] {
        let cal = Calendar.current
        let now = Date()
        guard let thirtyDaysAgo = cal.date(byAdding: .day, value: -30, to: now),
              let threeDaysAgo = cal.date(byAdding: .day, value: -3, to: now) else { return [] }

        // Baseline: debit transactions from 30 days ago
        let baseline = events.compactMap { event -> TransactionEvent? in
            guard event.timestamp >= thirtyDaysAgo && event.timestamp < threeDaysAgo else { return nil }
            if case .transaction(let t) = event.payload, !t.isCredit { return t }
            return nil
        }
        guard baseline.count >= 5 else { return [] } // Need enough data

        // Stats for amount
        let amounts = baseline.map { $0.amount }
        let mean = amounts.reduce(0, +) / Double(amounts.count)
        let variance = amounts.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(amounts.count)
        let stdDev = sqrt(variance)
        guard stdDev > 0 else { return [] }

        // Check recent transactions (last 3 days)
        let recent = events.compactMap { event -> (event: LifeEvent, txn: TransactionEvent)? in
            guard event.timestamp >= threeDaysAgo else { return nil }
            if case .transaction(let t) = event.payload, !t.isCredit { return (event, t) }
            return nil
        }

        var insights: [Insight] = []

        for item in recent {
            let zScore = (item.txn.amount - mean) / stdDev

            // Flag if amount is 2+ standard deviations above mean
            if zScore >= 2.0 {
                let multiplier = item.txn.amount / mean
                let priority: InsightPriority = zScore >= 3.0 ? .urgent : .high

                insights.append(Insight(
                    type: .anomaly,
                    title: "Unusual charge: \(formatAmount(item.txn.amount)) at \(item.txn.merchant)",
                    body: "This is \(String(format: "%.1f", multiplier))x your typical purchase amount of \(formatAmount(mean)).",
                    priority: priority,
                    category: item.txn.category,
                    relatedEventIds: [item.event.id],
                    expiresAt: cal.date(byAdding: .day, value: 7, to: Date())
                ))
            }
        }

        // Also detect unusual merchant (first-time merchant with high amount)
        let knownMerchants = Set(baseline.map { $0.merchant.lowercased() })
        for item in recent {
            if !knownMerchants.contains(item.txn.merchant.lowercased()) && item.txn.amount > mean * 1.5 {
                // Don't duplicate if already flagged as amount anomaly
                if !insights.contains(where: { $0.relatedEventIds.contains(item.event.id) }) {
                    insights.append(Insight(
                        type: .anomaly,
                        title: "New merchant: \(item.txn.merchant)",
                        body: "First purchase at \(item.txn.merchant) for \(formatAmount(item.txn.amount)).",
                        priority: .medium,
                        category: item.txn.category,
                        relatedEventIds: [item.event.id],
                        expiresAt: cal.date(byAdding: .day, value: 5, to: Date())
                    ))
                }
            }
        }

        return insights
    }

    private static func formatAmount(_ amount: Double) -> String {
        String(format: "$%.2f", amount)
    }
}
