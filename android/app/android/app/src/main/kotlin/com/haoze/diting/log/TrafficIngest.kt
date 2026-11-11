package com.haoze.diting.log

import android.content.Context
import android.database.sqlite.SQLiteStatement
import android.util.Log
import com.haoze.diting.log.DbWriteHealth.DropReason
import org.json.JSONArray
import java.io.DataOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit

/// Writes per-UID traffic into `app_traffic_daily`, batched every 15s or 1MB; deltas are ADDED.
///
/// The buckets, the flush threshold, the overflow drop, the requeue of a failed write and the
/// 2 s → 60 s backoff live in the log kernel (`rust/diting-log-core/src/traffic.rs`); the JSON
/// decode, the UID → package lookup, the SQL and the timers stay here.
class TrafficIngest(
    private val context: Context,
    private val databaseName: String,
    private val uidPackageCache: UidPackageCache,
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

    fun onTick(jsonDeltas: String) {
        if (jsonDeltas.isBlank() || closed) return
        val array = runCatching { JSONArray(jsonDeltas) }.getOrNull() ?: return
        if (array.length() == 0) {
            // An idle engine still ticks every second with `[]`: feed the rate clock a zero tick so
            // a stalled link decays to 0 B/s instead of freezing its last value. No row, no DB.
            TrafficRateMonitor.onTick(0, 0)
            return
        }

        val rows = collect(array)
        val packed = LogPayload.pack { out ->
            LogPayload.writeString(out, todayString())
            out.writeInt(rows.size)
            for (row in rows) writeRow(out, row)
        }
        val outcome = LogNative.trafficOnTick(traffic, packed)
        if (outcome.droppedDate != null) {
            Log.w(TAG, "Traffic buffer overflowed; dropped ${outcome.droppedDate}")
        }
        DbWriteHealth.onDropped(outcome.droppedPackages, DropReason.OVERFLOW, TABLE)
        // Outside any lock: the monitor only stores two numbers.
        TrafficRateMonitor.onTick(outcome.tickTx, outcome.tickRx)
        if (outcome.flush) submitFlush()
    }

    /// The rows the kernel will bucket: the same cheap filter, so a row that cannot count never
    /// reaches `PackageManager`. The kernel re-checks it, this only avoids the binder call.
    private fun collect(array: JSONArray): List<Delta> {
        val rows = ArrayList<Delta>(array.length())
        for (index in 0 until array.length()) {
            val obj = array.optJSONObject(index) ?: continue
            val uid = obj.optInt("uid", -1)
            val tx = obj.optLong("tx", 0L)
            val rx = obj.optLong("rx", 0L)
            if (uid <= 0 || (tx <= 0 && rx <= 0)) continue
            rows += Delta(uid, tx, rx, uidPackageCache.packageForUid(uid))
        }
        return rows
    }

    private fun writeRow(out: DataOutputStream, row: Delta) {
        out.writeInt(row.uid)
        out.writeLong(row.tx)
        out.writeLong(row.rx)
        LogPayload.writeString(out, row.packageName)
    }

    /// Force-writes the buffer and stops the executor, so the 15s timer cannot drop the tail
    fun close() {
        if (closed) return
        closed = true
        flushTask.cancel(false)
        runCatching {
            // Explicit Runnable: `submit { }` is ambiguous with the Callable overload.
            // Force: the tail must be attempted even while the backoff window is open.
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
            // Shut down already: close() is committing the tail.
        }
    }

    private fun writeBuffered(force: Boolean = false) {
        // `closed` must NOT gate this method: close() sets it before the final flush.
        val snapshot = LogNative.trafficTake(traffic)
        if (snapshot.isEmpty()) return

        if (!force && LogNative.trafficInBackoff(traffic)) {
            // Still backing off: keep the deltas buffered instead of losing them.
            LogNative.trafficRequeue(traffic, snapshot)
            return
        }

        val db = when (val opened = LegacyDb.open(context, databaseName)) {
            is LegacyDb.Open.Ready -> opened.db
            LegacyDb.Open.Absent -> {
                // Fresh install or server mode: retrying would buffer every tick forever.
                DbWriteHealth.onDropped(rowCount(snapshot), DropReason.NO_DATABASE, TABLE)
                return
            }
            is LegacyDb.Open.Unavailable -> {
                requeue(snapshot)
                LogNative.trafficBackoff(traffic)
                return
            }
        }

        // Express has no app_traffic_daily: a wrong database must be a no-op.
        when (LegacyDb.tableState(db, TABLE)) {
            LegacyDb.TableState.PRESENT -> Unit
            LegacyDb.TableState.MISSING -> {
                DbWriteHealth.warn(TAG, "$databaseName has no $TABLE; dropping traffic buffer")
                DbWriteHealth.onDropped(rowCount(snapshot), DropReason.TABLE_MISSING, TABLE)
                return
            }
            LegacyDb.TableState.ERROR -> {
                // A failed lookup is a busy database, not a missing table: keep the deltas.
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
                    // Compiled once per date instead of twice per package.
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
        if (failed.isEmpty()) LogNative.trafficResetBackoff(traffic) else LogNative.trafficBackoff(traffic)
        if (failed.isNotEmpty()) requeue(failed)
    }

    /// Puts unwritten deltas back under their original date for the next flush
    private fun requeue(batches: List<LogTrafficBatch>) {
        if (closed) {
            // Nothing will flush again: count the tail instead of losing it silently.
            DbWriteHealth.onDropped(rowCount(batches), DropReason.CLOSED, TABLE)
            return
        }
        LogNative.trafficRequeue(traffic, batches)
    }

    private fun rowCount(batches: List<LogTrafficBatch>): Int =
        batches.sumOf { it.rows.size }

    /// Adds both counters, keeps a stored non-empty `app_name`. ON CONFLICT needs API 30
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

    /// PackageManager label, cached per session: it is a binder call per package per flush.
    /// Failures are not cached, so an app installed mid-session still gets its name.
    private val labels = HashMap<String, String>()

    /// Only called on the executor thread, so [labels] needs no lock.
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

    /// One row of the engine's traffic tick, after the UID → package lookup.
    private data class Delta(
        val uid: Int,
        val tx: Long,
        val rx: Long,
        val packageName: String,
    )

    private companion object {
        const val TAG = "TrafficIngest"
        const val TABLE = "app_traffic_daily"
        const val FLUSH_INTERVAL_MS = 15_000L
        const val CLOSE_TIMEOUT_MS = 500L

        /// UPSERT as UPDATE + INSERT. The CASE keeps a non-empty stored name, so it is bound twice
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
