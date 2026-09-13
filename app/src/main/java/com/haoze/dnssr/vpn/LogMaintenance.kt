package com.haoze.dnssr.vpn

import com.haoze.dnssr.util.dayStringAt
import com.haoze.dnssr.data.AppDatabase
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Central log maintenance scheduler: periodic pruning and one-shot clearing
 * transactions for the 4 request-log types (DNS, HTTP, race, bootstrap).
 */
object LogMaintenance {
    private const val MAINTENANCE_INTERVAL_MS = 60 * 60 * 1000L // 1 hour
    private const val INITIAL_DELAY_MS = 30 * 1000L // first run 30s after service startup
    private const val DAY_MS = 24 * 60 * 60 * 1000L

    /**
     * Starts the periodic log retention pruning task in a background coroutine.
     */
    fun start(
        scope: CoroutineScope,
        database: AppDatabase,
        retentionDaysProvider: () -> Int
    ): Job {
        return scope.launch(Dispatchers.IO) {
            delay(INITIAL_DELAY_MS)
            while (isActive) {
                runCatching {
                    pruneExpiredLogs(database, retentionDaysProvider())
                }
                delay(MAINTENANCE_INTERVAL_MS)
            }
        }
    }

    /**
     * Prunes historical logs and app traffic data past the retention window.
     */
    suspend fun pruneExpiredLogs(database: AppDatabase, retentionDays: Int) {
        if (retentionDays <= 0) return
        val cutoff = System.currentTimeMillis() - retentionDays * DAY_MS
        val cutoffDate = dayStringAt(cutoff)
        withContext(Dispatchers.IO) {
            runCatching { database.dnsLogDao().deleteBefore(cutoff) }
            runCatching { database.httpRequestLogDao().deleteBefore(cutoff) }
            runCatching { database.raceLogDao().deleteBefore(cutoff) }
            runCatching { database.bootstrapLogDao().deleteBefore(cutoff) }
            runCatching { database.appTrafficDao().deleteOlderThan(cutoffDate) }
        }
    }

    /**
     * Clears all 4 log types in one operation.
     */
    suspend fun clearAllLogs(database: AppDatabase) {
        withContext(Dispatchers.IO) {
            runCatching { database.dnsLogDao().clearAll() }
            runCatching { database.httpRequestLogDao().clearAll() }
            runCatching { database.raceLogDao().clearAll() }
            runCatching { database.bootstrapLogDao().clearAll() }
        }
    }

    /**
     * Clears all app traffic history and in-memory statistics state.
     */
    suspend fun clearAllTrafficStats(database: AppDatabase) {
        withContext(Dispatchers.IO) {
            runCatching { com.haoze.dnssr.vpn.traffic.TrafficStatsManager.clearAllTrafficStats() }
            runCatching { database.appTrafficDao().clearAll() }
        }
    }
}
