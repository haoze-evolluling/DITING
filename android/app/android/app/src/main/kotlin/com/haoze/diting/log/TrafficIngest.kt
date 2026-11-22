package com.haoze.diting.log

import android.content.Context
import android.database.sqlite.SQLiteStatement
import android.util.Log
import com.haoze.diting.log.DbWriteHealth.DropReason
import java.nio.ByteBuffer
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit

class TrafficIngest(
    private val context: Context,
    private val databaseName: String,
) {
    private val executor: ScheduledExecutorService =
        Executors.newSingleThreadScheduledExecutor { runnable ->
            Thread(runnable, "diting-traffic-ingest").apply { isDaemon = true }
        }
    private val traffic: Long = LogNative.trafficNew()

    @Volatile
    private var closed = false

    private val flushTask = executor.scheduleWithFixedDelay(
        { writeBuffered() },
        FLUSH_INTERVAL_MS,
        FLUSH_INTERVAL_MS,
        TimeUnit.MILLISECONDS,
    )

    fun onTick(rows: ByteArray) {
        if (closed || rows.size < Int.SIZE_BYTES) return
        val count = ByteBuffer.wrap(rows, 0, Int.SIZE_BYTES).int
        if (count == 0) {
            TrafficRateMonitor.onTick(0, 0)
            return
        }

        val date = todayString().toByteArray(Charsets.UTF_8)
        val packed = ByteArray(Int.SIZE_BYTES + date.size + rows.size)
        ByteBuffer.wrap(packed).putInt(0, date.size)
        date.copyInto(packed, Int.SIZE_BYTES)
        rows.copyInto(packed, Int.SIZE_BYTES + date.size)

        val outcome = LogNative.trafficOnTick(traffic, packed)
        if (outcome.droppedDate != null) {
            Log.w(TAG, "Traffic buffer overflowed; dropped ${outcome.droppedDate}")
        }
        DbWriteHealth.onDropped(outcome.droppedPackages, DropReason.OVERFLOW, TABLE)
        TrafficRateMonitor.onTick(outcome.tickTx, outcome.tickRx)
        if (outcome.flush) submitFlush()
    }

    fun close() {
        if (closed) return
        closed = true
        flushTask.cancel(false)
        runCatching {
            executor.submit(Runnable { writeBuffered(force = true) })
                .get(CLOSE_TIMEOUT_MS, TimeUnit.MILLISECONDS)
        }.onFailure { Log.w(TAG, "Final traffic flush did not complete", it) }
        executor.shutdown()
        runCatching { executor.awaitTermination(CLOSE_TIMEOUT_MS, TimeUnit.MILLISECONDS) }
        val left = LogNative.trafficClear(traffic)
        DbWriteHealth.onDropped(left, DropReason.CLOSED, TABLE)
        LogNative.trafficFree(traffic)
    }

    private fun submitFlush() {
        if (closed) return
        try {
            executor.execute { writeBuffered() }
        } catch (_: RejectedExecutionException) {
        }
    }

    private fun writeBuffered(force: Boolean = false) {
        val snapshot = LogNative.trafficTake(traffic)
        if (snapshot.isEmpty()) return

        if (!force && LogNative.trafficInBackoff(traffic)) {
            LogNative.trafficRequeue(traffic, snapshot)
            return
        }

        val db = when (val opened = AppDatabase.open(context, databaseName)) {
            is AppDatabase.Open.Ready -> opened.db
            AppDatabase.Open.Absent -> {
                DbWriteHealth.onDropped(rowCount(snapshot), DropReason.NO_DATABASE, TABLE)
                return
            }
            is AppDatabase.Open.Unavailable -> {
                requeue(snapshot)
                LogNative.trafficBackoff(traffic)
                return
            }
        }

        when (AppDatabase.tableState(db, TABLE)) {
            AppDatabase.TableState.PRESENT -> Unit
            AppDatabase.TableState.MISSING -> {
                DbWriteHealth.warn(TAG, "$databaseName has no $TABLE; dropping traffic buffer")
                DbWriteHealth.onDropped(rowCount(snapshot), DropReason.TABLE_MISSING, TABLE)
                return
            }
            AppDatabase.TableState.ERROR -> {
                requeue(snapshot)
                LogNative.trafficBackoff(traffic)
                return
            }
        }

        val failed = ArrayList<LogTrafficBatch>(snapshot.size)
        val now = System.currentTimeMillis()
        for (batch in snapshot) {
            try {
                db.beginTransaction()
                try {
                    db.compileStatement(UPDATE_SQL).use { update ->
                        db.compileStatement(INSERT_SQL).use { insert ->
                            for (row in batch.rows) {
                                if (row.tx <= 0 && row.rx <= 0) continue
                                applyDelta(update, insert, batch.date, row, now)
                            }
                        }
                    }
                    db.setTransactionSuccessful()
                } finally {
                    db.endTransaction()
                }
            } catch (t: Throwable) {
                DbWriteHealth.warn(TAG, "Unable to persist traffic batch for ${batch.date}", t)
                failed += batch
            }
        }
        if (failed.isEmpty()) {
            LogNative.trafficResetBackoff(traffic)
        } else {
            LogNative.trafficBackoff(traffic)
            requeue(failed)
        }
    }

    private fun requeue(batches: List<LogTrafficBatch>) {
        if (closed) {
            DbWriteHealth.onDropped(rowCount(batches), DropReason.CLOSED, TABLE)
            return
        }
        LogNative.trafficRequeue(traffic, batches)
    }

    private fun rowCount(batches: List<LogTrafficBatch>): Int =
        batches.sumOf { it.rows.size }

    private fun applyDelta(
        update: SQLiteStatement,
        insert: SQLiteStatement,
        date: String,
        row: LogTrafficRow,
        now: Long,
    ) {
        val appName = appLabelFor(row.packageName)
        update.clearBindings()
        update.bindString(1, appName)
        update.bindString(2, appName)
        update.bindLong(3, row.tx)
        update.bindLong(4, row.rx)
        update.bindLong(5, now)
        update.bindString(6, date)
        update.bindString(7, row.packageName)
        if (update.executeUpdateDelete() == 0) {
            insert.clearBindings()
            insert.bindString(1, date)
            insert.bindString(2, row.packageName)
            insert.bindString(3, appName)
            insert.bindLong(4, row.tx)
            insert.bindLong(5, row.rx)
            insert.bindLong(6, now)
            insert.executeInsert()
        }
    }

    private val labels = HashMap<String, String>()

    private fun appLabelFor(packageName: String): String {
        labels[packageName]?.let { return it }
        val label = runCatching {
            val pm = context.packageManager
            pm.getApplicationInfo(packageName, 0).loadLabel(pm).toString()
        }.getOrDefault("")
        if (label.isNotEmpty()) labels[packageName] = label
        return label
    }

    private fun todayString(): String =
        SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())

    private companion object {
        const val TAG = "TrafficIngest"
        const val TABLE = "app_traffic_daily"
        const val FLUSH_INTERVAL_MS = 15_000L
        const val CLOSE_TIMEOUT_MS = 500L

        const val UPDATE_SQL = """
            UPDATE app_traffic_daily SET
                app_name = CASE WHEN ? != '' THEN ? ELSE app_name END,
                tx_bytes = tx_bytes + ?,
                rx_bytes = rx_bytes + ?,
                updated_at = ?
            WHERE date = ? AND package_name = ?
        """

        const val INSERT_SQL = """
            INSERT INTO app_traffic_daily (date, package_name, app_name, tx_bytes, rx_bytes, updated_at)
            VALUES (?, ?, ?, ?, ?, ?)
        """
    }
}
