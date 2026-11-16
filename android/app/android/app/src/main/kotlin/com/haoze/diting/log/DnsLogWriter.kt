package com.haoze.diting.log

import android.content.ContentValues
import android.content.Context

/// Writes the engine's packed DNS batch into `dns_log`, a table the Flutter side also reads.
///
/// The engine hands over the exact payload `LogNative.dnsBatch` decodes, so this object only skips
/// an empty batch and forwards the bytes: no JSON parse and no repack on the JVM side. The
/// classification — result, log-mode filter, `message`, subscription id, blank defaults — happens in
/// the log kernel (`rust/diting-log-core/src/row.rs`). The insert is queued so a locked database
/// retries instead of dropping the batch, and so the engine thread never waits on disk.
object DnsLogWriter {
    const val DB_NORMAL = "diting_database"
    const val DB_EXPRESS = "diting_express"

    /// Server mode's own store. It is created by the Flutter side from `LegacySchema`, so the
    /// server dashboard no longer shares `dns_log`/`dns_cache` rows with normal or express mode.
    const val DB_SERVER = "diting_server_logs"

    const val MODE_ALL = "all"
    const val MODE_BLOCKED_AND_ERRORS = "blocked_and_errors"
    const val MODE_OFF = "off"

    private const val TABLE = "dns_log"

    /// `packed` is the engine's batch: `u32 count` then the `dnsBatch` input rows. A zero count is
    /// the only shortcut; everything else is the kernel's.
    fun writeBatch(context: Context, databaseName: String, mode: String, packed: ByteArray) {
        if (packed.size <= Int.SIZE_BYTES) return
        // Counted before the mode check: the notification shows requests with logging off too.
        val rows = LogNative.dnsBatch(RequestStats.kernel, mode, packed)
        if (rows.isEmpty()) return

        val writer = LogTableWriters.of(context, databaseName, TABLE, "diting-dns-log", ::values)
        // One call for the whole batch: the queue lock and the flush decision are taken once.
        writer.submitAll(rows)
    }

    /// The kernel's row layout, unpacked into the `dns_log` columns.
    private fun values(row: ByteArray): ContentValues {
        val reader = LogPayload.Reader(row)
        return ContentValues().apply {
            put("timestamp", reader.i64())
            put("queryName", reader.string())
            put("queryType", reader.i32())
            put("result", reader.string())
            put("message", reader.optionalString())
            put("cached", if (reader.u8() != 0) 1 else 0)
            put("blockSubscriptionId", reader.optionalLong())
            put("packageName", reader.optionalString())
        }
    }
}
