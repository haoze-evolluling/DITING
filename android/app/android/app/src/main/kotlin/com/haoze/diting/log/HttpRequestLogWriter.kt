package com.haoze.diting.log

import android.content.Context
import android.database.sqlite.SQLiteStatement
import android.util.Log
import com.haoze.diting.log.DbWriteHealth.DropReason
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/// `http_request_log` writer, batched 10 rows / 500ms: the callback runs on the TLS relay path.
///
/// The row, the mode filter and the counters live in the log kernel
/// (`rust/diting-log-core/src/row.rs`), as does the batch policy (10 rows, 5k queued, 2 s → 30 s
/// backoff, `queue::HTTP`). The timer, the SQL and the `LegacyDb` handling stay here.
class HttpRequestLogWriter(
    private val context: Context,
    private val databaseName: String,
    private val modeProvider: () -> String,
) {
    private val executor: ScheduledExecutorService =
        Executors.newSingleThreadScheduledExecutor { runnable ->
            Thread(runnable, "diting-http-log").apply { isDaemon = true }
        }
    private val queue: Long = LogNative.queueNew(LogNative.QUEUE_HTTP)

    private val flushScheduled = AtomicBoolean(false)

    @Volatile
    private var closed = false

    /// The DNS log mode governs HTTP rows too, so off and blocked_and_errors keep their meaning
    fun onEvent(
        packageName: String,
        authority: String,
        protocol: String,
        outcome: String,
        matchedRule: String,
    ) {
        if (closed) return
        val packed = LogPayload.pack { out ->
            LogPayload.writeString(out, packageName)
            LogPayload.writeString(out, authority)
            LogPayload.writeString(out, protocol)
            LogPayload.writeString(out, outcome)
            LogPayload.writeString(out, matchedRule)
        }
        // Null when the log mode hides the event; the counters were fed either way.
        val row = LogNative.httpEvent(RequestStats.kernel, modeProvider(), packed) ?: return
        val decision = LogNative.queueSubmit(queue, row)
        if (!decision.accepted) return
        DbWriteHealth.onDropped(decision.overflow, DropReason.OVERFLOW, TABLE)
        if (decision.batchFull) submitFlush() else scheduleDelayedFlush(decision.flushDelayMs)
    }

    /// Final flush, then stop. `closed` gates the entry points only; the flush runs after it is set
    fun close() {
        if (closed) return
        closed = true
        LogNative.queueMarkClosed(queue)
        runCatching {
            // Explicit Runnable: `submit { }` is ambiguous with the Callable overload.
            executor.submit(Runnable { writeBatch() }).get(CLOSE_TIMEOUT_MS, TimeUnit.MILLISECONDS)
        }.onFailure { Log.w(TAG, "Final HTTP log flush did not complete", it) }
        executor.shutdown()
        runCatching { executor.awaitTermination(CLOSE_TIMEOUT_MS, TimeUnit.MILLISECONDS) }
        val left = LogNative.queueClose(queue)
        DbWriteHealth.onDropped(left, DropReason.CLOSED, TABLE)
        LogNative.queueFree(queue)
    }

    private fun submitFlush() {
        if (closed) return
        try {
            executor.execute { writeBatch() }
        } catch (_: RejectedExecutionException) {
            // Already shut down; close() commits the tail.
        }
    }

    /// Arms one 500ms timer for a burst's first row and reuses it, so ten events are one write
    private fun scheduleDelayedFlush(delayMs: Long = FLUSH_INTERVAL_MS) {
        if (closed || !flushScheduled.compareAndSet(false, true)) return
        try {
            executor.schedule(
                {
                    flushScheduled.set(false)
                    writeBatch()
                },
                delayMs,
                TimeUnit.MILLISECONDS,
            )
        } catch (_: RejectedExecutionException) {
            flushScheduled.set(false)
        }
    }

    private fun writeBatch() {
        val batch = LogNative.queueTake(queue) ?: return
        if (LogNative.queueInBackoff(queue)) {
            // Still backing off: keep the rows queued instead of dropping them.
            requeue(batch)
            return
        }

        val db = when (val opened = LegacyDb.open(context, databaseName)) {
            is LegacyDb.Open.Ready -> opened.db
            LegacyDb.Open.Absent -> {
                DbWriteHealth.onDropped(batch.size, DropReason.NO_DATABASE, TABLE)
                return
            }
            is LegacyDb.Open.Unavailable -> {
                requeue(batch)
                LogNative.queueBackoff(queue)
                return
            }
        }

        // Guard anyway: an INSERT into a missing table would throw per batch.
        when (LegacyDb.tableState(db, TABLE)) {
            LegacyDb.TableState.PRESENT -> Unit
            LegacyDb.TableState.MISSING -> {
                DbWriteHealth.warn(TAG, "$databaseName has no $TABLE; dropping HTTP rows")
                DbWriteHealth.onDropped(batch.size, DropReason.TABLE_MISSING, TABLE)
                return
            }
            LegacyDb.TableState.ERROR -> {
                // A failed lookup is a busy database, not a missing table: keep the rows.
                LogNative.queueBackoff(queue)
                requeue(batch)
                return
            }
        }
        try {
            db.beginTransaction()
            try {
                // One compiled statement per batch instead of one SQL build per row.
                db.compileStatement(INSERT_SQL).use { statement ->
                    for (row in batch) {
                        decode(row).bindTo(statement)
                        statement.executeInsert()
                    }
                }
                db.setTransactionSuccessful()
            } finally {
                db.endTransaction()
            }
            LogNative.queueResetBackoff(queue)
        } catch (t: Throwable) {
            DbWriteHealth.warn(TAG, "Unable to persist HTTP log batch", t)
            LogNative.queueBackoff(queue)
            requeue(batch)
        }
    }

    private fun requeue(batch: List<ByteArray>) {
        if (closed) {
            // Nothing will flush again: count the tail instead of losing it silently.
            DbWriteHealth.onDropped(batch.size, DropReason.CLOSED, TABLE)
            return
        }
        val overflow = LogNative.queueRequeue(queue, batch)
        DbWriteHealth.onDropped(overflow, DropReason.OVERFLOW, TABLE)
        // No later event may arrive to hit the batch size, so re-arm the timer.
        scheduleDelayedFlush()
    }

    /// The kernel's row layout, unpacked for [INSERT_SQL].
    private fun decode(row: ByteArray): Row {
        val reader = LogPayload.Reader(row)
        return Row(
            timestamp = reader.i64(),
            packageName = reader.string(),
            authority = reader.optionalString(),
            protocol = reader.string(),
            outcome = reader.string(),
            matchedRule = reader.optionalString(),
        )
    }

    private data class Row(
        val timestamp: Long,
        val packageName: String,
        val authority: String?,
        val protocol: String,
        val outcome: String,
        val matchedRule: String?,
    ) {
        /// Binds in [INSERT_SQL] order; `blockSubscriptionId` stays NULL there, it needs a rule
        /// snapshot this port does not keep.
        fun bindTo(statement: SQLiteStatement) {
            statement.clearBindings()
            statement.bindLong(1, timestamp)
            statement.bindString(2, packageName)
            if (authority == null) statement.bindNull(3) else statement.bindString(3, authority)
            statement.bindString(4, protocol)
            statement.bindString(5, outcome)
            if (matchedRule == null) statement.bindNull(6) else statement.bindString(6, matchedRule)
        }
    }

    private companion object {
        const val TAG = "HttpRequestLogWriter"
        const val TABLE = "http_request_log"
        const val FLUSH_INTERVAL_MS = 500L
        const val CLOSE_TIMEOUT_MS = 500L

        const val INSERT_SQL = "INSERT OR IGNORE INTO http_request_log " +
            "(timestamp, packageName, authority, protocol, outcome, matchedRule, blockSubscriptionId) " +
            "VALUES (?, ?, ?, ?, ?, ?, NULL)"
    }
}
