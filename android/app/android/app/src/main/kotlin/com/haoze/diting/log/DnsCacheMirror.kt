package com.haoze.diting.log

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import org.json.JSONArray
import org.json.JSONObject
import tunnel.Engine
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/// Mirrors the engine's in-memory DNS cache into the `dns_cache` table.
///
/// The Go cache is a sharded LRU with no persistence, so the Flutter cache views had nothing to
/// read: rows only ever existed in the legacy build. `Engine.getDNSCacheEntries` now exposes a
/// snapshot, and this class copies it on a timer. The table is a read-only projection: response
/// bytes are not needed by any Dart reader, so they are stored empty.
class DnsCacheMirror(
    private val context: Context,
    private val databaseName: String,
    private val engine: Engine,
) {
    private val executor: ScheduledExecutorService =
        Executors.newSingleThreadScheduledExecutor { runnable ->
            Thread(runnable, "diting-cache-mirror").apply { isDaemon = true }
        }

    private val closed = AtomicBoolean(false)

    fun start() {
        try {
            executor.scheduleWithFixedDelay(
                { publish() },
                INITIAL_DELAY_MS,
                INTERVAL_MS,
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
            JSONArray(engine.getDNSCacheEntries(MAX_ROWS))
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
        db.beginTransaction()
        try {
            // Replace the projection wholesale: entries the engine evicted or expired must
            // disappear, and the snapshot is already capped to the hottest rows.
            db.delete(TABLE, null, null)
            for (i in 0 until entries.length()) {
                val obj = entries.optJSONObject(i) ?: continue
                db.insertWithOnConflict(
                    TABLE,
                    null,
                    toValues(obj),
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

    private fun toValues(obj: org.json.JSONObject): ContentValues = ContentValues().apply {
        put("key", obj.optString("key"))
        put("queryName", obj.optString("queryName"))
        put("queryType", obj.optInt("queryType"))
        put("queryClass", obj.optInt("queryClass"))
        put("createdAt", obj.optLong("createdAt"))
        put("expiresAt", obj.optLong("expiresAt"))
        put("lastHitAt", obj.optLong("lastHitAt"))
        put("hitCount", obj.optLong("hitCount"))
        put("originalTtlSeconds", obj.optLong("originalTtlSeconds"))
        // NOT NULL columns the Dart readers never touch: the projection has no wire bytes.
        put("ttlOffsets", "")
        put("response", ByteArray(0))
        put("responseSize", obj.optInt("responseSize"))
    }

    private companion object {
        const val TAG = "DnsCacheMirror"
        const val TABLE = "dns_cache"
        const val MAX_ROWS = 200L
        const val INITIAL_DELAY_MS = 5_000L
        const val INTERVAL_MS = 10_000L
    }
}
