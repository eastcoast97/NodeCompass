package com.nodecompass.data.model

import kotlinx.serialization.Serializable

@Serializable
data class Transaction(
    val id: Long = 0,
    val amount: Double,
    val currency: Currency,
    val merchant: String,
    val category: Category,
    val timestampMillis: Long,
    val type: TransactionType,
    val source: TransactionSource,
    val rawText: String,
    val account: String? = null,
    val isRecurring: Boolean = false,
    val createdAtMillis: Long = 0
)

@Serializable
enum class TransactionType {
    DEBIT,
    CREDIT
}

@Serializable
enum class TransactionSource {
    SMS,
    EMAIL,
    MANUAL
}
