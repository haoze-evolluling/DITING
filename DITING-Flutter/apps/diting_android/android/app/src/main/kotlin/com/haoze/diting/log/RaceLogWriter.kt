package com.haoze.diting.log

import android.content.ContentValues
import android.content.Context

/// Writes the race callback into `dns_race_log`; provider names stay null, Dart resolves ids.
///
/// The row is queued, not written here: this callback runs on a Go engine thread, and a locked
/// database used to fail the open (dropping the row) or, worse, park the DNS hot path.
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
        if (queryName.isBlank()) return
        val values = ContentValues().apply {
            put("timestamp", System.currentTimeMillis())
            put("queryName", queryName.lowercase())
            put("queryType", queryType)
            put("strategy", strategy)
            put("providerCount", providerCount)
            put("success", if (success) 1 else 0)
            put("elapsedMs", elapsedMs)
            put("selectedProviderId", selectedProviderId.ifBlank { null })
            put("selectedProviderName", null as String?)
            put("selectedElapsedMs", selectedElapsedMs.takeIf { it > 0 })
            put("winnerProviderId", winnerProviderId.ifBlank { null })
            put("winnerProviderName", null as String?)
            put("winnerElapsedMs", winnerElapsedMs.takeIf { it > 0 })
            put("fallbackUsed", if (fallbackUsed) 1 else 0)
            put("fallbackSuccess", if (fallbackSuccess) 1 else 0)
            put("message", errorMessage.ifBlank { null })
        }
        LogTableWriters.of(context, databaseName, TABLE, "diting-race-log").submit(values)
    }
}
