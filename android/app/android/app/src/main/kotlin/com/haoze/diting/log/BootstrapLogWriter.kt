package com.haoze.diting.log

import android.content.Context
import android.database.sqlite.SQLiteStatement

object BootstrapLogWriter {
    private const val TABLE = "bootstrap_log"

    private const val INSERT_SQL = "INSERT OR IGNORE INTO bootstrap_log " +
        "(timestamp, ipId, ipName, ip, host, success, elapsedMs, fallbackUsed, message) " +
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)"

    fun writeBatch(context: Context, databaseName: String, packed: ByteArray) {
        LogTableWriters.of(
            context,
            databaseName,
            TABLE,
            "diting-bootstrap-log",
            INSERT_SQL,
            ::bindRow,
        ).submitKernelBatch(packed) { queue, rows ->
            LogNative.bootstrapRowsSubmit(queue, rows)
        }
    }

    private fun bindRow(statement: SQLiteStatement, row: ByteArray) {
        val reader = LogPayload.Reader(row)
        statement.bindLong(1, reader.i64())
        statement.bindString(2, reader.string())
        statement.bindString(3, reader.string())
        statement.bindString(4, reader.string())
        statement.bindString(5, reader.string())
        statement.bindLong(6, if (reader.u8() != 0) 1 else 0)
        statement.bindLong(7, reader.i64())
        statement.bindLong(8, if (reader.u8() != 0) 1 else 0)
        val message = reader.optionalString()
        if (message == null) statement.bindNull(9) else statement.bindString(9, message)
    }
}
