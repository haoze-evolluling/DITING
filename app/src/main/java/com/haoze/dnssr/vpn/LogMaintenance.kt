package com.haoze.dnssr.vpn

import com.haoze.dnssr.data.AppDatabase
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * 统一日志维护调度器，负责 4 类请求日志（DNS、HTTP、竞速、Bootstrap）的周期清理与一键清空事务。
 */
object LogMaintenance {
    private const val MAINTENANCE_INTERVAL_MS = 60 * 60 * 1000L // 1 小时
    private const val INITIAL_DELAY_MS = 30 * 1000L // 服务启动后 30 秒首次执行
    private const val DAY_MS = 24 * 60 * 60 * 1000L

    /**
     * 在后台协程中启动定期日志保留周期清理任务。
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
     * 统一清理超过保留期限的历史日志与应用流量数据。
     */
    suspend fun pruneExpiredLogs(database: AppDatabase, retentionDays: Int) {
        if (retentionDays <= 0) return
        val cutoff = System.currentTimeMillis() - retentionDays * DAY_MS
        val cutoffDate = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US).format(java.util.Date(cutoff))
        withContext(Dispatchers.IO) {
            runCatching { database.dnsLogDao().deleteBefore(cutoff) }
            runCatching { database.httpRequestLogDao().deleteBefore(cutoff) }
            runCatching { database.raceLogDao().deleteBefore(cutoff) }
            runCatching { database.bootstrapLogDao().deleteBefore(cutoff) }
            runCatching { database.appTrafficDao().deleteOlderThan(cutoffDate) }
        }
    }

    /**
     * 统一清空所有 4 类日志。
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
     * 清空全部应用流量历史记录。
     */
    suspend fun clearAllTrafficStats(database: AppDatabase) {
        withContext(Dispatchers.IO) {
            runCatching { database.appTrafficDao().clearAll() }
        }
    }
}
