package com.haoze.diting.log

import android.content.ContentValues
import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/// Writes the engine's batch DNS log JSON into `dns_log`, a table the Flutter side also reads.
///
/// Parsing stays here (pure JSON work on the callback thread); the insert is queued so a locked
/// database retries instead of dropping the batch, and so the engine thread never waits on disk.
object DnsLogWriter {
    const val DB_NORMAL = "diting_database"
    const val DB_EXPRESS = "diting_express"

    const val MODE_ALL = "all"
    const val MODE_BLOCKED_AND_ERRORS = "blocked_and_errors"
    const val MODE_OFF = "off"

    private const val TABLE = "dns_log"

    fun writeBatch(context: Context, databaseName: String, mode: String, jsonLogs: String) {
        if (jsonLogs.isBlank()) return
        val array = runCatching { JSONArray(jsonLogs) }.getOrNull() ?: return
        if (array.length() == 0) return
        // Counted before the mode check: the notification shows requests with logging off too.
        for (i in 0 until array.length()) {
            array.optJSONObject(i)?.let(RequestStats::onDns)
        }
        if (mode == MODE_OFF) return

        val writer = LogTableWriters.of(context, databaseName, TABLE, "diting-dns-log")
        for (i in 0 until array.length()) {
            val obj = array.optJSONObject(i) ?: continue
            val entity = toEntity(obj, mode) ?: continue
            writer.submit(
                ContentValues().apply {
                    put("timestamp", entity.timestamp)
                    put("queryName", entity.queryName)
                    put("queryType", entity.queryType)
                    put("result", entity.result)
                    put("message", entity.message)
                    put("cached", if (entity.cached) 1 else 0)
                    put("blockSubscriptionId", entity.blockSubscriptionId)
                    put("packageName", entity.packageName)
                },
            )
        }
    }

    private fun toEntity(obj: JSONObject, mode: String): LogEntity? {
        val domain = obj.optString("d")
        if (domain.isBlank()) return null
        val blocked = obj.optBoolean("b")
        val blockedBy = obj.optString("k")
        val error = obj.optString("e")
        val result = when {
            error.isNotBlank() -> "ERROR"
            blockedBy.startsWith("rewrite=") -> "REWRITTEN"
            blocked -> "BLOCKED"
            else -> "PASSED"
        }
        if (mode == MODE_BLOCKED_AND_ERRORS && result == "PASSED") return null
        val resolved = obj.optString("i")
        val app = obj.optString("a")
        val elapsed = obj.optLong("r")
        val message = listOfNotNull(
            app.takeIf { it.isNotBlank() }?.let { "app=$it" },
            resolved.takeIf { it.isNotBlank() }?.let { "resolved=$it" },
            blockedBy.takeIf { it.isNotBlank() }?.let { "blocked_by=$it" },
            error.takeIf { it.isNotBlank() }?.let { "error=$it" },
            elapsed.takeIf { it > 0 }?.let { "elapsed=${it}ms" },
        ).joinToString(", ").takeIf { it.isNotEmpty() }
        return LogEntity(
            timestamp = obj.optLong("ts").takeIf { it > 0 } ?: System.currentTimeMillis(),
            queryName = domain.lowercase(),
            queryType = obj.optInt("t"),
            result = result,
            message = message,
            cached = obj.optBoolean("c"),
            blockSubscriptionId = subscriptionIdOf(blockedBy),
            packageName = app.ifBlank { null },
        )
    }

    private fun subscriptionIdOf(blockedBy: String): Long? = blockedBy
        .split(',')
        .map { it.trim() }
        .firstNotNullOfOrNull { token ->
            if (token.startsWith("sub_")) token.removePrefix("sub_").toLongOrNull() else null
        }

    private data class LogEntity(
        val timestamp: Long,
        val queryName: String,
        val queryType: Int,
        val result: String,
        val message: String?,
        val cached: Boolean,
        val blockSubscriptionId: Long?,
        val packageName: String?,
    )
}
