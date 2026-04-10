package com.nodecompass.data.db

import com.nodecompass.TransactionEntity
import com.nodecompass.data.model.Category
import com.nodecompass.data.model.Currency
import com.nodecompass.data.model.Transaction
import com.nodecompass.data.model.TransactionSource
import com.nodecompass.data.model.TransactionType
import com.nodecompass.db.NodeCompassDatabase
import kotlinx.datetime.Clock

class TransactionRepository(private val database: NodeCompassDatabase) {

    private val queries = database.transactionQueries

    fun getAllTransactions(): List<Transaction> {
        return queries.getAllTransactions().executeAsList().map { it.toDomain() }
    }

    fun getTransactionsByMonth(startOfMonth: Long, endOfMonth: Long): List<Transaction> {
        return queries.getTransactionsByMonth(startOfMonth, endOfMonth)
            .executeAsList()
            .map { it.toDomain() }
    }

    fun getSpendingByCategory(startOfMonth: Long, endOfMonth: Long): Map<Category, Double> {
        return queries.getSpendingByCategory(startOfMonth, endOfMonth)
            .executeAsList()
            .associate { row ->
                val category = try {
                    Category.valueOf(row.category)
                } catch (_: IllegalArgumentException) {
                    Category.OTHER
                }
                category to (row.total ?: 0.0)
            }
    }

    fun getRecurringCharges(): List<RecurringCharge> {
        return queries.getRecurringCharges().executeAsList().map { row ->
            RecurringCharge(
                merchant = row.merchant,
                amount = row.amount,
                currency = Currency.fromCodeOrDefault(row.currency),
                occurrenceCount = row.occurrence_count,
                lastSeenMillis = row.last_seen ?: 0L
            )
        }
    }

    fun getTotalSpendThisMonth(startOfMonth: Long, endOfMonth: Long): Double {
        return queries.getTotalSpendThisMonth(startOfMonth, endOfMonth)
            .executeAsOne()
    }

    fun getTransactionsBySource(source: TransactionSource): List<Transaction> {
        return queries.getTransactionsBySource(source.name)
            .executeAsList()
            .map { it.toDomain() }
    }

    fun getRecentTransactions(limit: Long = 20): List<Transaction> {
        return queries.getRecentTransactions(limit)
            .executeAsList()
            .map { it.toDomain() }
    }

    fun insertTransaction(transaction: Transaction): Boolean {
        // Check for duplicates first
        val duplicateCount = queries.findDuplicate(
            amount = transaction.amount,
            merchant = transaction.merchant,
            timestamp = transaction.timestampMillis
        ).executeAsOne()

        if (duplicateCount > 0) return false

        queries.insertTransaction(
            amount = transaction.amount,
            currency = transaction.currency.code,
            merchant = transaction.merchant,
            category = transaction.category.name,
            timestamp = transaction.timestampMillis,
            type = transaction.type.name,
            source = transaction.source.name,
            raw_text = transaction.rawText,
            account = transaction.account,
            is_recurring = if (transaction.isRecurring) 1L else 0L,
            created_at = Clock.System.now().toEpochMilliseconds()
        )
        return true
    }

    fun deleteTransaction(id: Long) {
        queries.deleteTransaction(id)
    }
}

private fun TransactionEntity.toDomain(): Transaction {
    return Transaction(
        id = id,
        amount = amount,
        currency = Currency.fromCodeOrDefault(currency),
        merchant = merchant,
        category = try {
            Category.valueOf(category)
        } catch (_: IllegalArgumentException) {
            Category.OTHER
        },
        timestampMillis = timestamp,
        type = try {
            TransactionType.valueOf(type)
        } catch (_: IllegalArgumentException) {
            TransactionType.DEBIT
        },
        source = try {
            TransactionSource.valueOf(source)
        } catch (_: IllegalArgumentException) {
            TransactionSource.MANUAL
        },
        rawText = raw_text,
        account = account,
        isRecurring = is_recurring != 0L,
        createdAtMillis = created_at
    )
}

data class RecurringCharge(
    val merchant: String,
    val amount: Double,
    val currency: Currency,
    val occurrenceCount: Long,
    val lastSeenMillis: Long
)
