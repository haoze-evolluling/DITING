package com.haoze.diting.log

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.util.Log
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit

/// Hourly sweep of the request-log tables, native so it runs with no Flutter UI alive.
internal object LogRetention {
    private const val TAG = "LogRetention"

    private const val INTERVAL_MS = 60 * 60 * 1000L

    /// Not zero: the first sweep competes with the tunnel handshake for disk
    private const val INITIAL_DELAY_MS = 30 * 1000L

    private const val DAY_MS = 24 * 60 * 60 * 1000L

    /// Rows per `DELETE`; keeps a sweep from holding the write lock for minutes.
    private const val BATCH_ROWS = 5_000

    private const val DEFAULT_LOG_RETENTION_DAYS = 7
    private const val DEFAULT_TRAFFIC_RETENTION_DAYS = 30

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
        val logDays = settings.logRetentionDays()
        if (logDays <= 0) return 0
        val cutoff = System.currentTimeMillis() - logDays * DAY_MS

        val db = LegacyDb.writable(context, databaseName) ?: return 0
        var deleted = 0
        for (table in PRUNED_LOG_TABLES) {
            if (!LegacyDb.hasTable(db, table)) continue
            deleted += pruneTable(db, table, cutoff)
        }
        if (includeHttpAndTraffic && LegacyDb.hasTable(db, "app_traffic_daily")) {
            val trafficDays = settings.trafficRetentionDays()
            if (trafficDays > 0) {
                // `date` is `yyyy-MM-dd`, so the cutoff is a date: millis would delete all.
                val cutoffDate = dayStringAt(
                    System.currentTimeMillis() - trafficDays * DAY_MS,
                )
                deleted += runCatching {
                    db.delete("app_traffic_daily", "date < ?", arrayOf(cutoffDate))
                }.getOrDefault(0)
            }
        }
        if (deleted > 0) Log.i(TAG, "pruned $deleted rows older than $logDays d")
        return deleted
    }

    /// Deletes in bounded batches: one `DELETE` over millions of rows would hold the write lock for
    /// minutes, which is exactly what starved the log writers on 2.1.7.
    private fun pruneTable(db: SQLiteDatabase, table: String, cutoff: Long): Int {
        var total = 0
        while (true) {
            val batch = runCatching {
                db.delete(
                    table,
                    "id IN (SELECT id FROM $table WHERE timestamp < ? LIMIT $BATCH_ROWS)",
                    arrayOf(cutoff.toString()),
                )
            }.getOrDefault(0)
            total += batch
            if (batch < BATCH_ROWS) return total
        }
    }

    /// Tables carrying a `timestamp` column in epoch millis
    private val PRUNED_LOG_TABLES = arrayOf(
        "dns_log",
        "http_request_log",
        "dns_race_log",
        "bootstrap_log",
    )

    /// `yyyy-MM-dd` in the device zone, the key format TrafficIngest writes
    internal fun dayStringAt(millis: Long): String {
        val format = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US)
        return format.format(java.util.Date(millis))
    }

    internal class RetentionSettings(
        private val context: Context,
        private val prefsName: String,
    ) {
        fun logRetentionDays(): Int = runCatching {
            // Dataset-scoped: normal and express keep separate values.
            context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
                .getInt(KEY_LOG_RETENTION_DAYS, DEFAULT_LOG_RETENTION_DAYS)
        }.getOrDefault(DEFAULT_LOG_RETENTION_DAYS).coerceIn(1, 30)

        fun trafficRetentionDays(): Int = runCatching {
            // The traffic window is global: those tables exist in diting_database only.
            context.getSharedPreferences(PREFS_GLOBAL, Context.MODE_PRIVATE)
                .getInt(KEY_TRAFFIC_RETENTION_DAYS, DEFAULT_TRAFFIC_RETENTION_DAYS)
        }.getOrDefault(DEFAULT_TRAFFIC_RETENTION_DAYS).coerceIn(1, 90)
    }

    private const val PREFS_GLOBAL = "dns_vpn_prefs"
    private const val KEY_LOG_RETENTION_DAYS = "log_retention_days"
    private const val KEY_TRAFFIC_RETENTION_DAYS = "traffic_stats_retention_days"
}
