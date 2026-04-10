package com.nodecompass.data.model

import kotlinx.serialization.Serializable

@Serializable
data class Currency(
    val code: String,
    val symbol: String,
    val name: String
) {
    companion object {
        val USD = Currency("USD", "$", "US Dollar")
        val INR = Currency("INR", "₹", "Indian Rupee")
        val GBP = Currency("GBP", "£", "British Pound")
        val EUR = Currency("EUR", "€", "Euro")
        val JPY = Currency("JPY", "¥", "Japanese Yen")
        val CNY = Currency("CNY", "¥", "Chinese Yuan")
        val AUD = Currency("AUD", "A$", "Australian Dollar")
        val CAD = Currency("CAD", "C$", "Canadian Dollar")
        val SGD = Currency("SGD", "S$", "Singapore Dollar")
        val AED = Currency("AED", "د.إ", "UAE Dirham")
        val MYR = Currency("MYR", "RM", "Malaysian Ringgit")
        val THB = Currency("THB", "฿", "Thai Baht")
        val PHP = Currency("PHP", "₱", "Philippine Peso")
        val IDR = Currency("IDR", "Rp", "Indonesian Rupiah")
        val BRL = Currency("BRL", "R$", "Brazilian Real")
        val ZAR = Currency("ZAR", "R", "South African Rand")
        val KRW = Currency("KRW", "₩", "South Korean Won")
        val SEK = Currency("SEK", "kr", "Swedish Krona")
        val NOK = Currency("NOK", "kr", "Norwegian Krone")
        val CHF = Currency("CHF", "CHF", "Swiss Franc")
        val NZD = Currency("NZD", "NZ$", "New Zealand Dollar")
        val MXN = Currency("MXN", "MX$", "Mexican Peso")
        val HKD = Currency("HKD", "HK$", "Hong Kong Dollar")
        val TWD = Currency("TWD", "NT$", "New Taiwan Dollar")
        val PKR = Currency("PKR", "₨", "Pakistani Rupee")
        val BDT = Currency("BDT", "৳", "Bangladeshi Taka")
        val LKR = Currency("LKR", "₨", "Sri Lankan Rupee")
        val NGN = Currency("NGN", "₦", "Nigerian Naira")
        val KES = Currency("KES", "KSh", "Kenyan Shilling")
        val EGP = Currency("EGP", "E£", "Egyptian Pound")

        private val byCode: Map<String, Currency> = listOf(
            USD, INR, GBP, EUR, JPY, CNY, AUD, CAD, SGD, AED,
            MYR, THB, PHP, IDR, BRL, ZAR, KRW, SEK, NOK, CHF,
            NZD, MXN, HKD, TWD, PKR, BDT, LKR, NGN, KES, EGP
        ).associateBy { it.code }

        fun fromCode(code: String): Currency? = byCode[code.uppercase()]

        fun fromCodeOrDefault(code: String): Currency =
            fromCode(code) ?: Currency(code.uppercase(), code.uppercase(), code.uppercase())
    }
}
