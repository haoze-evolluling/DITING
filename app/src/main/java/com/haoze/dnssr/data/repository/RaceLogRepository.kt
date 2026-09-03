package com.haoze.dnssr.data.repository

import com.haoze.dnssr.data.RaceStats
import com.haoze.dnssr.data.RaceStatsRange
import com.haoze.dnssr.data.RaceStrategyStats
import com.haoze.dnssr.data.RaceWinnerStats
import com.haoze.dnssr.data.SmartSelectionStats
import com.haoze.dnssr.data.dao.RaceLogDao
import com.haoze.dnssr.ui.RaceModeStrategy
import com.haoze.dnssr.util.dayStartMillis

class RaceLogRepository(private val dao: RaceLogDao) {

    suspend fun stats(range: RaceStatsRange): RaceStats {
        val since = sinceMillis(range)
        return RaceStats(
            strategyStats = dao.strategyStats(since).map { row ->
                RaceStrategyStats(
                    strategy = row.strategy,
                    displayName = strategyDisplayName(row.strategy),
                    requests = row.requests,
                    successes = row.successes,
                    failures = row.failures,
                    avgElapsedMs = row.avgElapsedMs ?: 0.0,
                    fallbackUses = row.fallbackUses,
                    fallbackSuccesses = row.fallbackSuccesses,
                    primaryWins = row.primaryWins
                )
            }.sortedBy { it.strategy },
            winnerStats = dao.winnerStats(since).map { row ->
                RaceWinnerStats(
                    strategy = row.strategy,
                    providerId = row.providerId ?: "",
                    providerName = row.providerName ?: "未知服务商",
                    wins = row.wins,
                    avgWinnerElapsedMs = row.avgWinnerElapsedMs ?: 0.0
                )
            },
            smartSelectionStats = dao.smartSelectionStats(
                since = since,
                strategy = RaceModeStrategy.SMART_PREDICTION.storageValue
            ).map { row ->
                SmartSelectionStats(
                    providerId = row.providerId ?: "",
                    providerName = row.providerName ?: "未知服务商",
                    selectedCount = row.selectedCount,
                    selectedSuccesses = row.selectedSuccesses,
                    avgSelectedElapsedMs = row.avgSelectedElapsedMs ?: 0.0
                )
            }
        )
    }

    private fun sinceMillis(range: RaceStatsRange): Long {
        return when (range) {
            RaceStatsRange.TODAY -> dayStartMillis()
            RaceStatsRange.SEVEN_DAYS -> System.currentTimeMillis() - SEVEN_DAYS_MS
            RaceStatsRange.ALL -> 0L
        }
    }

    private fun strategyDisplayName(strategy: String): String {
        return RaceModeStrategy.fromStorageValue(strategy).displayName
    }

    private companion object {
        private const val SEVEN_DAYS_MS = 7L * 24L * 60L * 60L * 1000L
    }
}
