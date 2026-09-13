package com.haoze.dnssr.data.entity

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

/**
 * Room entity for a race-mode log entry. Only race resolutions that actually
 * issued DoH requests are recorded.
 */
@Entity(
    tableName = "dns_race_log",
    indices = [
        Index(value = ["timestamp"], name = "index_dns_race_log_timestamp"),
        Index(value = ["strategy", "timestamp"], name = "index_dns_race_log_strategy_timestamp"),
        Index(value = ["winnerProviderId", "timestamp"], name = "index_dns_race_log_winner_timestamp"),
        Index(value = ["selectedProviderId", "timestamp"], name = "index_dns_race_log_selected_timestamp")
    ]
)
data class RaceLogEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val timestamp: Long,
    val queryName: String,
    val queryType: Int,
    val strategy: String,
    val providerCount: Int,
    val success: Boolean,
    val elapsedMs: Long,
    val selectedProviderId: String? = null,
    val selectedProviderName: String? = null,
    val selectedElapsedMs: Long? = null,
    val winnerProviderId: String? = null,
    val winnerProviderName: String? = null,
    val winnerElapsedMs: Long? = null,
    val fallbackUsed: Boolean = false,
    val fallbackSuccess: Boolean = false,
    val message: String? = null
)
