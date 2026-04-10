package com.nodecompass.di

import com.nodecompass.data.db.TransactionRepository
import com.nodecompass.domain.categorizer.TransactionCategorizer
import com.nodecompass.domain.ghost.GhostSubscriptionDetector
import com.nodecompass.domain.parser.email.EmailReceiptParser
import com.nodecompass.domain.parser.sms.SmsParser
import org.koin.dsl.module

val sharedModule = module {
    single { TransactionRepository(get()) }
    single { SmsParser() }
    single { EmailReceiptParser() }
    single { TransactionCategorizer() }
    single { GhostSubscriptionDetector(get()) }
}
