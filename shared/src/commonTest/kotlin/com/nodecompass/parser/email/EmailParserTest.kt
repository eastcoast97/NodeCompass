package com.nodecompass.parser.email

import com.nodecompass.data.model.TransactionSource
import com.nodecompass.data.model.TransactionType
import com.nodecompass.domain.parser.email.EmailReceiptParser
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull

class EmailParserTest {
    private val parser = EmailReceiptParser()

    @Test
    fun testAmazonOrderConfirmation() {
        val subject = "Your Amazon.com order #123-4567890-1234567"
        val body = """
            Hello John,
            Thank you for your order!

            Order Total: $45.99

            Items ordered:
            Wireless Mouse - $25.99
            USB Cable - $10.00
            Shipping: $10.00
        """.trimIndent()
        val sender = "auto-confirm@amazon.com"

        val result = parser.parse(subject, body, sender)
        assertNotNull(result, "Amazon receipt should parse")
        assertEquals(45.99, result.amount)
        assertEquals("USD", result.currency.code)
        assertEquals(TransactionType.DEBIT, result.type)
        assertEquals("Amazon", result.merchant)
        assertEquals(TransactionSource.EMAIL, result.source)
    }

    @Test
    fun testAmazonInrOrder() {
        val subject = "Your Amazon.in order #123-4567890-1234567"
        val body = """
            Thank you for your order!

            Order Total: ₹1,499.00

            Items ordered:
            Phone Case - ₹999.00
            Screen Guard - ₹500.00
        """.trimIndent()
        val sender = "auto-confirm@amazon.in"

        val result = parser.parse(subject, body, sender)
        assertNotNull(result, "Amazon India receipt should parse")
        assertEquals(1499.0, result.amount)
        assertEquals("INR", result.currency.code)
    }

    @Test
    fun testUberRideReceipt() {
        val subject = "Your Uber receipt for Monday"
        val body = """
            Thanks for riding with Uber!

            Trip fare
            Distance: 5.2 km
            Time: 15 min

            Total: $12.50

            Payment: Visa ending in 1234
        """.trimIndent()
        val sender = "noreply@uber.com"

        val result = parser.parse(subject, body, sender)
        assertNotNull(result, "Uber receipt should parse")
        assertEquals(12.50, result.amount)
        assertEquals("USD", result.currency.code)
        assertEquals("Uber", result.merchant)
    }

    @Test
    fun testUberEatsReceipt() {
        val subject = "Your Uber Eats order receipt"
        val body = """
            Your Uber Eats delivery from McDonald's

            Items:
            Big Mac Meal - $8.99
            Fries - $2.49

            Subtotal: $11.48
            Delivery fee: $3.99
            Total: $15.47
        """.trimIndent()
        val sender = "noreply@uber.com"

        val result = parser.parse(subject, body, sender)
        assertNotNull(result, "Uber Eats receipt should parse")
        assertEquals(15.47, result.amount)
        assertEquals("Uber Eats", result.merchant)
    }

    @Test
    fun testGenericSubscriptionReceipt() {
        val subject = "Your subscription receipt"
        val body = """
            Thank you for your payment!

            Service: Premium Plan
            Period: Apr 2026 - May 2026
            Amount charged: $14.99

            Payment method: Visa ending in 5678
        """.trimIndent()
        val sender = "billing@someservice.com"

        val result = parser.parse(subject, body, sender)
        assertNotNull(result, "Generic subscription receipt should parse")
        assertEquals(14.99, result.amount)
        assertEquals("USD", result.currency.code)
        assertEquals(TransactionType.DEBIT, result.type)
    }

    @Test
    fun testHtmlReceipt() {
        val subject = "Payment receipt"
        val body = """
            <html><body>
            <h1>Payment Confirmation</h1>
            <table>
            <tr><td>Item</td><td>Price</td></tr>
            <tr><td>Monthly Plan</td><td>£9.99</td></tr>
            </table>
            <p><strong>Total: £9.99</strong></p>
            </body></html>
        """.trimIndent()
        val sender = "noreply@netflix.com"

        val result = parser.parse(subject, body, sender)
        assertNotNull(result, "HTML receipt should parse")
        assertEquals(9.99, result.amount)
        assertEquals("GBP", result.currency.code)
    }

    @Test
    fun testRefundReceipt() {
        val subject = "Refund confirmation"
        val body = """
            Your refund has been processed.

            Refund amount: $29.99

            The refund will appear on your statement within 5-10 business days.
        """.trimIndent()
        val sender = "orders@shop.example.com"

        val result = parser.parse(subject, body, sender)
        assertNotNull(result, "Refund receipt should parse")
        assertEquals(29.99, result.amount)
        assertEquals(TransactionType.CREDIT, result.type)
    }

    @Test
    fun testNonReceiptEmail() {
        val subject = "Weekly newsletter"
        val body = "Check out our latest blog posts and updates!"
        val sender = "newsletter@blog.com"

        val result = parser.parse(subject, body, sender)
        assertNull(result, "Non-receipt email should return null")
    }
}
