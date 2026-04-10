package com.nodecompass.data.db

import android.content.Context
import app.cash.sqldelight.db.SqlDriver
import app.cash.sqldelight.driver.android.AndroidSqliteDriver
import com.nodecompass.db.NodeCompassDatabase

actual class DriverFactory(private val context: Context) {
    actual fun createDriver(): SqlDriver {
        return AndroidSqliteDriver(NodeCompassDatabase.Schema, context, "nodecompass.db")
    }
}
