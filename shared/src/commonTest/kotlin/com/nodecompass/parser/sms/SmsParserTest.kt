package com.nodecompass.parser.sms

import com.nodecompass.data.model.TransactionType
import com.nodecompass.domain.parser.sms.SmsParser
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull

class SmsParserTest {
    private val parser = SmsParser()

    // === INDIAN BANKS (INR) ===

    @Test
    fun testSbiDebit() {
        val sms = "Your a/c no. XXXXXXXX1234 is debited for Rs.500.00 on 07-04-26 by a transfer to MERCHANT NAME. (UPI Ref No 412345678901)."
        val result = parser.parse(sms)
        assertNotNull(result, "SBI debit SMS should parse")
        assertEquals(500.0, result.amount)
        assertEquals("INR", result.currency.code)
        assertEquals(TransactionType.DEBIT, result.type)
        assertEquals("1234", result.account)
    }

    @Test
    fun testHdfcDebitWithCommas() {
        val sms = "Rs 1,50,000.00 debited from a/c **1234 on 07-Apr-26 to VPA merchant@upi (UPI Ref No 412345678901). Not you? Call 18002586161"
        val result = parser.parse(sms)
        assertNotNull(result, "HDFC debit SMS should parse")
        assertEquals(150000.0, result.amount)
        assertEquals("INR", result.currency.code)
        assertEquals(TransactionType.DEBIT, result.type)
    }

    @Test
    fun testIciciCredit() {
        val sms = "ICICI Bank Acct XX1234 credited with Rs.25,000.00 on 07-Apr-26 by NEFT from SENDER NAME. IMPS Ref No:412345678901"
        val result = parser.parse(sms)
        assertNotNull(result, "ICICI credit SMS should parse")
        assertEquals(25000.0, result.amount)
        assertEquals("INR", result.currency.code)
        assertEquals(TransactionType.CREDIT, result.type)
    }

    @Test
    fun testAxisUpiDebit() {
        val sms = "INR 350.00 debited from A/c no. XX1234 on 07-Apr-26. UPI: payee@ybl. Ref 412345678901"
        val result = parser.parse(sms)
        assertNotNull(result, "Axis UPI debit should parse")
        assertEquals(350.0, result.amount)
        assertEquals("INR", result.currency.code)
        assertEquals(TransactionType.DEBIT, result.type)
    }

    @Test
    fun testKotakAtmWithdrawal() {
        val sms = "Rs 10,000 withdrawn from your A/c XX5678 on 07/04/26 at ATM. Avl Bal: Rs 45,000."
        val result = parser.parse(sms)
        assertNotNull(result, "Kotak ATM withdrawal should parse")
        assertEquals(10000.0, result.amount)
        assertEquals(TransactionType.DEBIT, result.type)
    }

    // === US BANKS (USD) ===

    @Test
    fun testChaseDebit() {
        val sms = "You made a $125.50 purchase at WALMART on 04/07/26. Reply STOP to opt out."
        val result = parser.parse(sms)
        assertNotNull(result, "Chase USD debit should parse")
        assertEquals(125.50, result.amount)
        assertEquals("USD", result.currency.code)
        assertEquals(TransactionType.DEBIT, result.type)
    }

    @Test
    fun testBofaDebit() {
        val sms = "BofA: $2,500.00 debited from acct ending 9876 for payment to LANDLORD on 04/07/26."
        val result = parser.parse(sms)
        assertNotNull(result, "BofA debit should parse")
        assertEquals(2500.0, result.amount)
        assertEquals("USD", result.currency.code)
        assertEquals(TransactionType.DEBIT, result.type)
        assertEquals("9876", result.account)
    }

    @Test
    fun testWellsFargoCredit() {
        val sms = "Wells Fargo: A deposit of $3,000.00 was credited to your account ending 4321 on Apr 07, 2026."
        val result = parser.parse(sms)
        assertNotNull(result, "Wells Fargo credit should parse")
        assertEquals(3000.0, result.amount)
        assertEquals("USD", result.currency.code)
        assertEquals(TransactionType.CREDIT, result.type)
    }

    // === UK BANKS (GBP) ===

    @Test
    fun testBarclaysDebit() {
        val sms = "Barclays: £45.99 spent at TESCO STORES on 07-Apr-26 using card ending 5555."
        val result = parser.parse(sms)
        assertNotNull(result, "Barclays GBP debit should parse")
        assertEquals(45.99, result.amount)
        assertEquals("GBP", result.currency.code)
        assertEquals(TransactionType.DEBIT, result.type)
    }

    @Test
    fun testHsbcCredit() {
        val sms = "HSBC: £1,200.00 credited to your a/c XX3456 on 07/04/26. Ref: SALARY PAYMENT"
        val result = parser.parse(sms)
        assertNotNull(result, "HSBC GBP credit should parse")
        assertEquals(1200.0, result.amount)
        assertEquals("GBP", result.currency.code)
        assertEquals(TransactionType.CREDIT, result.type)
    }

    // === EURO ===

    @Test
    fun testEuroDebit() {
        val sms = "Your payment of €89.99 to Netflix was charged on 07/04/26 from account ending 7890."
        val result = parser.parse(sms)
        assertNotNull(result, "EUR debit should parse")
        assertEquals(89.99, result.amount)
        assertEquals("EUR", result.currency.code)
        assertEquals(TransactionType.DEBIT, result.type)
    }

    // === EDGE CASES ===

    @Test
    fun testEmptySms() {
        val result = parser.parse("")
        assertNull(result, "Empty SMS should return null")
    }

    @Test
    fun testShortSms() {
        val result = parser.parse("Hi")
        assertNull(result, "Short SMS should return null")
    }

    @Test
    fun testNonTransactionSms() {
        val result = parser.parse("Your OTP for login is 123456. Do not share with anyone.")
        assertNull(result, "OTP SMS should return null")
    }

    @Test
    fun testPromotionalSms() {
        val result = parser.parse("SALE! Get 50% off on all items at AMAZON. Shop now!")
        assertNull(result, "Promotional SMS should return null")
    }
}
