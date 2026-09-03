package com.haoze.dnssr.data.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Transaction
import com.haoze.dnssr.data.entity.AppTrafficDailyEntity

@Dao
interface AppTrafficDao {

    @Query("SELECT * FROM app_traffic_daily WHERE date = :date ORDER BY (tx_bytes + rx_bytes) DESC")
    suspend fun queryByDate(date: String): List<AppTrafficDailyEntity>

    @Query("""
        SELECT 
            min(date) as date,
            package_name,
            max(app_name) as app_name,
            sum(tx_bytes) as tx_bytes,
            sum(rx_bytes) as rx_bytes,
            max(updated_at) as updated_at
        FROM app_traffic_daily
        WHERE date >= :startDate AND date <= :endDate
        GROUP BY package_name
        ORDER BY (sum(tx_bytes) + sum(rx_bytes)) DESC
    """)
    suspend fun queryDateRange(startDate: String, endDate: String): List<AppTrafficDailyEntity>

    @Query("""
        SELECT 
            min(date) as date,
            package_name,
            max(app_name) as app_name,
            sum(tx_bytes) as tx_bytes,
            sum(rx_bytes) as rx_bytes,
            max(updated_at) as updated_at
        FROM app_traffic_daily
        GROUP BY package_name
        ORDER BY (sum(tx_bytes) + sum(rx_bytes)) DESC
    """)
    suspend fun queryAllHistory(): List<AppTrafficDailyEntity>

    @Query("SELECT * FROM app_traffic_daily WHERE package_name = :packageName ORDER BY date DESC")
    suspend fun queryByPackage(packageName: String): List<AppTrafficDailyEntity>

    @Query("""
        INSERT INTO app_traffic_daily (date, package_name, app_name, tx_bytes, rx_bytes, updated_at)
        VALUES (:date, :packageName, :appName, :txBytes, :rxBytes, :updatedAt)
        ON CONFLICT(date, package_name) DO UPDATE SET
            app_name = CASE WHEN excluded.app_name != '' THEN excluded.app_name ELSE app_traffic_daily.app_name END,
            tx_bytes = app_traffic_daily.tx_bytes + excluded.tx_bytes,
            rx_bytes = app_traffic_daily.rx_bytes + excluded.rx_bytes,
            updated_at = excluded.updated_at
    """)
    suspend fun upsertDelta(
        date: String,
        packageName: String,
        appName: String,
        txBytes: Long,
        rxBytes: Long,
        updatedAt: Long
    )

    @Transaction
    suspend fun upsertBatchDeltas(
        date: String,
        deltas: List<AppTrafficDeltaItem>,
        updatedAt: Long
    ) {
        for (item in deltas) {
            if (item.txDelta > 0 || item.rxDelta > 0) {
                upsertDelta(
                    date = date,
                    packageName = item.packageName,
                    appName = item.appName,
                    txBytes = item.txDelta,
                    rxBytes = item.rxDelta,
                    updatedAt = updatedAt
                )
            }
        }
    }

    @Query("DELETE FROM app_traffic_daily WHERE date < :cutoffDate")
    suspend fun deleteOlderThan(cutoffDate: String): Int

    @Query("DELETE FROM app_traffic_daily")
    suspend fun clearAll(): Int
}

data class AppTrafficDeltaItem(
    val packageName: String,
    val appName: String,
    val txDelta: Long,
    val rxDelta: Long
)
