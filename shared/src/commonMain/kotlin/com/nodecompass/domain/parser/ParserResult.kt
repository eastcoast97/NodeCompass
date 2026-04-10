package com.nodecompass.domain.parser

import com.nodecompass.data.model.Currency
import com.nodecompass.data.model.TransactionSource
import com.nodecompass.data.model.TransactionType

data class ParserResult(
    val amount: Double,
    val currency: Currency,
    val type: TransactionType,
    val merchant: String,
    val account: String? = null,
    val dateMillis: Long? = null,
    val referenceNumber: String? = null,
    val source: TransactionSource
)
