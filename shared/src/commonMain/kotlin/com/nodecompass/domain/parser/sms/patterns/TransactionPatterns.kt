package com.nodecompass.domain.parser.sms.patterns

import com.nodecompass.data.model.TransactionType
import kotlinx.datetime.LocalDate
import kotlinx.datetime.TimeZone
import kotlinx.datetime.atStartOfDayIn

/**
 * Universal patterns for extracting transaction details from bank SMS messages globally.
 */
object TransactionPatterns {

    private val debitKeywords = listOf(
        "debited", "debit", "spent", "withdrawn", "purchase",
        "payment", "charged", "sent", "paid", "deducted",
        "used at", "txn at", "transaction at", "buy"
    )

    private val creditKeywords = listOf(
        "credited", "credit", "received", "deposited", "refund",
        "cashback", "reversal", "added", "transferred to your"
    )

    private val accountPattern = Regex("""(?i)(?:a/c|acct?|account|ac)\s*(?:no\.?\s*)?(?:ending\s*)?[Xx*]*(\d{4})""")
    private val accountStarPattern = Regex("""[Xx*]{2,}(\d{4})""")
    private val accountEndingPattern = Regex("""(?i)(?:ending|ends?\s+in|last\s+4)\s*(\d{4})""")

    private val merchantPatterns = listOf(
        // "to VPA merchant@upi" or "to merchant"
        Regex("""(?i)(?:to|at|for)\s+(?:VPA\s+)?([A-Za-z0-9][\w\s.&'-]{1,40})"""),
        // "at MERCHANT_NAME" followed by "on" or end of sentence
        Regex("""(?i)at\s+([A-Za-z][\w\s.&'-]{1,40})(?=\s+on|\s*\.|$)"""),
        // UPI: "to payee@bank"
        Regex("""(?i)to\s+([\w.]+@[\w]+)"""),
    )

    // Multiple date formats used globally
    private val datePatterns = listOf(
        // DD-MM-YY or DD-MM-YYYY
        Regex("""(\d{2})-(\d{2})-(\d{2,4})"""),
        // DD/MM/YY or DD/MM/YYYY
        Regex("""(\d{2})/(\d{2})/(\d{2,4})"""),
        // DD-Mon-YY or DD-Mon-YYYY (e.g., 07-Apr-26)
        Regex("""(\d{1,2})-([A-Za-z]{3})-(\d{2,4})"""),
        // Mon DD, YYYY (e.g., Apr 07, 2026)
        Regex("""([A-Za-z]{3})\s+(\d{1,2}),?\s+(\d{4})"""),
    )

    private val referencePatterns = listOf(
        Regex("""(?i)(?:ref|reference|txn|transaction)\s*(?:no\.?|number|id|#)?\s*:?\s*(\w{6,20})"""),
        Regex("""(?i)(?:UPI|IMPS|NEFT|RTGS)\s+(?:Ref\s*(?:No\.?)?\s*:?\s*)?(\d{6,20})"""),
    )

    fun detectTransactionType(text: String): TransactionType? {
        val lower = text.lowercase()

        val hasDebit = debitKeywords.any { lower.contains(it) }
        val hasCredit = creditKeywords.any { lower.contains(it) }

        return when {
            hasDebit && !hasCredit -> TransactionType.DEBIT
            hasCredit && !hasDebit -> TransactionType.CREDIT
            // If both keywords appear, look at which comes first
            hasDebit && hasCredit -> {
                val firstDebit = debitKeywords.mapNotNull { kw ->
                    val idx = lower.indexOf(kw)
                    if (idx >= 0) idx else null
                }.minOrNull() ?: Int.MAX_VALUE

                val firstCredit = creditKeywords.mapNotNull { kw ->
                    val idx = lower.indexOf(kw)
                    if (idx >= 0) idx else null
                }.minOrNull() ?: Int.MAX_VALUE

                if (firstDebit < firstCredit) TransactionType.DEBIT else TransactionType.CREDIT
            }
            else -> null
        }
    }

    fun extractMerchant(text: String): String? {
        for (pattern in merchantPatterns) {
            val match = pattern.find(text)
            if (match != null) {
                val merchant = match.groupValues[1].trim()
                // Clean up: remove trailing "on", "Ref", etc.
                val cleaned = merchant
                    .replace(Regex("""(?i)\s+(?:on|ref|upi|imps|neft).*$"""), "")
                    .trim()
                if (cleaned.length >= 2) return cleaned
            }
        }
        return null
    }

    fun extractAccount(text: String): String? {
        accountPattern.find(text)?.let { return it.groupValues[1] }
        accountEndingPattern.find(text)?.let { return it.groupValues[1] }
        accountStarPattern.find(text)?.let { return it.groupValues[1] }
        return null
    }

    fun extractDate(text: String): Long? {
        for (pattern in datePatterns) {
            val match = pattern.find(text) ?: continue
            return try {
                parseDateMatch(match, pattern)
            } catch (_: Exception) {
                null
            }
        }
        return null
    }

    fun extractReference(text: String): String? {
        for (pattern in referencePatterns) {
            val match = pattern.find(text)
            if (match != null) return match.groupValues[1]
        }
        return null
    }

    private val monthNames = mapOf(
        "jan" to 1, "feb" to 2, "mar" to 3, "apr" to 4,
        "may" to 5, "jun" to 6, "jul" to 7, "aug" to 8,
        "sep" to 9, "oct" to 10, "nov" to 11, "dec" to 12
    )

    private fun parseDateMatch(match: MatchResult, pattern: Regex): Long? {
        val groups = match.groupValues

        val (day, month, year) = when {
            // DD-Mon-YY format
            groups[2].length == 3 && groups[2][0].isLetter() -> {
                val m = monthNames[groups[2].lowercase()] ?: return null
                Triple(groups[1].toInt(), m, normalizeYear(groups[3].toInt()))
            }
            // Mon DD, YYYY format
            groups[1].length == 3 && groups[1][0].isLetter() -> {
                val m = monthNames[groups[1].lowercase()] ?: return null
                Triple(groups[2].toInt(), m, normalizeYear(groups[3].toInt()))
            }
            // DD-MM-YY or DD/MM/YY format
            else -> {
                Triple(groups[1].toInt(), groups[2].toInt(), normalizeYear(groups[3].toInt()))
            }
        }

        if (month !in 1..12 || day !in 1..31 || year < 2000) return null

        // Convert to epoch millis (UTC midnight)
        // Simple calculation: days since epoch
        return try {
            val localDate = LocalDate(year, month, day)
            localDate.atStartOfDayIn(TimeZone.UTC).toEpochMilliseconds()
        } catch (_: Exception) {
            null
        }
    }

    private fun normalizeYear(year: Int): Int {
        return when {
            year in 0..99 -> 2000 + year
            else -> year
        }
    }
}
