import Foundation

/// Bridges StoredTransaction objects into LifeEvents.
/// Called after every transaction is added to TransactionStore.
/// Also handles one-time migration of existing transactions on first launch.
struct TransactionBridge {

    /// Convert a single StoredTransaction into a LifeEvent and append to EventStore.
    static func bridge(_ txn: StoredTransaction) {
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

        Task {
            await EventStore.shared.append(event)
        }
    }

    /// One-time migration: bridge all existing transactions into events.
    /// Called on app launch if EventStore has no transaction events yet.
    static func migrateExistingTransactions(from transactions: [StoredTransaction]) {
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

        Task {
            await EventStore.shared.appendBatch(events)
            let count = await EventStore.shared.totalCount
            print("[TransactionBridge] Migrated \(events.count) transactions → \(count) total events")
        }
    }
}
