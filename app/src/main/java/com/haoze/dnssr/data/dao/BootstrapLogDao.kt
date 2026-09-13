package com.haoze.dnssr.data.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.Query
import com.haoze.dnssr.data.entity.BootstrapLogEntity

@Dao
interface BootstrapLogDao {
    @Insert
    suspend fun insert(entity: BootstrapLogEntity)

    @Insert
    suspend fun insertAll(entities: List<BootstrapLogEntity>)

    @Query("DELETE FROM bootstrap_log WHERE timestamp < :before")
    suspend fun deleteBefore(before: Long)

    @Query("DELETE FROM bootstrap_log")
    suspend fun clearAll()

    @Query(
        """
        SELECT
            COUNT(*) AS attempts,
            COALESCE(SUM(CASE WHEN success = 1 THEN 1 ELSE 0 END), 0) AS successes,
            COALESCE(SUM(CASE WHEN success = 0 THEN 1 ELSE 0 END), 0) AS failures,
            AVG(elapsedMs) AS avgElapsedMs,
            COALESCE(SUM(CASE WHEN fallbackUsed = 1 THEN 1 ELSE 0 END), 0) AS fallbackUses
        FROM bootstrap_log
        WHERE timestamp >= :since
        """
    )
    suspend fun overallStats(since: Long): BootstrapOverallStatRow

    @Query(
        """
        SELECT
            ipId,
            MAX(ipName) AS ipName,
            MAX(ip) AS ip,
            COUNT(*) AS attempts,
            COALESCE(SUM(CASE WHEN success = 1 THEN 1 ELSE 0 END), 0) AS successes,
            COALESCE(SUM(CASE WHEN success = 0 THEN 1 ELSE 0 END), 0) AS failures,
            AVG(elapsedMs) AS avgElapsedMs,
            COALESCE(SUM(CASE WHEN fallbackUsed = 1 THEN 1 ELSE 0 END), 0) AS fallbackUses
        FROM bootstrap_log
        WHERE timestamp >= :since
        GROUP BY ipId
        ORDER BY attempts DESC
        """
    )
    suspend fun ipStats(since: Long): List<BootstrapIpStatRow>
}

data class BootstrapOverallStatRow(
    val attempts: Int,
    val successes: Int,
    val failures: Int,
    val avgElapsedMs: Double?,
    val fallbackUses: Int
)

data class BootstrapIpStatRow(
    val ipId: String,
    val ipName: String?,
    val ip: String?,
    val attempts: Int,
    val successes: Int,
    val failures: Int,
    val avgElapsedMs: Double?,
    val fallbackUses: Int
)
