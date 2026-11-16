package com.haoze.diting.log

import android.content.Context
import android.database.sqlite.SQLiteStatement
import com.haoze.diting.engine.TunnelEngine
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/// Mirrors the engine's in-memory DNS cache into the `dns_cache` table.
///
/// The engine cache is a sharded LRU with no persistence, so the Flutter cache views had nothing to
/// read: rows only ever existed in the legacy build. `Engine.getDNSCacheSnapshot` now returns the
/// hottest entries as packed bytes in the log kernel's mirror input layout, so this class forwards
/// them untouched: no JSON document, no per-entry model and no re-pack cross the boundary. The
/// table is a read-only projection: response bytes are not needed by any Dart reader, so they are
/// stored empty — that decision, the row cap and the cadence live in the log kernel
/// (`rust/diting-log-core/src/mirror.rs`).
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
        val rows = try {
            // Engine bytes -> kernel rows: one crossing, no intermediate model.
            LogNative.mirrorRows(engine.getDNSCacheSnapshot(layout.maxRows))
        } catch (t: Throwable) {
            DbWriteHealth.warn(TAG, "Unable to read engine cache snapshot", t)
            return
        }

        val db = when (val opened = AppDatabase.open(context, databaseName)) {
            is AppDatabase.Open.Ready -> opened.db
            // No database yet, or locked right now: the next tick is 10s away, so just skip.
            AppDatabase.Open.Absent -> return
            is AppDatabase.Open.Unavailable -> return
        }
        if (!AppDatabase.hasTable(db, TABLE)) return
        db.beginTransaction()
        try {
            // Replace the projection wholesale: entries the engine evicted or expired must
            // disappear, and the snapshot is already capped to the hottest rows. One compiled
            // `INSERT OR REPLACE` for the whole snapshot, bound straight from the kernel bytes.
            db.delete(TABLE, null, null)
            db.compileStatement(INSERT_SQL).use { statement ->
                for (row in rows) {
                    statement.clearBindings()
                    bindRow(statement, row)
                    statement.executeInsert()
                }
            }
            db.setTransactionSuccessful()
        } catch (t: Throwable) {
            DbWriteHealth.warn(TAG, "Unable to mirror DNS cache", t)
        } finally {
            runCatching { db.endTransaction() }
        }
    }

    /// The kernel's row layout, bound in [INSERT_SQL] order.
    private fun bindRow(statement: SQLiteStatement, row: ByteArray) {
        val reader = LogPayload.Reader(row)
        statement.bindString(1, reader.string())
        statement.bindString(2, reader.string())
        statement.bindLong(3, reader.i32().toLong())
        statement.bindLong(4, reader.i32().toLong())
        statement.bindLong(5, reader.i64())
        statement.bindLong(6, reader.i64())
        statement.bindLong(7, reader.i64())
        statement.bindLong(8, reader.i64())
        statement.bindLong(9, reader.i64())
        // NOT NULL columns the Dart readers never touch: the projection has no wire bytes.
        statement.bindString(10, reader.string())
        statement.bindBlob(11, reader.blob())
        statement.bindLong(12, reader.i32().toLong())
    }

    private companion object {
        const val TAG = "DnsCacheMirror"
        const val TABLE = "dns_cache"

        const val INSERT_SQL = "INSERT OR REPLACE INTO dns_cache " +
            "(key, queryName, queryType, queryClass, createdAt, expiresAt, lastHitAt, hitCount, " +
            "originalTtlSeconds, ttlOffsets, response, responseSize) " +
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
    }
}
