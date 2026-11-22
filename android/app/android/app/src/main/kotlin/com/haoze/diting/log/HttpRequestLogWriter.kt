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

    fun onEvents(rows: ByteArray) {
        if (closed) return
        when (val outcome = LogNative.httpEvents(RequestStats.kernel, queue, modeProvider(), rows)) {
            LogBatchOutcome.Closed, LogBatchOutcome.Hidden -> return
            is LogBatchOutcome.Enqueued -> {
                DbWriteHealth.onDropped(outcome.overflow, DropReason.OVERFLOW, TABLE)
                if (outcome.batchFull) submitFlush() else scheduleDelayedFlush(outcome.flushDelayMs)
            }
        }
    }

    fun close() {
        if (closed) return
        closed = true
        LogNative.queueMarkClosed(queue)
        runCatching {
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
        }
    }

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
            requeue(batch)
            return
        }

        val db = when (val opened = AppDatabase.open(context, databaseName)) {
            is AppDatabase.Open.Ready -> opened.db
            AppDatabase.Open.Absent -> {
                DbWriteHealth.onDropped(batch.size, DropReason.NO_DATABASE, TABLE)
                return
            }
            is AppDatabase.Open.Unavailable -> {
                requeue(batch)
                LogNative.queueBackoff(queue)
                return
            }
        }

        when (AppDatabase.tableState(db, TABLE)) {
            AppDatabase.TableState.PRESENT -> Unit
            AppDatabase.TableState.MISSING -> {
                DbWriteHealth.warn(TAG, "$databaseName has no $TABLE; dropping HTTP rows")
                DbWriteHealth.onDropped(batch.size, DropReason.TABLE_MISSING, TABLE)
                return
            }
            AppDatabase.TableState.ERROR -> {
                LogNative.queueBackoff(queue)
                requeue(batch)
                return
            }
        }
        try {
            db.beginTransaction()
            try {
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
            DbWriteHealth.onDropped(batch.size, DropReason.CLOSED, TABLE)
            return
        }
        val overflow = LogNative.queueRequeue(queue, batch)
        DbWriteHealth.onDropped(overflow, DropReason.OVERFLOW, TABLE)
        scheduleDelayedFlush()
    }

    private fun decode(row: ByteArray): Row {
        val reader = LogPayload.Reader(row)
        return Row(
            timestamp = reader.i64(),
            packageName = reader.string(),
            authority = reader.optionalString(),
            protocol = reader.string(),
            outcome = reader.string(),
            matchedRule = reader.optionalString(),
            blockSubscriptionId = reader.optionalLong(),
        )
    }

    private data class Row(
        val timestamp: Long,
        val packageName: String,
        val authority: String?,
        val protocol: String,
        val outcome: String,
        val matchedRule: String?,
        val blockSubscriptionId: Long?,
    ) {
        fun bindTo(statement: SQLiteStatement) {
            statement.clearBindings()
            statement.bindLong(1, timestamp)
            statement.bindString(2, packageName)
            if (authority == null) statement.bindNull(3) else statement.bindString(3, authority)
            statement.bindString(4, protocol)
            statement.bindString(5, outcome)
            if (matchedRule == null) statement.bindNull(6) else statement.bindString(6, matchedRule)
            if (blockSubscriptionId == null) statement.bindNull(7)
            else statement.bindLong(7, blockSubscriptionId)
        }
    }

    private companion object {
        const val TAG = "HttpRequestLogWriter"
        const val TABLE = "http_request_log"
        const val FLUSH_INTERVAL_MS = 500L
        const val CLOSE_TIMEOUT_MS = 500L

        const val INSERT_SQL = "INSERT OR IGNORE INTO http_request_log " +
            "(timestamp, packageName, authority, protocol, outcome, matchedRule, blockSubscriptionId) " +
            "VALUES (?, ?, ?, ?, ?, ?, ?)"
    }
}
