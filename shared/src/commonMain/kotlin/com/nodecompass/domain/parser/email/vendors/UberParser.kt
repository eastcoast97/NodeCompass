package com.nodecompass.domain.parser.email.vendors

import com.nodecompass.data.model.TransactionSource
import com.nodecompass.data.model.TransactionType
import com.nodecompass.domain.parser.ParserResult
import com.nodecompass.domain.parser.email.VendorParser
import com.nodecompass.domain.parser.sms.patterns.CurrencyPatterns

class UberParser : VendorParser {
    override val vendorName = "Uber"
    override val senderPatterns = listOf(
        "uber.com",
        "ubereats.com",
    )

    private val totalPatterns = listOf(
        // Match "Total:" but NOT "Subtotal:" — use negative lookbehind
        Regex("""(?i)(?<!sub)total\s*:?\s*([₹$£€¥A-Z]{1,3}\.?\s*[\d,]+\.?\d*)"""),
        Regex("""(?i)(?:you\s+paid|amount\s+charged|trip\s+fare)\s*:?\s*([₹$£€¥A-Z]{1,3}\.?\s*[\d,]+\.?\d*)"""),
        Regex("""(?i)(?<!sub)total\s*:?\s*([₹$£€¥])\s*([\d,]+\.?\d*)"""),
    )

    override fun canHandle(senderEmail: String, subject: String): Boolean {
        val sender = senderEmail.lowercase()
        val sub = subject.lowercase()
        return senderPatterns.any { sender.contains(it) } ||
                (sub.contains("uber") && (sub.contains("receipt") || sub.contains("trip")))
    }

    override fun parse(subject: String, plainBody: String, senderEmail: String): ParserResult? {
        val fullText = "$subject\n$plainBody"

        // Determine if it's Uber Eats or Uber Rides
        val isUberEats = fullText.lowercase().let {
            it.contains("uber eats") || it.contains("ubereats") || it.contains("delivery")
        }
        val merchant = if (isUberEats) "Uber Eats" else "Uber"

        for (pattern in totalPatterns) {
            val match = pattern.find(fullText)
            if (match != null) {
                val currencyAmount = CurrencyPatterns.extractCurrencyAndAmount(match.value)
                if (currencyAmount != null) {
                    return ParserResult(
                        amount = currencyAmount.second,
                        currency = currencyAmount.first,
                        type = TransactionType.DEBIT,
                        merchant = merchant,
                        source = TransactionSource.EMAIL
                    )
                }
            }
        }

        // Fallback
        val currencyAmount = CurrencyPatterns.extractCurrencyAndAmount(fullText)
        if (currencyAmount != null) {
            return ParserResult(
                amount = currencyAmount.second,
                currency = currencyAmount.first,
                type = TransactionType.DEBIT,
                merchant = merchant,
                source = TransactionSource.EMAIL
            )
        }

        return null
    }
}
