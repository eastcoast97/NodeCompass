package com.nodecompass.domain.parser.sms

import com.nodecompass.data.model.Currency
import com.nodecompass.data.model.TransactionSource
import com.nodecompass.data.model.TransactionType
import com.nodecompass.domain.parser.ParserResult
import com.nodecompass.domain.parser.sms.patterns.CurrencyPatterns
import com.nodecompass.domain.parser.sms.patterns.TransactionPatterns
import com.nodecompass.util.CurrencyUtil

/**
 * Universal SMS parser that works globally across banks and currencies.
 * Uses pattern matching to extract transaction data from bank SMS messages.
 */
class SmsParser {

    fun parse(smsBody: String): ParserResult? {
        val text = smsBody.trim()
        if (text.length < 10) return null

        // Step 1: Determine transaction type (debit or credit)
        val type = TransactionPatterns.detectTransactionType(text) ?: return null

        // Step 2: Extract currency and amount
        val currencyAmount = CurrencyPatterns.extractCurrencyAndAmount(text) ?: return null

        // Step 3: Extract merchant/payee
        val merchant = TransactionPatterns.extractMerchant(text) ?: "Unknown"

        // Step 4: Extract account number (last 4 digits)
        val account = TransactionPatterns.extractAccount(text)

        // Step 5: Extract date
        val dateMillis = TransactionPatterns.extractDate(text)

        // Step 6: Extract reference number
        val refNumber = TransactionPatterns.extractReference(text)

        return ParserResult(
            amount = currencyAmount.second,
            currency = currencyAmount.first,
            type = type,
            merchant = merchant.trim(),
            account = account,
            dateMillis = dateMillis,
            referenceNumber = refNumber,
            source = TransactionSource.SMS
        )
    }
}
