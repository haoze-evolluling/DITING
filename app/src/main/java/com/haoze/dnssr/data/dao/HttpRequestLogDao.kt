package com.haoze.dnssr.data.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.Query
import com.haoze.dnssr.data.entity.HttpRequestLogEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface HttpRequestLogDao {
    @Insert
    suspend fun insertAll(entities: List<HttpRequestLogEntity>)

    @Query("SELECT * FROM http_request_log ORDER BY timestamp DESC LIMIT :limit")
    fun observeRecent(limit: Int = 50): Flow<List<HttpRequestLogEntity>>

    @Query("SELECT * FROM http_request_log ORDER BY timestamp DESC LIMIT :limit")
    suspend fun recent(limit: Int): List<HttpRequestLogEntity>

    @Query("SELECT outcome, COUNT(*) AS count FROM http_request_log WHERE timestamp >= :since GROUP BY outcome")
    suspend fun dailyStats(since: Long): List<HttpDailyStatRow>

    @Query("SELECT COUNT(*) FROM http_request_log WHERE timestamp >= :since")
    suspend fun countSince(since: Long): Int

    @Query(
        """
        SELECT
            packageName,
            COUNT(*) AS total,
            SUM(CASE WHEN outcome IN ('blocked', 'invalid', 'filtered', 'denied') THEN 1 ELSE 0 END) AS blocked,
            SUM(CASE WHEN outcome IN ('allowed', 'rewritten', 'passed', 'success') THEN 1 ELSE 0 END) AS allowed,
            SUM(CASE WHEN outcome IN ('decryption_failed', 'unsupported_protocol', 'resource_bypass', 'bypassed', 'passthrough') THEN 1 ELSE 0 END) AS bypassed,
            SUM(CASE WHEN outcome NOT IN ('blocked', 'invalid', 'filtered', 'denied', 'allowed', 'rewritten', 'passed', 'success', 'decryption_failed', 'unsupported_protocol', 'resource_bypass', 'bypassed', 'passthrough') THEN 1 ELSE 0 END) AS errors,
            MAX(timestamp) AS lastTimestamp
        FROM http_request_log
        WHERE timestamp >= :since AND packageName != ''
        GROUP BY packageName
        ORDER BY blocked DESC, total DESC, lastTimestamp DESC
        LIMIT :limit
        """
    )
    suspend fun appInterceptionStats(since: Long, limit: Int): List<AppInterceptionStatRow>

    @Query("""
        SELECT blockSubscriptionId AS subscriptionId, COUNT(*) AS hits
        FROM http_request_log
        WHERE timestamp >= :since
            AND outcome = :blockedOutcome
            AND blockSubscriptionId IS NOT NULL
        GROUP BY blockSubscriptionId
    """)
    suspend fun subscriptionInterceptionStats(
        since: Long,
        blockedOutcome: String
    ): List<SubscriptionInterceptionStatRow>

    @Query("DELETE FROM http_request_log WHERE timestamp < :before")
    suspend fun deleteBefore(before: Long)

    @Query("DELETE FROM http_request_log")
    suspend fun clearAll()
}

data class HttpDailyStatRow(
    val outcome: String,
    val count: Int
)

data class AppInterceptionStatRow(
    val packageName: String,
    val total: Int,
    val blocked: Int,
    val allowed: Int,
    val bypassed: Int,
    val errors: Int,
    val lastTimestamp: Long
)
