package com.nodecompass.data.db

import app.cash.sqldelight.db.SqlDriver
import app.cash.sqldelight.driver.native.NativeSqliteDriver
import com.nodecompass.db.NodeCompassDatabase

actual class DriverFactory {
    actual fun createDriver(): SqlDriver {
        return NativeSqliteDriver(NodeCompassDatabase.Schema, "nodecompass.db")
    }
}
