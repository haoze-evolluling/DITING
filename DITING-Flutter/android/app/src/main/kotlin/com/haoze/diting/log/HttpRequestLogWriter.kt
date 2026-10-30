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
class HttpRequestLogWriter(
    private val context: Context,
    private val databaseName: String,
    private val modeProvider: () -> String,
) {
    private val executor: ScheduledExecutorService =
        Executors.newSingleThreadScheduledExecutor { runnable ->
            Thread(runnable, "diting-http-log").apply { isDaemon = true }
        }
    private val lock = Any()
    private val pending = ArrayList<Row>(BATCH_SIZE)

    private val flushScheduled = AtomicBoolean(false)

    /// Backoff after a locked database; the pending rows stay queued meanwhile.
    private var backoffMs = 0L
    private var retryAtMs = 0L

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
        RequestStats.onHttp(outcome.ifBlank { "error" })
        val mode = modeProvider()
        if (mode == DnsLogWriter.MODE_OFF) return
        if (mode == DnsLogWriter.MODE_BLOCKED_AND_ERRORS && outcome in PASS_THROUGH_OUTCOMES) return

        var full = false
        synchronized(lock) {
            pending += Row(
                timestamp = System.currentTimeMillis(),
                packageName = packageName.ifBlank { "unknown" },
                authority = authority.ifBlank { null },
                protocol = protocol.ifBlank { "" },
                outcome = outcome.ifBlank { "error" },
                matchedRule = matchedRule.ifBlank { null },
            )
            full = pending.size >= BATCH_SIZE
        }
        if (full) submitFlush() else scheduleDelayedFlush()
    }

    /// Final flush, then stop. `closed` gates the entry points only; the flush runs after it is set
    fun close() {
        if (closed) return
        closed = true
        runCatching {
            // Explicit Runnable: `submit { }` is ambiguous with the Callable overload.
            executor.submit(Runnable { writeBatch() }).get(CLOSE_TIMEOUT_MS, TimeUnit.MILLISECONDS)
        }.onFailure { Log.w(TAG, "Final HTTP log flush did not complete", it) }
        executor.shutdown()
        runCatching { executor.awaitTermination(CLOSE_TIMEOUT_MS, TimeUnit.MILLISECONDS) }
        val left = synchronized(lock) {
            val remaining = pending.size
            pending.clear()
            remaining
        }
        DbWriteHealth.onDropped(left, DropReason.CLOSED, TABLE)
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
    private fun scheduleDelayedFlush() {
        if (closed || !flushScheduled.compareAndSet(false, true)) return
        try {
            executor.schedule(
                {
                    flushScheduled.set(false)
                    writeBatch()
                },
                FLUSH_INTERVAL_MS,
                TimeUnit.MILLISECONDS,
            )
        } catch (_: RejectedExecutionException) {
            flushScheduled.set(false)
        }
    }

    private fun writeBatch() {
        // Returned from the block, not a captured `val`: that form leans on callsInPlace.
        val batch = synchronized(lock) {
            if (pending.isEmpty()) return
            val copy = ArrayList(pending)
            pending.clear()
            copy
        }

        if (System.currentTimeMillis() < retryAtMs) {
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
                backoff()
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
                backoff()
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
                        row.bindTo(statement)
                        statement.executeInsert()
                    }
                }
                db.setTransactionSuccessful()
            } finally {
                db.endTransaction()
            }
            resetBackoff()
        } catch (t: Throwable) {
            DbWriteHealth.warn(TAG, "Unable to persist HTTP log batch", t)
            backoff()
            requeue(batch)
        }
    }

    private fun backoff() {
        synchronized(lock) {
            backoffMs = if (backoffMs <= 0L) MIN_BACKOFF_MS else minOf(backoffMs * 2, MAX_BACKOFF_MS)
            retryAtMs = System.currentTimeMillis() + backoffMs
        }
    }

    private fun resetBackoff() {
        synchronized(lock) {
            backoffMs = 0L
            retryAtMs = 0L
        }
    }

    private fun requeue(batch: List<Row>) {
        var overflow = 0
        var wasClosed = false
        synchronized(lock) {
            wasClosed = closed
            if (!wasClosed) {
                // Prepend so the buffer stays chronological.
                pending.addAll(0, batch)
                // A failing write must not grow the buffer without bound: drop the oldest rows.
                overflow = pending.size - MAX_PENDING_ROWS
                if (overflow > 0) pending.subList(0, overflow).clear()
            }
        }
        if (wasClosed) {
            // Nothing will flush again: count the tail instead of losing it silently.
            DbWriteHealth.onDropped(batch.size, DropReason.CLOSED, TABLE)
            return
        }
        DbWriteHealth.onDropped(overflow, DropReason.OVERFLOW, TABLE)
        // No later event may arrive to hit BATCH_SIZE, so re-arm the timer.
        scheduleDelayedFlush()
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
        const val BATCH_SIZE = 10
        const val FLUSH_INTERVAL_MS = 500L
        const val CLOSE_TIMEOUT_MS = 500L

        /// Large enough to ride out a 30 s backoff under heavy MITM traffic.
        const val MAX_PENDING_ROWS = 5_000

        const val INSERT_SQL = "INSERT OR IGNORE INTO http_request_log " +
            "(timestamp, packageName, authority, protocol, outcome, matchedRule, blockSubscriptionId) " +
            "VALUES (?, ?, ?, ?, ?, ?, NULL)"

        const val MIN_BACKOFF_MS = 2_000L
        const val MAX_BACKOFF_MS = 30_000L

        /// Outcomes hidden by the `blocked_and_errors` log mode
        val PASS_THROUGH_OUTCOMES = setOf("allowed", "passthrough")
    }
}
