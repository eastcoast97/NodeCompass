package com.nodecompass.categorizer

import com.nodecompass.data.model.Category
import com.nodecompass.domain.categorizer.TransactionCategorizer
import kotlin.test.Test
import kotlin.test.assertEquals

class CategorizerTest {
    private val categorizer = TransactionCategorizer()

    // === FOOD ===
    @Test
    fun testSwiggy() = assertEquals(Category.FOOD, categorizer.categorize("Swiggy"))

    @Test
    fun testZomato() = assertEquals(Category.FOOD, categorizer.categorize("ZOMATO ORDER"))

    @Test
    fun testUberEats() = assertEquals(Category.FOOD, categorizer.categorize("Uber Eats delivery"))

    @Test
    fun testDoordash() = assertEquals(Category.FOOD, categorizer.categorize("DoorDash Inc"))

    @Test
    fun testStarbucks() = assertEquals(Category.FOOD, categorizer.categorize("STARBUCKS #12345"))

    @Test
    fun testMcdonalds() = assertEquals(Category.FOOD, categorizer.categorize("McDonald's Store"))

    // === GROCERIES ===
    @Test
    fun testWholeFoods() = assertEquals(Category.GROCERIES, categorizer.categorize("Whole Foods Market"))

    @Test
    fun testBigbasket() = assertEquals(Category.GROCERIES, categorizer.categorize("BIGBASKET.COM"))

    @Test
    fun testBlinkit() = assertEquals(Category.GROCERIES, categorizer.categorize("Blinkit Order"))

    @Test
    fun testInstacart() = assertEquals(Category.GROCERIES, categorizer.categorize("Instacart delivery"))

    // === TRANSPORT ===
    @Test
    fun testUber() = assertEquals(Category.TRANSPORT, categorizer.categorize("Uber BV"))

    @Test
    fun testLyft() = assertEquals(Category.TRANSPORT, categorizer.categorize("LYFT *RIDE"))

    @Test
    fun testOla() = assertEquals(Category.TRANSPORT, categorizer.categorize("Ola Cabs"))

    @Test
    fun testShellFuel() = assertEquals(Category.TRANSPORT, categorizer.categorize("SHELL OIL STATION"))

    // === SHOPPING ===
    @Test
    fun testAmazon() = assertEquals(Category.SHOPPING, categorizer.categorize("Amazon.com"))

    @Test
    fun testFlipkart() = assertEquals(Category.SHOPPING, categorizer.categorize("Flipkart Marketplace"))

    @Test
    fun testTarget() = assertEquals(Category.SHOPPING, categorizer.categorize("TARGET STORE"))

    @Test
    fun testIkea() = assertEquals(Category.SHOPPING, categorizer.categorize("IKEA Home Furnishings"))

    // === SUBSCRIPTIONS ===
    @Test
    fun testNetflix() = assertEquals(Category.SUBSCRIPTIONS, categorizer.categorize("Netflix.com"))

    @Test
    fun testSpotify() = assertEquals(Category.SUBSCRIPTIONS, categorizer.categorize("Spotify Premium"))

    @Test
    fun testAppleBill() = assertEquals(Category.SUBSCRIPTIONS, categorizer.categorize("APPLE.COM/BILL"))

    @Test
    fun testChatGpt() = assertEquals(Category.SUBSCRIPTIONS, categorizer.categorize("ChatGPT Plus"))

    // === BILLS ===
    @Test
    fun testElectricity() = assertEquals(Category.BILLS, categorizer.categorize("City Electricity Board"))

    @Test
    fun testJio() = assertEquals(Category.BILLS, categorizer.categorize("Jio Prepaid Recharge"))

    @Test
    fun testVerizon() = assertEquals(Category.BILLS, categorizer.categorize("Verizon Wireless"))

    // === ENTERTAINMENT ===
    @Test
    fun testBookMyShow() = assertEquals(Category.ENTERTAINMENT, categorizer.categorize("BookMyShow"))

    @Test
    fun testSteam() = assertEquals(Category.ENTERTAINMENT, categorizer.categorize("STEAM PURCHASE"))

    // === HEALTH ===
    @Test
    fun testApolloPharmacy() = assertEquals(Category.HEALTH, categorizer.categorize("Apollo Pharmacy"))

    @Test
    fun testCvsPharmacy() = assertEquals(Category.HEALTH, categorizer.categorize("CVS Pharmacy"))

    // === ATM ===
    @Test
    fun testAtmWithdrawal() = assertEquals(Category.ATM, categorizer.categorize("ATM WITHDRAWAL"))

    // === TRANSFERS ===
    @Test
    fun testUpi() = assertEquals(Category.TRANSFERS, categorizer.categorize("UPI transfer to John"))

    @Test
    fun testVenmo() = assertEquals(Category.TRANSFERS, categorizer.categorize("Venmo payment"))

    // === OTHER ===
    @Test
    fun testUnknownMerchant() = assertEquals(Category.OTHER, categorizer.categorize("RANDOM STORE XYZ"))

    @Test
    fun testEmpty() = assertEquals(Category.OTHER, categorizer.categorize(""))
}
