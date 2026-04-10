package com.nodecompass.data.model

import kotlinx.serialization.Serializable

@Serializable
enum class Category(val displayName: String) {
    FOOD("Food & Dining"),
    GROCERIES("Groceries"),
    TRANSPORT("Transport"),
    SHOPPING("Shopping"),
    BILLS("Bills & Utilities"),
    SUBSCRIPTIONS("Subscriptions"),
    ENTERTAINMENT("Entertainment"),
    HEALTH("Health"),
    EDUCATION("Education"),
    TRANSFERS("Transfers"),
    ATM("ATM Withdrawal"),
    OTHER("Other")
}
