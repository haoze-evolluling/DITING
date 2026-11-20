package com.haoze.diting.log

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.util.Log
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit

internal object LogRetention {
    private const val TAG = "LogRetention"

    private const val INTERVAL_MS = 60 * 60 * 1000L

    private const val INITIAL_DELAY_MS = 30 * 1000L

    private var executor: ScheduledExecutorService? = null

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

    @Synchronized
    fun stop() {
        executor?.shutdownNow()
        executor = null
    }

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

        val db = AppDatabase.writable(context, databaseName) ?: return 0
        var deleted = 0
        for (table in plan.tables) {
            if (!AppDatabase.hasTable(db, table)) continue
            deleted += pruneTable(db, table, plan.logCutoffMs, plan.batchRows)
        }
        if (includeHttpAndTraffic && AppDatabase.hasTable(db, plan.trafficTable)) {
            val cutoffDate = dayStringAt(plan.trafficCutoffMs)
            deleted += runCatching {
                db.delete(plan.trafficTable, "date < ?", arrayOf(cutoffDate))
            }.getOrDefault(0)
        }
        if (deleted > 0) Log.i(TAG, "pruned $deleted rows older than ${plan.logDays} d")
        return deleted
    }

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

    internal fun dayStringAt(millis: Long): String {
        val format = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US)
        return format.format(java.util.Date(millis))
    }

    internal class RetentionSettings(
        private val context: Context,
        private val prefsName: String,
    ) {
        fun logRetentionDaysOrNull(): Int? = read(prefsName, KEY_LOG_RETENTION_DAYS)

        fun trafficRetentionDaysOrNull(): Int? = read(PREFS_GLOBAL, KEY_TRAFFIC_RETENTION_DAYS)

        private fun read(prefsName: String, key: String): Int? = runCatching {
            val prefs = context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
            if (prefs.contains(key)) prefs.getInt(key, 0) else null
        }.getOrNull()
    }

    private const val PREFS_GLOBAL = "dns_vpn_prefs"
    private const val KEY_LOG_RETENTION_DAYS = "log_retention_days"
    private const val KEY_TRAFFIC_RETENTION_DAYS = "traffic_stats_retention_days"
}
