package com.haoze.diting.log

import android.content.ContentValues
import android.content.Context

/// `bootstrap_log` writer: one row per bootstrap probe the engine reports.
///
/// The engine already races bootstrap IPs and reports every attempt through
/// `BootstrapLogCallback`; nothing consumed it before, so the table stayed empty and the
/// dashboard card had no data. The row is shaped in the log kernel and queued like the race log:
/// this is a per-host callback on an engine thread, not a place to open a database.
object BootstrapLogWriter {
    private const val TABLE = "bootstrap_log"

    fun write(
        context: Context,
        databaseName: String,
        ipId: String,
        ipName: String,
        ip: String,
        host: String,
        success: Boolean,
        elapsedMs: Long,
        fallbackUsed: Boolean,
        errorMessage: String,
    ) {
        val packed = LogPayload.pack { out ->
            LogPayload.writeString(out, ipId)
            LogPayload.writeString(out, ipName)
            LogPayload.writeString(out, ip)
            LogPayload.writeString(out, host)
            out.writeByte(if (success) 1 else 0)
            out.writeLong(elapsedMs)
            out.writeByte(if (fallbackUsed) 1 else 0)
            LogPayload.writeString(out, errorMessage)
        }
        val row = LogNative.bootstrapRow(packed) ?: return
        val writer = LogTableWriters.of(
            context,
            databaseName,
            TABLE,
            "diting-bootstrap-log",
            ::values,
        )
        writer.submit(row)
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
