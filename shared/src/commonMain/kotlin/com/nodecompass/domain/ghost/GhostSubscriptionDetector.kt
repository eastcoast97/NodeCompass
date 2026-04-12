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
                    frequency = estimateFrequency(charge),
                    occurrences = charge.occurrenceCount,
                    lastChargedMillis = charge.lastSeenMillis
                )
            }
            .sortedByDescending { it.occurrences }
    }

    /**
     * Estimate frequency by analyzing the actual time interval between
     * first and last charge (replaces the old count-based heuristic that
     * incorrectly claimed 12+ occurrences = WEEKLY even when they spanned
     * a full year).
     */
    private fun estimateFrequency(charge: RecurringCharge): SubscriptionFrequency {
        if (charge.occurrenceCount < 2 ||
            charge.firstSeenMillis <= 0 ||
            charge.lastSeenMillis <= 0) {
            return SubscriptionFrequency.UNKNOWN
        }

        val spanMillis = charge.lastSeenMillis - charge.firstSeenMillis
        if (spanMillis <= 0) return SubscriptionFrequency.UNKNOWN

        val avgIntervalDays = (spanMillis / (charge.occurrenceCount - 1)) / (1000.0 * 60 * 60 * 24)

        return when {
            avgIntervalDays < 10 -> SubscriptionFrequency.WEEKLY
            avgIntervalDays < 45 -> SubscriptionFrequency.MONTHLY
            avgIntervalDays < 120 -> SubscriptionFrequency.QUARTERLY
            avgIntervalDays < 400 -> SubscriptionFrequency.YEARLY
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
