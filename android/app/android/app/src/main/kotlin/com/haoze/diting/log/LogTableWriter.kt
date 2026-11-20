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

internal class LogTableWriter(
    context: Context,
    private val databaseName: String,
    private val table: String,
    threadName: String,
    private val insertSql: String,
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

    fun submit(row: ByteArray) = submitAll(listOf(row))

    fun submitAll(rows: List<ByteArray>) {
        if (rows.isEmpty()) return
        val decision = LogNative.queueSubmitMany(queue, rows)
        if (!decision.accepted) return
        DbWriteHealth.onDropped(decision.overflow, DropReason.OVERFLOW, table)
        schedule(decision.flushDelayMs)
    }

    fun submitDnsBatch(stats: Long, mode: String, packed: ByteArray) {
        applyOutcome(LogNative.dnsBatchSubmit(stats, queue, mode, packed))
    }

    fun submitKernelBatch(
        packed: ByteArray,
        submit: (queue: Long, packed: ByteArray) -> LogBatchOutcome,
    ) {
        if (packed.size <= Int.SIZE_BYTES) return
        applyOutcome(submit(queue, packed))
    }

    private fun applyOutcome(outcome: LogBatchOutcome) {
        when (outcome) {
            LogBatchOutcome.Closed, LogBatchOutcome.Hidden -> return
            is LogBatchOutcome.Enqueued -> {
                DbWriteHealth.onDropped(outcome.overflow, DropReason.OVERFLOW, table)
                schedule(outcome.flushDelayMs)
            }
        }
    }

    fun close() {
        synchronized(lock) {
            if (closed) return
            closed = true
        }
        LogNative.queueMarkClosed(queue)
        executor.shutdownNow()
        drainQueue()
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
            synchronized(lock) { scheduled = false }
        }
    }

    private fun drain() {
        synchronized(lock) { scheduled = false }
        drainQueue()
        if (LogNative.queuePendingLen(queue) > 0) {
            schedule(LogNative.queueRetryWait(queue))
        }
    }

    private fun drainQueue() {
        while (true) {
            val batch = LogNative.queueTake(queue) ?: return
            if (!write(batch)) return
        }
    }

    private fun write(rows: List<ByteArray>): Boolean {
        val db = when (val open = AppDatabase.open(appContext, databaseName)) {
            is AppDatabase.Open.Ready -> open.db
            AppDatabase.Open.Absent -> {
                DbWriteHealth.onDropped(rows.size, DropReason.NO_DATABASE, table)
                return true
            }
            is AppDatabase.Open.Unavailable -> {
                requeue(rows)
                LogNative.queueBackoff(queue)
                return false
            }
        }
        if (LogNative.queueMissingLatched(queue)) {
            DbWriteHealth.onDropped(rows.size, DropReason.TABLE_MISSING, table)
            return true
        }
        when (AppDatabase.tableState(db, table)) {
            AppDatabase.TableState.PRESENT -> Unit
            AppDatabase.TableState.MISSING -> {
                LogNative.queueLatchMissing(queue)
                DbWriteHealth.warn(TAG, "$databaseName has no $table; dropping rows")
                DbWriteHealth.onDropped(rows.size, DropReason.TABLE_MISSING, table)
                return true
            }
            AppDatabase.TableState.ERROR -> {
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

    private fun requeue(rows: List<ByteArray>) {
        val overflow = LogNative.queueRequeue(queue, rows)
        DbWriteHealth.onDropped(overflow, DropReason.OVERFLOW, table)
    }

    private companion object {
        const val TAG = "LogTableWriter"
    }
}

internal object LogTableWriters {
    private val writers = ConcurrentHashMap<String, LogTableWriter>()

    fun of(
        context: Context,
        databaseName: String,
        table: String,
        threadName: String,
        insertSql: String,
        bind: (SQLiteStatement, ByteArray) -> Unit,
    ): LogTableWriter = writers.computeIfAbsent("$databaseName/$table") {
        LogTableWriter(context, databaseName, table, threadName, insertSql, bind)
    }

    fun closeAll() {
        val snapshot = writers.values.toList()
        writers.clear()
        snapshot.forEach { runCatching { it.close() } }
    }
}
