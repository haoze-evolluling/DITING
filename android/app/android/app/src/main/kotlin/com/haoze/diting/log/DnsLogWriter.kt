package com.haoze.diting.log

import android.content.Context
import android.database.sqlite.SQLiteStatement

/// Writes the engine's packed DNS batch into `dns_log`, a table the Flutter side also reads.
///
/// The engine hands over the exact payload the log kernel decodes, so this object only skips an
/// empty batch and forwards the bytes. The counters, the classification and the writer queue all
/// happen inside one native call (`dnsBatchSubmit`): Kotlin no longer receives one `ByteArray` per
/// row only to hand them back for a re-pack. The queue is drained on the writer thread, so the
/// engine thread never waits on disk.
object DnsLogWriter {
    const val MODE_ALL = "all"
    const val MODE_BLOCKED_AND_ERRORS = "blocked_and_errors"
    const val MODE_OFF = "off"

    private const val TABLE = "dns_log"

    private const val INSERT_SQL = "INSERT OR IGNORE INTO dns_log " +
        "(timestamp, queryName, queryType, result, message, cached, blockSubscriptionId, packageName) " +
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?)"

    /// `packed` is the engine's batch: `u32 count` then the `dnsBatch` input rows. A zero count is
    /// the only shortcut; everything else is the kernel's.
    fun writeBatch(context: Context, databaseName: String, mode: String, packed: ByteArray) {
        if (packed.size <= Int.SIZE_BYTES) return
        // Counted before the mode check: the notification shows requests with logging off too.
        LogTableWriters.of(context, databaseName, TABLE, "diting-dns-log", INSERT_SQL, ::bindRow)
            .submitDnsBatch(RequestStats.kernel, mode, packed)
    }

    /// The kernel's row layout, bound straight into the compiled statement.
    private fun bindRow(statement: SQLiteStatement, row: ByteArray) {
        val reader = LogPayload.Reader(row)
        statement.bindLong(1, reader.i64())
        statement.bindString(2, reader.string())
        statement.bindLong(3, reader.i32().toLong())
        statement.bindString(4, reader.string())
        val message = reader.optionalString()
        if (message == null) statement.bindNull(5) else statement.bindString(5, message)
        statement.bindLong(6, if (reader.u8() != 0) 1 else 0)
        val subscription = reader.optionalLong()
        if (subscription == null) statement.bindNull(7) else statement.bindLong(7, subscription)
        val packageName = reader.optionalString()
        if (packageName == null) statement.bindNull(8) else statement.bindString(8, packageName)
    }
}
