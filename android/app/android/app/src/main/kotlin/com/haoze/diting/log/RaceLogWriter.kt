package com.haoze.diting.log

import android.content.ContentValues
import android.content.Context

/// Writes the race callback into `dns_race_log`; provider names stay null, Dart resolves ids.
///
/// The row is shaped in the log kernel (`rust/diting-log-core/src/row.rs`) and queued, not written
/// here: this callback runs on an engine thread, and a locked database used to fail the open
/// (dropping the row) or, worse, park the DNS hot path.
object RaceLogWriter {
    private const val TABLE = "dns_race_log"

    fun write(
        context: Context,
        databaseName: String,
        queryName: String,
        queryType: Int,
        strategy: String,
        providerCount: Int,
        success: Boolean,
        elapsedMs: Long,
        selectedProviderId: String,
        selectedElapsedMs: Long,
        winnerProviderId: String,
        winnerElapsedMs: Long,
        fallbackUsed: Boolean,
        fallbackSuccess: Boolean,
        errorMessage: String,
    ) {
        val packed = LogPayload.pack { out ->
            LogPayload.writeString(out, queryName)
            out.writeInt(queryType)
            LogPayload.writeString(out, strategy)
            out.writeInt(providerCount)
            out.writeByte(if (success) 1 else 0)
            out.writeLong(elapsedMs)
            LogPayload.writeString(out, selectedProviderId)
            out.writeLong(selectedElapsedMs)
            LogPayload.writeString(out, winnerProviderId)
            out.writeLong(winnerElapsedMs)
            out.writeByte(if (fallbackUsed) 1 else 0)
            out.writeByte(if (fallbackSuccess) 1 else 0)
            LogPayload.writeString(out, errorMessage)
        }
        val row = LogNative.raceRow(packed) ?: return
        val writer = LogTableWriters.of(context, databaseName, TABLE, "diting-race-log", ::values)
        writer.submit(row)
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
