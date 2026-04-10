package com.nodecompass.domain.parser.email

import com.nodecompass.data.model.TransactionSource
import com.nodecompass.domain.parser.ParserResult
import com.nodecompass.domain.parser.email.vendors.AmazonParser
import com.nodecompass.domain.parser.email.vendors.GenericReceiptParser
import com.nodecompass.domain.parser.email.vendors.UberParser

/**
 * Orchestrates email receipt parsing.
 * Tries vendor-specific parsers first, falls back to generic pattern matching.
 */
class EmailReceiptParser {

    private val vendorParsers: List<VendorParser> = listOf(
        AmazonParser(),
        UberParser(),
        // Add more vendor parsers here:
        // NetflixParser(),
        // SpotifyParser(),
        // GooglePlayParser(),
        // AppleParser(),
    )

    private val genericParser = GenericReceiptParser()

    /**
     * Parse an email receipt into a transaction.
     *
     * @param subject Email subject line
     * @param body Email body (HTML or plain text)
     * @param senderEmail Sender's email address
     * @return ParserResult if a transaction was detected, null otherwise
     */
    fun parse(subject: String, body: String, senderEmail: String): ParserResult? {
        // Extract plain text from HTML if needed
        val plainBody = if (body.contains("<html", ignoreCase = true) || body.contains("<body", ignoreCase = true)) {
            HtmlExtractor.extractText(body)
        } else {
            body
        }

        // Try vendor-specific parsers first
        for (parser in vendorParsers) {
            if (parser.canHandle(senderEmail, subject)) {
                val result = parser.parse(subject, plainBody, senderEmail)
                if (result != null) return result
            }
        }

        // Fall back to generic receipt parser
        return genericParser.parse(subject, plainBody, senderEmail)
    }
}

/**
 * Base interface for vendor-specific email receipt parsers.
 */
interface VendorParser {
    val vendorName: String
    val senderPatterns: List<String>

    fun canHandle(senderEmail: String, subject: String): Boolean {
        val sender = senderEmail.lowercase()
        return senderPatterns.any { sender.contains(it) }
    }

    fun parse(subject: String, plainBody: String, senderEmail: String): ParserResult?
}
