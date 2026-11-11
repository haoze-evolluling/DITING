package com.haoze.diting.log

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.util.Log
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit

/// Hourly sweep of the request-log tables, native so it runs with no Flutter UI alive.
///
/// The windows, their bounds, the table list and the batch size live in the log kernel
/// (`rust/diting-log-core/src/retention.rs`); the preferences, the `DELETE` statements and the
/// `yyyy-MM-dd` formatting stay here.
internal object LogRetention {
    private const val TAG = "LogRetention"

    private const val INTERVAL_MS = 60 * 60 * 1000L

    /// Not zero: the first sweep competes with the tunnel handshake for disk
    private const val INITIAL_DELAY_MS = 30 * 1000L

    private var executor: ScheduledExecutorService? = null

    /// Starts the hourly sweep; no-op when one already runs
    @Synchronized
    fun start(
        context: Context,
        databaseName: String,
        prefsName: String,
        includeHttpAndTraffic: Boolean,
    ) {
        if (executor != null) return
        val appContext = context.applicationContext
        val scheduler = Executors.newSingleThreadScheduledExecutor { runnable ->
            Thread(runnable, "diting-log-retention").apply { isDaemon = true }
        }
        executor = scheduler
        scheduler.scheduleWithFixedDelay(
            {
                runCatching {
                    prune(
                        appContext,
                        databaseName = databaseName,
                        prefsName = prefsName,
                        includeHttpAndTraffic = includeHttpAndTraffic,
                    )
                }.onFailure { Log.w(TAG, "retention sweep failed", it) }
            },
            INITIAL_DELAY_MS,
            INTERVAL_MS,
            TimeUnit.MILLISECONDS,
        )
        Log.i(TAG, "retention sweep scheduled for $databaseName ($prefsName)")
    }

    /// Stops the sweep. Safe to call when it was never started
    @Synchronized
    fun stop() {
        executor?.shutdownNow()
        executor = null
    }

    /// Deletes rows outside the configured windows; a missing table must not stop the others
    fun prune(
        context: Context,
        databaseName: String,
        prefsName: String,
        includeHttpAndTraffic: Boolean,
    ): Int {
        val settings = RetentionSettings(context, prefsName)
        val plan = LogNative.retentionPlan(
            logDays = settings.logRetentionDaysOrNull(),
            trafficDays = settings.trafficRetentionDaysOrNull(),
            nowMs = System.currentTimeMillis(),
        )

        val db = LegacyDb.writable(context, databaseName) ?: return 0
        var deleted = 0
        for (table in plan.tables) {
            if (!LegacyDb.hasTable(db, table)) continue
            deleted += pruneTable(db, table, plan.logCutoffMs, plan.batchRows)
        }
        if (includeHttpAndTraffic && LegacyDb.hasTable(db, plan.trafficTable)) {
            // `date` is `yyyy-MM-dd`, so the cutoff is a date: millis would delete all.
            val cutoffDate = dayStringAt(plan.trafficCutoffMs)
            deleted += runCatching {
                db.delete(plan.trafficTable, "date < ?", arrayOf(cutoffDate))
            }.getOrDefault(0)
        }
        if (deleted > 0) Log.i(TAG, "pruned $deleted rows older than ${plan.logDays} d")
        return deleted
    }

    /// Deletes in bounded batches: one `DELETE` over millions of rows would hold the write lock for
    /// minutes, which is exactly what starved the log writers on 2.1.7.
    private fun pruneTable(
        db: SQLiteDatabase,
        table: String,
        cutoff: Long,
        batchRows: Long,
    ): Int {
        var total = 0
        while (true) {
            val batch = runCatching {
                db.delete(
                    table,
                    "id IN (SELECT id FROM $table WHERE timestamp < ? LIMIT $batchRows)",
                    arrayOf(cutoff.toString()),
                )
            }.getOrDefault(0)
            total += batch
            if (batch < batchRows) return total
        }
    }

    /// `yyyy-MM-dd` in the device zone, the key format TrafficIngest writes
    internal fun dayStringAt(millis: Long): String {
        val format = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US)
        return format.format(java.util.Date(millis))
    }

    internal class RetentionSettings(
        private val context: Context,
        private val prefsName: String,
    ) {
        /// The stored value, or null when it was never written or the store threw: the kernel owns
        /// the default and the bounds, so an absent preference is not spelled again here.
        fun logRetentionDaysOrNull(): Int? = read(prefsName, KEY_LOG_RETENTION_DAYS)

        /// The traffic window is global: those tables exist in diting_database only.
        fun trafficRetentionDaysOrNull(): Int? = read(PREFS_GLOBAL, KEY_TRAFFIC_RETENTION_DAYS)

        private fun read(prefsName: String, key: String): Int? = runCatching {
            // Dataset-scoped: normal and express keep separate log windows.
            val prefs = context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
            if (prefs.contains(key)) prefs.getInt(key, 0) else null
        }.getOrNull()
    }

    private const val PREFS_GLOBAL = "dns_vpn_prefs"
    private const val KEY_LOG_RETENTION_DAYS = "log_retention_days"
    private const val KEY_TRAFFIC_RETENTION_DAYS = "traffic_stats_retention_days"
}
