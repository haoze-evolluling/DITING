package com.haoze.diting.log

import android.content.ContentValues
import android.content.Context

/// `bootstrap_log` writer: the engine's packed bootstrap batches.
///
/// The engine already races bootstrap IPs and reports every attempt through
/// `BootstrapLogCallback`; nothing consumed it before, so the table stayed empty and the
/// dashboard card had no data. The rows are shaped in the log kernel and queued like the race log:
/// this is a per-host stream on an engine thread, not a place to open a database.
object BootstrapLogWriter {
    private const val TABLE = "bootstrap_log"

    /// `packed` is `u32 count | rows(bootstrap input)`; the kernel answers the writer rows in one
    /// call, so a burst of probes costs one JNI pair instead of one per host.
    fun writeBatch(context: Context, databaseName: String, packed: ByteArray) {
        if (packed.size <= Int.SIZE_BYTES) return
        val rows = LogNative.bootstrapRows(packed)
        if (rows.isEmpty()) return
        val writer = LogTableWriters.of(
            context,
            databaseName,
            TABLE,
            "diting-bootstrap-log",
            ::values,
        )
        writer.submitAll(rows)
    }

    /// The kernel's row layout, unpacked into the `bootstrap_log` columns.
    private fun values(row: ByteArray): ContentValues {
        val reader = LogPayload.Reader(row)
        return ContentValues().apply {
            put("timestamp", reader.i64())
            put("ipId", reader.string())
            put("ipName", reader.string())
            put("ip", reader.string())
            put("host", reader.string())
            put("success", if (reader.u8() != 0) 1 else 0)
            put("elapsedMs", reader.i64())
            put("fallbackUsed", if (reader.u8() != 0) 1 else 0)
            put("message", reader.optionalString())
        }
    }
}
