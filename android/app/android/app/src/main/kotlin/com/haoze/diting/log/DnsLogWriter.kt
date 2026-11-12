package com.haoze.diting.log

import android.content.ContentValues
import android.content.Context
import java.io.DataOutputStream
import org.json.JSONArray
import org.json.JSONObject

/// Writes the engine's batch DNS log JSON into `dns_log`, a table the Flutter side also reads.
///
/// The JSON decode stays here (the engine's field letters are its own contract); the
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

    fun writeBatch(context: Context, databaseName: String, mode: String, jsonLogs: String) {
        if (jsonLogs.isBlank()) return
        val array = runCatching { JSONArray(jsonLogs) }.getOrNull() ?: return
        if (array.length() == 0) return
        val packed = LogPayload.pack { out ->
            out.writeInt(array.length())
            for (index in 0 until array.length()) {
                // A non-object entry keeps its defaults, which the kernel skips like a blank domain.
                writeEntry(out, array.optJSONObject(index) ?: JSONObject())
            }
        }
        // Counted before the mode check: the notification shows requests with logging off too.
        val rows = LogNative.dnsBatch(RequestStats.kernel, mode, packed)
        if (rows.isEmpty()) return

        val writer = LogTableWriters.of(context, databaseName, TABLE, "diting-dns-log", ::values)
        rows.forEach(writer::submit)
    }

    private fun writeEntry(out: DataOutputStream, obj: JSONObject) {
        out.writeLong(obj.optLong("ts"))
        LogPayload.writeString(out, obj.optString("d"))
        out.writeInt(obj.optInt("t"))
        out.writeByte(if (obj.optBoolean("b")) 1 else 0)
        LogPayload.writeString(out, obj.optString("k"))
        LogPayload.writeString(out, obj.optString("e"))
        out.writeByte(if (obj.optBoolean("c")) 1 else 0)
        LogPayload.writeString(out, obj.optString("a"))
        LogPayload.writeString(out, obj.optString("i"))
        out.writeLong(obj.optLong("r"))
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
