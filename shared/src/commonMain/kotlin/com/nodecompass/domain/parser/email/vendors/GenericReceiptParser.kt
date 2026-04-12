package com.nodecompass.domain.parser.email.vendors

import com.nodecompass.data.model.TransactionSource
import com.nodecompass.data.model.TransactionType
import com.nodecompass.domain.parser.ParserResult
import com.nodecompass.domain.parser.email.VendorParser
import com.nodecompass.domain.parser.sms.patterns.CurrencyPatterns

/**
 * Generic receipt parser that attempts to extract transaction data
 * from any receipt-like email using common patterns.
 */
class GenericReceiptParser : VendorParser {
    override val vendorName = "Generic"
    override val senderPatterns = emptyList<String>()

    // Keywords that suggest an email is a receipt
    private val receiptKeywords = listOf(
        "receipt", "invoice", "order confirmation", "payment confirmation",
        "payment received", "billing statement", "subscription",
        "your order", "purchase", "transaction", "charged",
        "refund", "refund confirmation", "reversal"
    )

    private val totalPatterns = listOf(
        // Prefer "Grand Total" and "Order Total" first
        Regex("""(?i)(?:grand\s+total|order\s+total)\s*:?\s*([₹$£€¥A-Z]{1,4}\.?\s*[\d,]+\.?\d*)"""),
        // Then "Total" but NOT "Subtotal", also match "Refund amount"
        Regex("""(?i)(?<!sub)(?:total|amount\s+charged|charged|paid|refund\s+amount)\s*:?\s*([₹$£€¥A-Z]{1,4}\.?\s*[\d,]+\.?\d*)"""),
        Regex("""(?i)(?<!sub)(?:total|amount|charged|paid|refund)\s*:?\s*(?:Rs\.?|INR|USD|GBP|EUR|CAD|AUD)\s*([\d,]+\.?\d*)"""),
    )

    override fun canHandle(senderEmail: String, subject: String): Boolean {
        // Generic parser always runs as fallback
        val sub = subject.lowercase()
        return receiptKeywords.any { sub.contains(it) }
    }

    override fun parse(subject: String, plainBody: String, senderEmail: String): ParserResult? {
        val fullText = "$subject\n$plainBody"

        // Extract merchant from sender email domain
        val merchant = extractMerchantFromEmail(senderEmail)

        // Determine if refund
        val isRefund = fullText.lowercase().let {
            it.contains("refund") || it.contains("reversal") || it.contains("returned")
        }
        val type = if (isRefund) TransactionType.CREDIT else TransactionType.DEBIT

        // Try specific total patterns first
        for (pattern in totalPatterns) {
            val match = pattern.find(fullText)
            if (match != null) {
                val currencyAmount = CurrencyPatterns.extractCurrencyAndAmount(match.value)
                if (currencyAmount != null) {
                    return ParserResult(
                        amount = currencyAmount.second,
                        currency = currencyAmount.first,
                        type = type,
                        merchant = merchant,
                        source = TransactionSource.EMAIL
                    )
                }
            }
        }

        return null
    }

    private fun extractMerchantFromEmail(email: String): String {
        // Safely extract a brand name from a sender address.
        // Handles malformed emails (missing @, missing .) and skips generic
        // subdomains like "noreply", "mail", "support" so that
        // "orders@shop.company.com" becomes "Shop" (or "Company") instead of "Orders".
        if ("@" !in email) return "Unknown"

        val domainPart = email.substringAfter("@")
        if ("." !in domainPart) return "Unknown"

        val name = domainPart.substringBefore(".")
        val genericPrefixes = setOf("mail", "email", "noreply", "no-reply", "info", "support", "com")

        if (name.length < 2 || name.lowercase() in genericPrefixes) {
            val remaining = domainPart.substringAfter(".")
            if ("." in remaining) {
                val secondName = remaining.substringBefore(".")
                if (secondName.length >= 2) {
                    return secondName.replaceFirstChar { it.uppercase() }
                }
            }
            return name.replaceFirstChar { it.uppercase() }
        }

        return name.replaceFirstChar { it.uppercase() }
    }
}
