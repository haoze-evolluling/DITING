package com.haoze.diting.log

import android.content.Context
import android.database.sqlite.SQLiteStatement

object RaceLogWriter {
    private const val TABLE = "dns_race_log"

    private const val INSERT_SQL = "INSERT OR IGNORE INTO dns_race_log " +
        "(timestamp, queryName, queryType, strategy, providerCount, success, elapsedMs, " +
        "selectedProviderId, selectedProviderName, selectedElapsedMs, winnerProviderId, " +
        "winnerProviderName, winnerElapsedMs, fallbackUsed, fallbackSuccess, message) " +
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"

    fun writeBatch(context: Context, databaseName: String, packed: ByteArray) {
        LogTableWriters.of(context, databaseName, TABLE, "diting-race-log", INSERT_SQL, ::bindRow)
            .submitKernelBatch(packed) { queue, rows -> LogNative.raceRowsSubmit(queue, rows) }
    }

    private fun bindRow(statement: SQLiteStatement, row: ByteArray) {
        val reader = LogPayload.Reader(row)
        statement.bindLong(1, reader.i64())
        statement.bindString(2, reader.string())
        statement.bindLong(3, reader.i32().toLong())
        statement.bindString(4, reader.string())
        statement.bindLong(5, reader.i32().toLong())
        statement.bindLong(6, if (reader.u8() != 0) 1 else 0)
        statement.bindLong(7, reader.i64())
        bindOptionalString(statement, 8, reader.optionalString())
        statement.bindNull(9)
        bindOptionalLong(statement, 10, reader.optionalLong())
        bindOptionalString(statement, 11, reader.optionalString())
        statement.bindNull(12)
        bindOptionalLong(statement, 13, reader.optionalLong())
        statement.bindLong(14, if (reader.u8() != 0) 1 else 0)
        statement.bindLong(15, if (reader.u8() != 0) 1 else 0)
        bindOptionalString(statement, 16, reader.optionalString())
    }

    private fun bindOptionalString(statement: SQLiteStatement, position: Int, value: String?) {
        if (value == null) statement.bindNull(position) else statement.bindString(position, value)
    }

    private fun bindOptionalLong(statement: SQLiteStatement, position: Int, value: Long?) {
        if (value == null) statement.bindNull(position) else statement.bindLong(position, value)
    }
}
