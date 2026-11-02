package com.haoze.diting.log

import android.content.Context
import android.database.sqlite.SQLiteStatement
import android.util.Log
import com.haoze.diting.log.DbWriteHealth.DropReason
import org.json.JSONArray
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit

/// Writes per-UID traffic into `app_traffic_daily`, batched every 15s or 1MB; deltas are ADDED.
class TrafficIngest(
    private val context: Context,
    private val databaseName: String,
    private val uidPackageCache: UidPackageCache,
) {
    private val executor: ScheduledExecutorService =
        Executors.newSingleThreadScheduledExecutor { runnable ->
            Thread(runnable, "diting-traffic-ingest").apply { isDaemon = true }
        }
    private val lock = Any()

    /// date -> (packageName -> delta); keyed by date so a retried write is not mis-dated
    private val buckets = LinkedHashMap<String, LinkedHashMap<String, Delta>>()
    private var bufferedBytes = 0L

    @Volatile
    private var closed = false

    /// Backoff after a locked/unopenable database, so a stuck lock is retried instead of hammered
    /// on every 1MB threshold crossing (the 2026-10-27 export showed a 2.5s retry storm).
    private var backoffMs = 0L
    private var retryAtMs = 0L

    private val flushTask = executor.scheduleWithFixedDelay(
        { writeBuffered() },
        FLUSH_INTERVAL_MS,
        FLUSH_INTERVAL_MS,
        TimeUnit.MILLISECONDS,
    )

    fun onTick(jsonDeltas: String) {
        if (jsonDeltas.isBlank() || closed) return
        val array = runCatching { JSONArray(jsonDeltas) }.getOrNull() ?: return
        if (array.length() == 0) return

        var overThreshold = false
        var droppedPackages = 0
        var tickTx = 0L
        var tickRx = 0L
        synchronized(lock) {
            val date = todayString()
            val bucket = buckets.getOrPut(date) { LinkedHashMap() }
            for (i in 0 until array.length()) {
                val obj = array.optJSONObject(i) ?: continue
                val uid = obj.optInt("uid", -1)
                val tx = obj.optLong("tx", 0L)
                val rx = obj.optLong("rx", 0L)
                if (uid <= 0 || (tx <= 0 && rx <= 0)) continue
                // Device-wide rates: every delta counts, including package-less rows.
                tickTx += tx
                tickRx += rx
                val packageName = uidPackageCache.packageForUid(uid)
                if (packageName.isBlank()) {
                    // No package name yet; the next tick retries with a warm cache.
                    continue
                }
                val delta = bucket.getOrPut(packageName) { Delta() }
                delta.tx += tx
                delta.rx += rx
                bufferedBytes += tx + rx
            }
            overThreshold = bufferedBytes > FLUSH_THRESHOLD_BYTES
            // Past the cap the oldest date bucket is dropped, so a failing write cannot leak.
            if (bufferedBytes > MAX_BUFFERED_BYTES && buckets.size > 1) {
                val oldest = buckets.keys.first()
                val dropped = buckets.remove(oldest) ?: LinkedHashMap()
                bufferedBytes -= dropped.values.sumOf { it.tx + it.rx }
                Log.w(TAG, "Traffic buffer over ${MAX_BUFFERED_BYTES}B; dropped $oldest")
                droppedPackages = dropped.size
            }
        }
        DbWriteHealth.onDropped(droppedPackages, DropReason.OVERFLOW, TABLE)
        // Outside the lock: the monitor only stores two numbers.
        TrafficRateMonitor.onTick(tickTx, tickRx)
        if (overThreshold) submitFlush()
    }

    /// Force-writes the buffer and stops the executor, so the 15s timer cannot drop the tail
    fun close() {
        if (closed) return
        closed = true
        flushTask.cancel(false)
        runCatching {
            // Explicit Runnable: `submit { }` is ambiguous with the Callable overload.
            // Force: the tail must be attempted even while the backoff window is open.
            executor.submit(Runnable { writeBuffered(force = true) }).get(CLOSE_TIMEOUT_MS, TimeUnit.MILLISECONDS)
        }.onFailure { Log.w(TAG, "Final traffic flush did not complete", it) }
        executor.shutdown()
        runCatching { executor.awaitTermination(CLOSE_TIMEOUT_MS, TimeUnit.MILLISECONDS) }
        val left = synchronized(lock) {
            val remaining = buckets.values.sumOf { it.size }
            buckets.clear()
            bufferedBytes = 0L
            remaining
        }
        DbWriteHealth.onDropped(left, DropReason.CLOSED, TABLE)
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
        // Returned from the block, not assigned to a captured `val`: that relies on callsInPlace.
        val snapshot = synchronized(lock) {
            // `closed` must NOT gate this method: close() sets it before the final flush.
            if (buckets.isEmpty()) return
            val copy = buckets.map { it.key to it.value }
            buckets.clear()
            bufferedBytes = 0L
            copy
        }

        if (!force && System.currentTimeMillis() < retryAtMs) {
            // Still backing off: keep the deltas buffered instead of losing them.
            requeue(snapshot)
            return
        }

        val db = when (val opened = LegacyDb.open(context, databaseName)) {
            is LegacyDb.Open.Ready -> opened.db
            LegacyDb.Open.Absent -> {
                // Fresh install or server mode: retrying would buffer every tick forever.
                DbWriteHealth.onDropped(snapshot.sumOf { it.second.size }, DropReason.NO_DATABASE, TABLE)
                return
            }
            is LegacyDb.Open.Unavailable -> {
                requeue(snapshot)
                backoff()
                return
            }
        }

        // Express has no app_traffic_daily: a wrong database must be a no-op.
        when (LegacyDb.tableState(db, TABLE)) {
            LegacyDb.TableState.PRESENT -> Unit
            LegacyDb.TableState.MISSING -> {
                DbWriteHealth.warn(TAG, "$databaseName has no $TABLE; dropping traffic buffer")
                DbWriteHealth.onDropped(snapshot.sumOf { it.second.size }, DropReason.TABLE_MISSING, TABLE)
                return
            }
            LegacyDb.TableState.ERROR -> {
                // A failed lookup is a busy database, not a missing table: keep the deltas.
                requeue(snapshot)
                backoff()
                return
            }
        }

        val failed = ArrayList<Pair<String, LinkedHashMap<String, Delta>>>(snapshot.size)
        val now = System.currentTimeMillis()
        for ((date, bucket) in snapshot) {
            try {
                db.beginTransaction()
                try {
                    // Compiled once per date instead of twice per package.
                    db.compileStatement(UPDATE_SQL).use { update ->
                        db.compileStatement(INSERT_SQL).use { insert ->
                            for ((packageName, delta) in bucket) {
                                if (delta.tx <= 0 && delta.rx <= 0) continue
                                applyDelta(update, insert, date, packageName, delta, now)
                            }
                        }
                    }
                    db.setTransactionSuccessful()
                } finally {
                    db.endTransaction()
                }
            } catch (t: Throwable) {
                DbWriteHealth.warn(TAG, "Unable to persist traffic batch for $date", t)
                failed.add(date to bucket)
            }
        }
        if (failed.isEmpty()) resetBackoff() else backoff()
        if (failed.isNotEmpty()) requeue(failed)
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

    /// Adds both counters, keeps a stored non-empty `app_name`. ON CONFLICT needs API 30
    private fun applyDelta(
        update: SQLiteStatement,
        insert: SQLiteStatement,
        date: String,
        packageName: String,
        delta: Delta,
        now: Long,
    ) {
        val appName = appLabelFor(packageName)
        update.clearBindings()
        update.bindString(1, appName)
        update.bindString(2, appName)
        update.bindLong(3, delta.tx)
        update.bindLong(4, delta.rx)
        update.bindLong(5, now)
        update.bindString(6, date)
        update.bindString(7, packageName)
        if (update.executeUpdateDelete() == 0) {
            insert.clearBindings()
            insert.bindString(1, date)
            insert.bindString(2, packageName)
            insert.bindString(3, appName)
            insert.bindLong(4, delta.tx)
            insert.bindLong(5, delta.rx)
            insert.bindLong(6, now)
            insert.executeInsert()
        }
    }

    /// Puts an unwritten batch back under its original date for the next flush
    private fun requeue(failed: List<Pair<String, LinkedHashMap<String, Delta>>>) {
        synchronized(lock) {
            if (closed) {
                // Nothing will flush again: count the tail instead of losing it silently.
                DbWriteHealth.onDropped(failed.sumOf { it.second.size }, DropReason.CLOSED, TABLE)
                return
            }
            for ((date, bucket) in failed) {
                val target = buckets.getOrPut(date) { LinkedHashMap() }
                for ((packageName, delta) in bucket) {
                    val merged = target.getOrPut(packageName) { Delta() }
                    merged.tx += delta.tx
                    merged.rx += delta.rx
                    bufferedBytes += delta.tx + delta.rx
                }
            }
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

    private class Delta(var tx: Long = 0L, var rx: Long = 0L)

    private companion object {
        const val TAG = "TrafficIngest"
        const val TABLE = "app_traffic_daily"
        const val FLUSH_INTERVAL_MS = 15_000L
        const val FLUSH_THRESHOLD_BYTES = 1024L * 1024L
        const val CLOSE_TIMEOUT_MS = 500L

        const val MAX_BUFFERED_BYTES = 8L * 1024L * 1024L

        const val MIN_BACKOFF_MS = 2_000L
        const val MAX_BACKOFF_MS = 60_000L

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
