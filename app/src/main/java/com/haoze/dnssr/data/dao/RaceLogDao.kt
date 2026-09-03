package com.haoze.dnssr.data.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.Query
import com.haoze.dnssr.data.entity.RaceLogEntity

@Dao
interface RaceLogDao {
    @Insert
    suspend fun insert(entity: RaceLogEntity)

    @Insert
    suspend fun insertAll(entities: List<RaceLogEntity>)

    @Query("DELETE FROM dns_race_log WHERE timestamp < :before")
    suspend fun deleteBefore(before: Long)

    @Query("DELETE FROM dns_race_log")
    suspend fun clearAll()

    @Query(
        """
        SELECT
            strategy,
            COUNT(*) AS requests,
            SUM(CASE WHEN success = 1 THEN 1 ELSE 0 END) AS successes,
            SUM(CASE WHEN success = 0 THEN 1 ELSE 0 END) AS failures,
            AVG(elapsedMs) AS avgElapsedMs,
            SUM(CASE WHEN fallbackUsed = 1 THEN 1 ELSE 0 END) AS fallbackUses,
            SUM(CASE WHEN fallbackSuccess = 1 THEN 1 ELSE 0 END) AS fallbackSuccesses,
            SUM(CASE WHEN selectedProviderId IS NOT NULL AND winnerProviderId = selectedProviderId AND success = 1 THEN 1 ELSE 0 END) AS primaryWins
        FROM dns_race_log
        WHERE timestamp >= :since
        GROUP BY strategy
        """
    )
    suspend fun strategyStats(since: Long): List<RaceStrategyStatRow>

    @Query(
        """
        SELECT
            strategy,
            winnerProviderId AS providerId,
            MAX(winnerProviderName) AS providerName,
            COUNT(*) AS wins,
            AVG(winnerElapsedMs) AS avgWinnerElapsedMs
        FROM dns_race_log
        WHERE timestamp >= :since
            AND success = 1
            AND winnerProviderId IS NOT NULL
        GROUP BY strategy, winnerProviderId
        ORDER BY wins DESC
        """
    )
    suspend fun winnerStats(since: Long): List<RaceWinnerStatRow>

    @Query(
        """
        SELECT
            selectedProviderId AS providerId,
            MAX(selectedProviderName) AS providerName,
            COUNT(*) AS selectedCount,
            SUM(CASE WHEN fallbackUsed = 0 AND winnerProviderId = selectedProviderId AND success = 1 THEN 1 ELSE 0 END) AS selectedSuccesses,
            AVG(selectedElapsedMs) AS avgSelectedElapsedMs
        FROM dns_race_log
        WHERE timestamp >= :since
            AND strategy = :strategy
            AND selectedProviderId IS NOT NULL
        GROUP BY selectedProviderId
        ORDER BY selectedCount DESC
        """
    )
    suspend fun smartSelectionStats(since: Long, strategy: String): List<SmartSelectionStatRow>
}

data class RaceStrategyStatRow(
    val strategy: String,
    val requests: Int,
    val successes: Int,
    val failures: Int,
    val avgElapsedMs: Double?,
    val fallbackUses: Int,
    val fallbackSuccesses: Int,
    val primaryWins: Int
)

data class RaceWinnerStatRow(
    val strategy: String,
    val providerId: String?,
    val providerName: String?,
    val wins: Int,
    val avgWinnerElapsedMs: Double?
)

data class SmartSelectionStatRow(
    val providerId: String?,
    val providerName: String?,
    val selectedCount: Int,
    val selectedSuccesses: Int,
    val avgSelectedElapsedMs: Double?
)
