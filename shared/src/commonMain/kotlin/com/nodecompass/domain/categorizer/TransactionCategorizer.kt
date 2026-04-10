package com.nodecompass.domain.categorizer

import com.nodecompass.data.model.Category

/**
 * Rule-based transaction categorizer using merchant keyword matching.
 * Works globally across merchants and services.
 */
class TransactionCategorizer {

    /**
     * Categorize a transaction based on merchant name.
     * Returns the best matching category, or OTHER if no match found.
     */
    fun categorize(merchant: String): Category {
        val normalized = merchant.lowercase().trim()
        if (normalized.isEmpty()) return Category.OTHER

        for ((category, keywords) in merchantKeywords) {
            if (keywords.any { keyword -> normalized.contains(keyword) }) {
                return category
            }
        }

        return Category.OTHER
    }
}
