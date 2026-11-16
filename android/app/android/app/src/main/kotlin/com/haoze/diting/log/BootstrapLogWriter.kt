package com.haoze.diting.log

import android.content.Context
import android.database.sqlite.SQLiteStatement

/// `bootstrap_log` writer: the engine's packed bootstrap batches.
///
/// The engine already races bootstrap IPs and reports every attempt through
/// `BootstrapLogCallback`; nothing consumed it before, so the table stayed empty and the
/// dashboard card had no data. The rows are shaped in the log kernel and queued like the race log:
/// this is a per-host stream on an engine thread, not a place to open a database.
object BootstrapLogWriter {
    private const val TABLE = "bootstrap_log"

    private const val INSERT_SQL = "INSERT OR IGNORE INTO bootstrap_log " +
        "(timestamp, ipId, ipName, ip, host, success, elapsedMs, fallbackUsed, message) " +
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)"

    /// `packed` is `u32 count | rows(bootstrap input)`; the kernel classifies and enqueues the
    /// writer rows in one call, so a burst of probes costs one crossing instead of one per host.
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

    /// The kernel's row layout, bound straight into the compiled statement.
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
