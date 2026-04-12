package com.nodecompass.util

import com.nodecompass.data.model.Currency

object CurrencyUtil {

    /**
     * Parse an amount string handling multiple number formats:
     * - Indian: 1,50,000.00 (lakh/crore grouping)
     * - Western: 150,000.00
     * - European: 150.000,00 (dots as thousands, comma as decimal)
     */
    fun parseAmount(amountStr: String, currency: Currency? = null): Double? {
        val cleaned = amountStr.trim()
        if (cleaned.isEmpty()) return null

        // Remove currency symbols and whitespace
        val numStr = cleaned
            .replace(Regex("[^0-9.,]"), "")
            .trim()

        if (numStr.isEmpty()) return null

        return when {
            // European format: dots as thousands separator, comma as decimal.
            // Validated: must have at most 2 decimal digits after the comma to
            // avoid false positives like "12.34,56" that are actually malformed.
            numStr.contains('.') && numStr.contains(',') && numStr.lastIndexOf(',') > numStr.lastIndexOf('.') -> {
                val parts = numStr.split(',')
                if (parts.size == 2 && parts[1].length <= 2) {
                    numStr.replace(".", "").replace(",", ".").toDoubleOrNull()
                } else {
                    // Ambiguous — treat as standard (comma as thousands)
                    numStr.replace(",", "").toDoubleOrNull()
                }
            }

            // Standard format with both comma and dot: "150,000.00"
            numStr.contains(',') && numStr.contains('.') && numStr.lastIndexOf('.') > numStr.lastIndexOf(',') -> {
                numStr.replace(",", "").toDoubleOrNull()
            }

            // Commas only (no dot) — thousands separators: "150,000" or Indian "1,50,000"
            numStr.contains(',') && !numStr.contains('.') -> {
                numStr.replace(",", "").toDoubleOrNull()
            }

            // Just a number with optional decimal
            else -> numStr.toDoubleOrNull()
        }
    }

    /**
     * Format amount with currency symbol for display.
     */
    fun formatAmount(amount: Double, currency: Currency): String {
        val formatted = if (amount == amount.toLong().toDouble()) {
            amount.toLong().toString()
        } else {
            // Round to 2 decimal places
            val rounded = (amount * 100).toLong() / 100.0
            rounded.toString()
        }

        return "${currency.symbol}$formatted"
    }

    /**
     * Maps common currency symbols/prefixes found in SMS/emails to Currency objects.
     */
    private val symbolToCurrency = mapOf(
        "$" to Currency.USD,
        "₹" to Currency.INR,
        "rs" to Currency.INR,
        "rs." to Currency.INR,
        "inr" to Currency.INR,
        "£" to Currency.GBP,
        "€" to Currency.EUR,
        "¥" to Currency.JPY,
        "a$" to Currency.AUD,
        "au$" to Currency.AUD,
        "aud" to Currency.AUD,
        "c$" to Currency.CAD,
        "cad" to Currency.CAD,
        "s$" to Currency.SGD,
        "sgd" to Currency.SGD,
        "rm" to Currency.MYR,
        "myr" to Currency.MYR,
        "฿" to Currency.THB,
        "₱" to Currency.PHP,
        "rp" to Currency.IDR,
        "r$" to Currency.BRL,
        "₩" to Currency.KRW,
        "kr" to Currency.SEK,
        "chf" to Currency.CHF,
        "nz$" to Currency.NZD,
        "hk$" to Currency.HKD,
        "nt$" to Currency.TWD,
        "₨" to Currency.PKR,
        "৳" to Currency.BDT,
        "₦" to Currency.NGN,
        "ksh" to Currency.KES,
        "usd" to Currency.USD,
        "gbp" to Currency.GBP,
        "eur" to Currency.EUR,
        "jpy" to Currency.JPY,
        "cny" to Currency.CNY,
        "us$" to Currency.USD,
    )

    fun currencyFromSymbol(symbol: String): Currency? {
        return symbolToCurrency[symbol.trim().lowercase()]
    }
}
