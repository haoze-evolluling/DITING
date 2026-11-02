package com.haoze.diting.log

import android.content.ContentValues
import android.content.Context

/// `bootstrap_log` writer: one row per bootstrap probe the engine reports.
///
/// The engine already races bootstrap IPs and reports every attempt through
/// `BootstrapLogCallback`; nothing consumed it before, so the table stayed empty and the
/// dashboard card had no data. Rows are queued like the race log: this is a per-host callback on
/// an engine thread, not a place to open a database.
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
        if (host.isBlank()) return
        val values = ContentValues().apply {
            put("timestamp", System.currentTimeMillis())
            put("ipId", ipId.ifBlank { "unknown" })
            put("ipName", ipName.ifBlank { ipId })
            put("ip", ip)
            put("host", host.lowercase())
            put("success", if (success) 1 else 0)
            put("elapsedMs", elapsedMs)
            put("fallbackUsed", if (fallbackUsed) 1 else 0)
            put("message", errorMessage.ifBlank { null })
        }
        LogTableWriters.of(context, databaseName, TABLE, "diting-bootstrap-log").submit(values)
    }
}
