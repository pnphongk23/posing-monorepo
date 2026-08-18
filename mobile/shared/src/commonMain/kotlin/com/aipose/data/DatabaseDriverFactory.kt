// shared/src/commonMain/kotlin/com/aipose/data/DatabaseDriverFactory.kt
package com.aipose.data

import app.cash.sqldelight.db.SqlDriver

expect class DatabaseDriverFactory() {
    fun createDriver(): SqlDriver
}
