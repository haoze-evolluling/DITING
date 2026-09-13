package com.haoze.dnssr.data.entity

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

/**
 * Room entity for a DNS request log entry.
 *
 * @param result query outcome: PASSED (allowed), BLOCKED, or ERROR (resolution failed).
 * @param packageName package name of the app that issued the DNS query, resolved
 *   dynamically from the UID in the connection 5-tuple; may be null.
 */
@Entity(
    tableName = "dns_log",
    indices = [
        Index(value = ["timestamp"], name = "index_dns_log_timestamp"),
        Index(value = ["result", "timestamp"], name = "index_dns_log_result_timestamp"),
        Index(value = ["result", "cached", "timestamp"], name = "index_dns_log_result_cached_timestamp"),
        Index(value = ["queryName"], name = "index_dns_log_queryName"),
        Index(value = ["blockSubscriptionId", "timestamp"], name = "index_dns_log_block_subscription_timestamp"),
        Index(value = ["packageName"], name = "index_dns_log_packageName")
    ]
)
data class DnsLogEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val timestamp: Long,
    val queryName: String,
    val queryType: Int,
    val result: String,
    val message: String? = null,
    val cached: Boolean = false,
    val blockSubscriptionId: Long? = null,
    val packageName: String? = null
)
