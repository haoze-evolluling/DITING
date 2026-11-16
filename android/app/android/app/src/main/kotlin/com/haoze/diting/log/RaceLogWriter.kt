package com.haoze.diting.log

import android.content.ContentValues
import android.content.Context

/// Writes the engine's packed race batches into `dns_race_log`; provider names stay null, Dart
/// resolves ids.
///
/// The rows are shaped in the log kernel (`rust/diting-log-core/src/row.rs`) and queued, not written
/// here: this callback runs on an engine thread, and a locked database used to fail the open
/// (dropping the row) or, worse, park the DNS hot path. One batch is two JNI calls (classify, then
/// enqueue) instead of one pair per race result.
object RaceLogWriter {
    private const val TABLE = "dns_race_log"

    /// `packed` is `u32 count | rows(race input)`; the kernel answers the same framing with the
    /// `dns_race_log` rows, and the queue takes them all at once.
    fun writeBatch(context: Context, databaseName: String, packed: ByteArray) {
        if (packed.size <= Int.SIZE_BYTES) return
        val rows = LogNative.raceRows(packed)
        if (rows.isEmpty()) return
        val writer = LogTableWriters.of(context, databaseName, TABLE, "diting-race-log", ::values)
        writer.submitAll(rows)
    }

    /// The kernel's row layout, unpacked into the `dns_race_log` columns.
    private fun values(row: ByteArray): ContentValues {
        val reader = LogPayload.Reader(row)
        return ContentValues().apply {
            put("timestamp", reader.i64())
            put("queryName", reader.string())
            put("queryType", reader.i32())
            put("strategy", reader.string())
            put("providerCount", reader.i32())
            put("success", if (reader.u8() != 0) 1 else 0)
            put("elapsedMs", reader.i64())
            put("selectedProviderId", reader.optionalString())
            put("selectedProviderName", null as String?)
            put("selectedElapsedMs", reader.optionalLong())
            put("winnerProviderId", reader.optionalString())
            put("winnerProviderName", null as String?)
            put("winnerElapsedMs", reader.optionalLong())
            put("fallbackUsed", if (reader.u8() != 0) 1 else 0)
            put("fallbackSuccess", if (reader.u8() != 0) 1 else 0)
            put("message", reader.optionalString())
        }
    }
}
