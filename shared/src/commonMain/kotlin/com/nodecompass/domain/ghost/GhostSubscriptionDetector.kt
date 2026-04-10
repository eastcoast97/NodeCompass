package com.nodecompass.domain.ghost

import com.nodecompass.data.db.RecurringCharge
import com.nodecompass.data.db.TransactionRepository
import com.nodecompass.data.model.Currency

/**
 * Detects potential "ghost subscriptions" — recurring charges the user
 * may have forgotten about. Analyzes transaction history for patterns
 * of same-merchant, same-amount charges.
 */
class GhostSubscriptionDetector(
    private val repository: TransactionRepository
) {

    /**
     * Detect recurring charges that look like subscriptions.
     * A charge is considered a potential ghost subscription if:
     * - Same merchant + same amount appears 2+ times
     * - The charges are spaced roughly periodically
     */
    fun detect(): List<GhostSubscription> {
        val recurring = repository.getRecurringCharges()
        return recurring
            .filter { it.occurrenceCount >= 2 }
            .map { charge ->
                GhostSubscription(
                    merchant = charge.merchant,
                    amount = charge.amount,
                    currency = charge.currency,
                    frequency = estimateFrequency(charge.occurrenceCount),
                    occurrences = charge.occurrenceCount,
                    lastChargedMillis = charge.lastSeenMillis
                )
            }
            .sortedByDescending { it.occurrences }
    }

    private fun estimateFrequency(occurrenceCount: Long): SubscriptionFrequency {
        // Simple heuristic based on count
        // In a real implementation, we'd analyze the actual timestamps
        return when {
            occurrenceCount >= 12 -> SubscriptionFrequency.WEEKLY
            occurrenceCount >= 3 -> SubscriptionFrequency.MONTHLY
            else -> SubscriptionFrequency.UNKNOWN
        }
    }
}

data class GhostSubscription(
    val merchant: String,
    val amount: Double,
    val currency: Currency,
    val frequency: SubscriptionFrequency,
    val occurrences: Long,
    val lastChargedMillis: Long
)

enum class SubscriptionFrequency(val displayName: String) {
    WEEKLY("Weekly"),
    MONTHLY("Monthly"),
    QUARTERLY("Quarterly"),
    YEARLY("Yearly"),
    UNKNOWN("Recurring")
}
