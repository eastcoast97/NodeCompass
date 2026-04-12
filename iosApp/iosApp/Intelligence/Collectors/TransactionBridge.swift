import Foundation

/// Bridges StoredTransaction objects into LifeEvents.
/// Called after every transaction is added to TransactionStore.
/// Also handles one-time migration of existing transactions on first launch.
struct TransactionBridge {

    /// Convert a single StoredTransaction into a LifeEvent and append to EventStore.
    /// Awaits the EventStore append to prevent race conditions when bridging
    /// multiple transactions in rapid succession.
    static func bridge(_ txn: StoredTransaction) async {
        let event = LifeEvent(
            timestamp: txn.date,
            source: txn.source == "BANK" ? .bank : .email,
            payload: .transaction(TransactionEvent(
                transactionId: txn.id,
                amount: txn.amount,
                merchant: txn.merchant,
                category: txn.category,
                isCredit: txn.isCredit
            ))
        )

        await EventStore.shared.append(event)
    }

    /// Fire-and-forget version for callers that don't need to await.
    /// Use `bridge(_:) async` when ordering matters.
    static func bridgeInBackground(_ txn: StoredTransaction) {
        Task {
            await bridge(txn)
        }
    }

    /// One-time migration: bridge all existing transactions into events.
    /// Called on app launch if EventStore has no transaction events yet.
    static func migrateExistingTransactions(from transactions: [StoredTransaction]) async {
        let events = transactions.map { txn in
            LifeEvent(
                timestamp: txn.date,
                source: txn.source == "BANK" ? .bank : .email,
                payload: .transaction(TransactionEvent(
                    transactionId: txn.id,
                    amount: txn.amount,
                    merchant: txn.merchant,
                    category: txn.category,
                    isCredit: txn.isCredit
                ))
            )
        }

        await EventStore.shared.appendBatch(events)
        let count = await EventStore.shared.totalCount
        print("[TransactionBridge] Migrated \(events.count) transactions → \(count) total events")
    }
}
