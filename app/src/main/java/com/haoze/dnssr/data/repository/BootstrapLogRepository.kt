package com.haoze.dnssr.data.repository

import android.content.Context
import com.haoze.dnssr.data.BootstrapIpStats
import com.haoze.dnssr.data.BootstrapOverallStats
import com.haoze.dnssr.data.BootstrapStats
import com.haoze.dnssr.data.BootstrapStatsRange
import com.haoze.dnssr.data.dao.BootstrapLogDao
import com.haoze.dnssr.ui.AppSettings
import com.haoze.dnssr.util.dayStartMillis
import com.haoze.dnssr.vpn.BootstrapHealthStore

class BootstrapLogRepository(
    private val context: Context,
    private val dao: BootstrapLogDao
) {
    suspend fun stats(range: BootstrapStatsRange): BootstrapStats {
        val since = sinceMillis(range)
        val overallRow = dao.overallStats(since)
        val healthByIp = BootstrapHealthStore.loadAll(context)
        val entriesById = AppSettings.loadBootstrapIpEntries(context).associateBy { it.id }

        return BootstrapStats(
            overall = BootstrapOverallStats(
                attempts = overallRow.attempts,
                successes = overallRow.successes,
                failures = overallRow.failures,
                avgElapsedMs = overallRow.avgElapsedMs ?: 0.0,
                fallbackUses = overallRow.fallbackUses
            ),
            ipStats = dao.ipStats(since).map { row ->
                val health = healthByIp[row.ipId]
                val entry = entriesById[row.ipId]
                BootstrapIpStats(
                    ipId = row.ipId,
                    ipName = entry?.name ?: row.ipName ?: "未知 Bootstrap IP",
                    ip = entry?.ip ?: row.ip ?: "",
                    attempts = row.attempts,
                    successes = row.successes,
                    failures = row.failures,
                    avgElapsedMs = row.avgElapsedMs ?: 0.0,
                    fallbackUses = row.fallbackUses,
                    predictionWeight = health?.predictionWeight ?: 1.0,
                    ewmaMs = health?.ewmaMs ?: 0.0,
                    consecutiveFailures = health?.consecutiveFailures ?: 0,
                    cooldownUntil = health?.cooldownUntil ?: 0L
                )
            }
        )
    }

    private fun sinceMillis(range: BootstrapStatsRange): Long {
        return when (range) {
            BootstrapStatsRange.TODAY -> dayStartMillis()
            BootstrapStatsRange.SEVEN_DAYS -> System.currentTimeMillis() - SEVEN_DAYS_MS
            BootstrapStatsRange.ALL -> 0L
        }
    }

    private companion object {
        private const val SEVEN_DAYS_MS = 7L * 24L * 60L * 60L * 1000L
    }
}
