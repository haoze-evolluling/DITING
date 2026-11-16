package com.haoze.diting.log

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteStatement
import com.haoze.diting.log.DbWriteHealth.DropReason
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit

/// Bounded, single-threaded writer for one log table.
///
/// Engine callbacks must not touch the disk: a write that waits on `busy_timeout` stalls the DNS
/// hot path, which is why 2.1.7 opened a connection per event there. The queue and its policy (200
/// rows or 1 s, 10k queued, 500 per transaction, 1 s → 30 s backoff) live in the log kernel
/// (`rust/diting-log-core/src/queue.rs`); this class keeps the timer, the SQL, the compiled
/// statement and every `LegacyDb` decision.
internal class LogTableWriter(
    context: Context,
    private val databaseName: String,
    private val table: String,
    threadName: String,
    /// The complete `INSERT OR IGNORE` for this table, compiled once per transaction.
    private val insertSql: String,
    /// Binds one packed kernel row straight into the compiled statement. No `ContentValues` is
    /// built: a DNS batch used to allocate one hash map per row just to read it back out.
    private val bind: (SQLiteStatement, ByteArray) -> Unit,
) {
    private val appContext = context.applicationContext
    private val lock = Any()
    private val queue: Long = LogNative.queueNew(LogNative.QUEUE_LOG_TABLE)

    private val executor: ScheduledExecutorService =
        Executors.newSingleThreadScheduledExecutor { runnable ->
            Thread(runnable, threadName).apply { isDaemon = true }
        }

    private var scheduled = false
    private var closed = false

    /// One row for the low-volume tables (bootstrap and race); the DNS batch uses [submitAll].
    fun submit(row: ByteArray) = submitAll(listOf(row))

    /// Cheap enough for a per-batch callback: one JNI call packs, appends and arms a timer.
    fun submitAll(rows: List<ByteArray>) {
        if (rows.isEmpty()) return
        val decision = LogNative.queueSubmitMany(queue, rows)
        if (!decision.accepted) return
        // Counted outside any lock: the health counter may log.
        DbWriteHealth.onDropped(decision.overflow, DropReason.OVERFLOW, table)
        schedule(decision.flushDelayMs)
    }

    /// One DNS batch: the kernel counts, classifies and enqueues it in a single crossing, so the
    /// rows never come back to Kotlin for a re-pack. Only the timer and the overflow counter are
    /// left here, exactly like [submitAll].
    fun submitDnsBatch(stats: Long, mode: String, packed: ByteArray) {
        when (val outcome = LogNative.dnsBatchSubmit(stats, queue, mode, packed)) {
            LogBatchOutcome.Closed, LogBatchOutcome.Hidden -> return
            is LogBatchOutcome.Enqueued -> {
                DbWriteHealth.onDropped(outcome.overflow, DropReason.OVERFLOW, table)
                schedule(outcome.flushDelayMs)
            }
        }
    }

    /// Final flush on the caller's thread (the engine is already stopped), then stops the timer.
    fun close() {
        synchronized(lock) {
            if (closed) return
            closed = true
        }
        // Rows may still arrive between the flag and the drain; the kernel drops them.
        LogNative.queueMarkClosed(queue)
        executor.shutdownNow()
        // One pass that ignores the backoff window: nothing retries after this.
        while (true) {
            val batch = LogNative.queueTake(queue) ?: break
            // A failed write requeued its rows; they are counted below.
            if (!write(batch)) break
        }
        val left = LogNative.queueClose(queue)
        DbWriteHealth.onDropped(left, DropReason.CLOSED, table)
        LogNative.queueFree(queue)
    }

    private fun schedule(delayMs: Long) {
        synchronized(lock) {
            if (closed || scheduled) return
            scheduled = true
        }
        try {
            executor.schedule({ drain() }, delayMs, TimeUnit.MILLISECONDS)
        } catch (_: RejectedExecutionException) {
            // Already shut down: close() commits the tail.
            synchronized(lock) { scheduled = false }
        }
    }

    private fun drain() {
        synchronized(lock) { scheduled = false }
        while (true) {
            val batch = LogNative.queueTake(queue) ?: return
            if (!write(batch)) break
        }
        if (LogNative.queuePendingLen(queue) > 0) {
            schedule(LogNative.queueRetryWait(queue))
        }
    }

    /// True when the rows are either written or permanently unpersistable (so no requeue).
    private fun write(rows: List<ByteArray>): Boolean {
        val db = when (val open = LegacyDb.open(appContext, databaseName)) {
            is LegacyDb.Open.Ready -> open.db
            LegacyDb.Open.Absent -> {
                // No database yet on a fresh install; Dart creates the schema. Counted, not silent.
                DbWriteHealth.onDropped(rows.size, DropReason.NO_DATABASE, table)
                return true
            }
            is LegacyDb.Open.Unavailable -> {
                requeue(rows)
                LogNative.queueBackoff(queue)
                return false
            }
        }
        if (LogNative.queueMissingLatched(queue)) {
            DbWriteHealth.onDropped(rows.size, DropReason.TABLE_MISSING, table)
            return true
        }
        when (LegacyDb.tableState(db, table)) {
            LegacyDb.TableState.PRESENT -> Unit
            LegacyDb.TableState.MISSING -> {
                LogNative.queueLatchMissing(queue)
                DbWriteHealth.warn(TAG, "$databaseName has no $table; dropping rows")
                DbWriteHealth.onDropped(rows.size, DropReason.TABLE_MISSING, table)
                return true
            }
            LegacyDb.TableState.ERROR -> {
                // Locked or I/O: the table is almost certainly there, so keep the rows.
                requeue(rows)
                LogNative.queueBackoff(queue)
                return false
            }
        }
        return try {
            insertAll(db, rows)
            LogNative.queueResetBackoff(queue)
            true
        } catch (t: Throwable) {
            DbWriteHealth.warn(TAG, "unable to persist ${rows.size} rows into $table", t)
            requeue(rows)
            LogNative.queueBackoff(queue)
            false
        }
    }

    /// One compiled `INSERT OR IGNORE` per transaction, bound row by row from the kernel's bytes.
    ///
    /// The previous version materialised a `ContentValues` (a hash map plus boxed numbers) for
    /// every row before it could bind anything. The SQL is now fixed per table, since every row
    /// of these four streams has the same columns anyway.
    private fun insertAll(db: SQLiteDatabase, rows: List<ByteArray>) {
        db.beginTransaction()
        try {
            db.compileStatement(insertSql).use { statement ->
                for (row in rows) {
                    statement.clearBindings()
                    bind(statement, row)
                    statement.executeInsert()
                }
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    /// Puts an unwritten batch back in front so the table stays chronological.
    private fun requeue(rows: List<ByteArray>) {
        val overflow = LogNative.queueRequeue(queue, rows)
        DbWriteHealth.onDropped(overflow, DropReason.OVERFLOW, table)
    }

    private companion object {
        const val TAG = "LogTableWriter"
    }
}

/// One [LogTableWriter] per (database, table), so the engine callbacks of both data planes share
/// the same queue instead of each creating a thread that opens its own connection.
internal object LogTableWriters {
    private val writers = ConcurrentHashMap<String, LogTableWriter>()

    fun of(
        context: Context,
        databaseName: String,
        table: String,
        threadName: String,
        insertSql: String,
        bind: (SQLiteStatement, ByteArray) -> Unit,
    // computeIfAbsent, not getOrPut: two racing callbacks must not each start a writer thread.
    ): LogTableWriter = writers.computeIfAbsent("$databaseName/$table") {
        LogTableWriter(context, databaseName, table, threadName, insertSql, bind)
    }

    /// Flushes and stops every queue; called when the data plane closes.
    fun closeAll() {
        val snapshot = writers.values.toList()
        writers.clear()
        snapshot.forEach { runCatching { it.close() } }
    }
}
