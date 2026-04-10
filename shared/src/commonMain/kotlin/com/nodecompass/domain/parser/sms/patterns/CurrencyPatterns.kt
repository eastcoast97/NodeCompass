package com.nodecompass.domain.parser.sms.patterns

import com.nodecompass.data.model.Currency
import com.nodecompass.util.CurrencyUtil

/**
 * Multi-currency regex patterns for extracting currency and amount from SMS text.
 */
object CurrencyPatterns {

    // Order matters: more specific patterns first
    private val currencyAmountPatterns = listOf(
        // Symbol before amount: $500.00, ₹1,500, £200.50, €150, ¥1000
        Regex("""([₹$£€¥₱₩₦৳฿])\s*([\d,]+\.?\d*)"""),
        // Rs/Rs. before amount (Indian): Rs 500.00, Rs.1,500
        Regex("""(?i)\b(Rs\.?|INR)\s*([\d,]+\.?\d*)"""),
        // Currency code before amount: USD 500, GBP 200.50, EUR 150
        Regex("""(?i)\b(USD|GBP|EUR|AUD|CAD|SGD|MYR|JPY|CNY|AED|CHF|NZD|BRL|ZAR|KRW|SEK|NOK|HKD|THB|PHP|IDR|TWD|PKR|BDT|LKR|NGN|KES|EGP|MXN)\s*([\d,]+\.?\d*)"""),
        // Prefixed dollar variants: US$, A$, C$, S$, HK$, NZ$, NT$, MX$, R$, E£
        Regex("""(?i)(US\$|A\$|AU\$|C\$|S\$|HK\$|NZ\$|NT\$|MX\$|R\$|E£|KSh|Rp|RM)\s*([\d,]+\.?\d*)"""),
        // Amount after keyword: amount of 500.00, for 1,500.00
        Regex("""(?i)(?:amount|amt|sum|total|for|of)\s*:?\s*([₹$£€¥]?)\s*([\d,]+\.?\d{2})"""),
    )

    /**
     * Extract currency and amount from SMS text.
     * Returns a pair of (Currency, amount as Double) or null if not found.
     */
    fun extractCurrencyAndAmount(text: String): Pair<Currency, Double>? {
        for (pattern in currencyAmountPatterns) {
            val match = pattern.find(text)
            if (match != null) {
                val symbolOrCode = match.groupValues[1].trim()
                val amountStr = match.groupValues[2].trim()

                val currency = resolveCurrency(symbolOrCode)
                val amount = CurrencyUtil.parseAmount(amountStr, currency)

                if (currency != null && amount != null && amount > 0) {
                    return currency to amount
                }
            }
        }
        return null
    }

    private fun resolveCurrency(symbolOrCode: String): Currency? {
        if (symbolOrCode.isEmpty()) return null

        // Try as symbol first
        CurrencyUtil.currencyFromSymbol(symbolOrCode)?.let { return it }

        // Try as currency code
        Currency.fromCode(symbolOrCode)?.let { return it }

        // Direct symbol mapping for single chars
        return when (symbolOrCode) {
            "$" -> Currency.USD
            "₹" -> Currency.INR
            "£" -> Currency.GBP
            "€" -> Currency.EUR
            "¥" -> Currency.JPY
            "₱" -> Currency.PHP
            "₩" -> Currency.KRW
            "₦" -> Currency.NGN
            "৳" -> Currency.BDT
            "฿" -> Currency.THB
            else -> null
        }
    }
}
