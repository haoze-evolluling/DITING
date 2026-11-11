package com.haoze.diting.log

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import org.json.JSONArray
import org.json.JSONObject
import com.haoze.diting.engine.TunnelEngine
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/// Mirrors the engine's in-memory DNS cache into the `dns_cache` table.
///
/// The engine cache is a sharded LRU with no persistence, so the Flutter cache views had nothing to
/// read: rows only ever existed in the legacy build. `Engine.getDNSCacheEntries` now exposes a
/// snapshot, and this class copies it on a timer. The table is a read-only projection: response
/// bytes are not needed by any Dart reader, so they are stored empty — that decision, the row cap
/// and the cadence live in the log kernel (`rust/diting-log-core/src/mirror.rs`).
class DnsCacheMirror(
    private val context: Context,
    private val databaseName: String,
    private val engine: TunnelEngine,
) {
    private val executor: ScheduledExecutorService =
        Executors.newSingleThreadScheduledExecutor { runnable ->
            Thread(runnable, "diting-cache-mirror").apply { isDaemon = true }
        }

    private val closed = AtomicBoolean(false)
    private val layout = LogNative.mirrorLayout()

    fun start() {
        try {
            executor.scheduleWithFixedDelay(
                { publish() },
                layout.initialDelayMs,
                layout.intervalMs,
                TimeUnit.MILLISECONDS,
            )
        } catch (_: RejectedExecutionException) {
            // Already shut down: nothing to publish.
        }
    }

    /// Stops the timer; the last snapshot stays in the table for the UI to read.
    fun close() {
        if (!closed.compareAndSet(false, true)) return
        executor.shutdownNow()
    }

    private fun publish() {
        if (closed.get()) return
        val entries = try {
            JSONArray(engine.getDNSCacheEntries(layout.maxRows))
        } catch (t: Throwable) {
            DbWriteHealth.warn(TAG, "Unable to read engine cache snapshot", t)
            return
        }

        val db = when (val opened = LegacyDb.open(context, databaseName)) {
            is LegacyDb.Open.Ready -> opened.db
            // No database yet, or locked right now: the next tick is 10s away, so just skip.
            LegacyDb.Open.Absent -> return
            is LegacyDb.Open.Unavailable -> return
        }
        if (!LegacyDb.hasTable(db, TABLE)) return
        val rows = LogNative.mirrorRows(readEntries(entries))
        db.beginTransaction()
        try {
            // Replace the projection wholesale: entries the engine evicted or expired must
            // disappear, and the snapshot is already capped to the hottest rows.
            db.delete(TABLE, null, null)
            for (row in rows) {
                db.insertWithOnConflict(
                    TABLE,
                    null,
                    toValues(row),
                    SQLiteDatabase.CONFLICT_REPLACE,
                )
            }
            db.setTransactionSuccessful()
        } catch (t: Throwable) {
            DbWriteHealth.warn(TAG, "Unable to mirror DNS cache", t)
        } finally {
            runCatching { db.endTransaction() }
        }
    }

    /// `Engine.getDNSCacheEntries`' JSON, in the order the kernel expects.
    private fun readEntries(entries: JSONArray): List<LogMirrorEntry> {
        val rows = ArrayList<LogMirrorEntry>(entries.length())
        for (index in 0 until entries.length()) {
            val obj = entries.optJSONObject(index) ?: continue
            rows += toEntry(obj)
        }
        return rows
    }

    private fun toEntry(obj: JSONObject): LogMirrorEntry = LogMirrorEntry(
        key = obj.optString("key"),
        queryName = obj.optString("queryName"),
        queryType = obj.optInt("queryType"),
        queryClass = obj.optInt("queryClass"),
        createdAt = obj.optLong("createdAt"),
        expiresAt = obj.optLong("expiresAt"),
        lastHitAt = obj.optLong("lastHitAt"),
        hitCount = obj.optLong("hitCount"),
        originalTtlSeconds = obj.optLong("originalTtlSeconds"),
        responseSize = obj.optInt("responseSize"),
    )

    /// The kernel's row layout, unpacked into the `dns_cache` columns.
    private fun toValues(row: ByteArray): ContentValues {
        val reader = LogPayload.Reader(row)
        return ContentValues().apply {
            put("key", reader.string())
            put("queryName", reader.string())
            put("queryType", reader.i32())
            put("queryClass", reader.i32())
            put("createdAt", reader.i64())
            put("expiresAt", reader.i64())
            put("lastHitAt", reader.i64())
            put("hitCount", reader.i64())
            put("originalTtlSeconds", reader.i64())
            // NOT NULL columns the Dart readers never touch: the projection has no wire bytes.
            put("ttlOffsets", reader.string())
            put("response", reader.blob())
            put("responseSize", reader.i32())
        }
    }

    private companion object {
        const val TAG = "DnsCacheMirror"
        const val TABLE = "dns_cache"
    }
}
