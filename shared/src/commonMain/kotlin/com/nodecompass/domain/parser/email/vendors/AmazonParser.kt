package com.nodecompass.domain.parser.email.vendors

import com.nodecompass.data.model.Currency
import com.nodecompass.data.model.TransactionSource
import com.nodecompass.data.model.TransactionType
import com.nodecompass.domain.parser.ParserResult
import com.nodecompass.domain.parser.email.VendorParser
import com.nodecompass.domain.parser.sms.patterns.CurrencyPatterns

class AmazonParser : VendorParser {
    override val vendorName = "Amazon"
    override val senderPatterns = listOf(
        "auto-confirm@amazon",
        "order-update@amazon",
        "shipment-tracking@amazon",
        "digital-no-reply@amazon",
        "payments-messages@amazon",
    )

    // Patterns for Amazon order totals
    private val orderTotalPatterns = listOf(
        Regex("""(?i)(?:order\s+total|grand\s+total|total\s+for\s+this\s+order)\s*:?\s*([₹$£€¥])\s*([\d,]+\.?\d*)"""),
        Regex("""(?i)(?:order\s+total|grand\s+total|total)\s*:?\s*(?:Rs\.?|INR|USD|GBP|EUR)\s*([\d,]+\.?\d*)"""),
        Regex("""(?i)(?:charged|amount)\s*:?\s*([₹$£€¥])\s*([\d,]+\.?\d*)"""),
    )

    override fun parse(subject: String, plainBody: String, senderEmail: String): ParserResult? {
        val fullText = "$subject\n$plainBody"

        // Try to extract the order total
        for (pattern in orderTotalPatterns) {
            val match = pattern.find(fullText)
            if (match != null) {
                val currencyAmount = CurrencyPatterns.extractCurrencyAndAmount(match.value)
                if (currencyAmount != null) {
                    return ParserResult(
                        amount = currencyAmount.second,
                        currency = currencyAmount.first,
                        type = TransactionType.DEBIT,
                        merchant = "Amazon",
                        source = TransactionSource.EMAIL
                    )
                }
            }
        }

        // Fallback: try CurrencyPatterns on the full text
        val currencyAmount = CurrencyPatterns.extractCurrencyAndAmount(fullText)
        if (currencyAmount != null) {
            return ParserResult(
                amount = currencyAmount.second,
                currency = currencyAmount.first,
                type = TransactionType.DEBIT,
                merchant = "Amazon",
                source = TransactionSource.EMAIL
            )
        }

        return null
    }
}
