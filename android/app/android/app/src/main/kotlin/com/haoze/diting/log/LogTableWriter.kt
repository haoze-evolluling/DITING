package com.haoze.diting.log

import android.content.ContentValues
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
/// hot path, which is why 2.1.7 opened a connection per event there. Rows are queued instead,
/// written in one transaction per chunk through one compiled statement, and kept while the
/// database is unavailable — retried with an exponential backoff rather than dropped.
internal class LogTableWriter(
    context: Context,
    private val databaseName: String,
    private val table: String,
    threadName: String,
    private val maxPending: Int = MAX_PENDING_ROWS,
) {
    private val appContext = context.applicationContext
    private val lock = Any()
    private val pending = ArrayDeque<ContentValues>()

    private val executor: ScheduledExecutorService =
        Executors.newSingleThreadScheduledExecutor { runnable ->
            Thread(runnable, threadName).apply { isDaemon = true }
        }

    private var scheduled = false
    private var closed = false
    private var backoffMs = 0L
    private var retryAtMs = 0L

    /// Until when a confirmed-missing table drops rows without asking again. Not permanent: 2.1.9
    /// latched this forever, so one failed lookup cost the whole session's logs.
    private var missingUntilMs = 0L

    /// Cheap enough for a per-query callback: it only appends and arms a timer.
    fun submit(values: ContentValues) {
        var overflow = 0
        var batchFull = false
        synchronized(lock) {
            if (closed) return
            pending.addLast(values)
            // A stuck database must not grow the heap without bound: drop the oldest rows.
            while (pending.size > maxPending) {
                pending.removeFirst()
                overflow++
            }
            batchFull = pending.size >= BATCH_SIZE
        }
        // Counted outside the lock: the health counter may log.
        DbWriteHealth.onDropped(overflow, DropReason.OVERFLOW, table)
        if (batchFull) schedule(0L) else schedule(FLUSH_INTERVAL_MS)
    }

    /// Final flush on the caller's thread (the engine is already stopped), then stops the timer.
    fun close() {
        synchronized(lock) {
            if (closed) return
            closed = true
        }
        executor.shutdownNow()
        // One pass that ignores the backoff window: nothing retries after this.
        while (true) {
            val batch = takeBatch() ?: break
            // A failed write requeued its rows; they are counted below.
            if (!write(batch)) break
        }
        val left = synchronized(lock) {
            val remaining = pending.size
            pending.clear()
            remaining
        }
        DbWriteHealth.onDropped(left, DropReason.CLOSED, table)
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
            val batch = takeBatch() ?: return
            if (!write(batch)) break
        }
        if (hasPending()) {
            val wait = synchronized(lock) { maxOf(0L, retryAtMs - System.currentTimeMillis()) }
            schedule(wait)
        }
    }

    /// At most [MAX_ROWS_PER_TRANSACTION] rows, so one commit never holds the write lock long
    /// enough to stall the Dart side's own writes.
    private fun takeBatch(): List<ContentValues>? = synchronized(lock) {
        if (pending.isEmpty()) return null
        val count = minOf(pending.size, MAX_ROWS_PER_TRANSACTION)
        val copy = ArrayList<ContentValues>(count)
        repeat(count) { copy.add(pending.removeFirst()) }
        copy
    }

    private fun hasPending(): Boolean = synchronized(lock) { pending.isNotEmpty() }

    /// True when the rows are either written or permanently unpersistable (so no requeue).
    private fun write(batch: List<ContentValues>): Boolean {
        val db = when (val open = LegacyDb.open(appContext, databaseName)) {
            is LegacyDb.Open.Ready -> open.db
            LegacyDb.Open.Absent -> {
                // No database yet on a fresh install; Dart creates the schema. Counted, not silent.
                DbWriteHealth.onDropped(batch.size, DropReason.NO_DATABASE, table)
                return true
            }
            is LegacyDb.Open.Unavailable -> {
                requeue(batch)
                backoff()
                return false
            }
        }
        if (System.currentTimeMillis() < missingUntilMs) {
            DbWriteHealth.onDropped(batch.size, DropReason.TABLE_MISSING, table)
            return true
        }
        when (LegacyDb.tableState(db, table)) {
            LegacyDb.TableState.PRESENT -> Unit
            LegacyDb.TableState.MISSING -> {
                missingUntilMs = System.currentTimeMillis() + MISSING_RECHECK_MS
                DbWriteHealth.warn("LogTableWriter", "$databaseName has no $table; dropping rows")
                DbWriteHealth.onDropped(batch.size, DropReason.TABLE_MISSING, table)
                return true
            }
            LegacyDb.TableState.ERROR -> {
                // Locked or I/O: the table is almost certainly there, so keep the rows.
                requeue(batch)
                backoff()
                return false
            }
        }
        return try {
            insertAll(db, batch)
            resetBackoff()
            true
        } catch (t: Throwable) {
            DbWriteHealth.warn("LogTableWriter", "unable to persist ${batch.size} rows into $table", t)
            requeue(batch)
            backoff()
            false
        }
    }

    /// One compiled `INSERT OR IGNORE` per transaction. `insertWithOnConflict` rebuilt and
    /// recompiled the SQL for every row, which dominated the write time of a DNS batch.
    private fun insertAll(db: SQLiteDatabase, batch: List<ContentValues>) {
        val columns = batch.first().keySet().sorted()
        val sql = buildString {
            append("INSERT OR IGNORE INTO ").append(table).append(" (")
            columns.joinTo(this, ", ")
            append(") VALUES (")
            columns.indices.joinTo(this, ", ") { "?" }
            append(")")
        }
        db.beginTransaction()
        try {
            db.compileStatement(sql).use { statement ->
                for (values in batch) {
                    if (values.size() == columns.size && values.keySet().containsAll(columns)) {
                        statement.bindRow(columns, values)
                        statement.executeInsert()
                    } else {
                        // A row with another column set; rare, so the slow path is fine.
                        db.insertWithOnConflict(table, null, values, SQLiteDatabase.CONFLICT_IGNORE)
                    }
                }
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    private fun SQLiteStatement.bindRow(columns: List<String>, values: ContentValues) {
        clearBindings()
        for ((index, column) in columns.withIndex()) {
            val position = index + 1
            when (val value = values.get(column)) {
                null -> bindNull(position)
                is String -> bindString(position, value)
                is Long -> bindLong(position, value)
                is Int -> bindLong(position, value.toLong())
                is Short -> bindLong(position, value.toLong())
                is Byte -> bindLong(position, value.toLong())
                is Boolean -> bindLong(position, if (value) 1L else 0L)
                is Double -> bindDouble(position, value)
                is Float -> bindDouble(position, value.toDouble())
                is ByteArray -> bindBlob(position, value)
                else -> bindString(position, value.toString())
            }
        }
    }

    /// Puts an unwritten batch back in front so the table stays chronological.
    private fun requeue(batch: List<ContentValues>) {
        var overflow = 0
        synchronized(lock) {
            for (index in batch.indices.reversed()) {
                pending.addFirst(batch[index])
            }
            while (pending.size > maxPending) {
                pending.removeFirst()
                overflow++
            }
        }
        DbWriteHealth.onDropped(overflow, DropReason.OVERFLOW, table)
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

    private companion object {
        /// Rows that trigger an immediate flush; below it the timer batches them.
        const val BATCH_SIZE = 200
        const val FLUSH_INTERVAL_MS = 1_000L
        const val MAX_ROWS_PER_TRANSACTION = 500

        /// 500 rows were under a minute of DNS + connection logs, so a single 60 s backoff
        /// already overflowed. 10k rows of a few hundred bytes each stay within a few MB.
        const val MAX_PENDING_ROWS = 10_000
        const val MIN_BACKOFF_MS = 1_000L
        const val MAX_BACKOFF_MS = 30_000L
        const val MISSING_RECHECK_MS = 30_000L
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
    // computeIfAbsent, not getOrPut: two racing callbacks must not each start a writer thread.
    ): LogTableWriter = writers.computeIfAbsent("$databaseName/$table") {
        LogTableWriter(context, databaseName, table, threadName)
    }

    /// Flushes and stops every queue; called when the data plane closes.
    fun closeAll() {
        val snapshot = writers.values.toList()
        writers.clear()
        snapshot.forEach { runCatching { it.close() } }
    }
}
