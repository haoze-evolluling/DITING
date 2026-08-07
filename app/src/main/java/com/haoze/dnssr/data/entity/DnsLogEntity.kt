package com.haoze.dnssr.data.entity

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

/**
 * DNS 请求日志实体。
 *
 * @param result 请求结果：PASSED（通过）、BLOCKED（被屏蔽）、ERROR（解析失败）。
 */
@Entity(
    tableName = "dns_log",
    indices = [
        Index(value = ["timestamp"], name = "index_dns_log_timestamp"),
        Index(value = ["result", "timestamp"], name = "index_dns_log_result_timestamp"),
        Index(value = ["result", "cached", "timestamp"], name = "index_dns_log_result_cached_timestamp"),
        Index(value = ["queryName"], name = "index_dns_log_queryName"),
        Index(value = ["blockSubscriptionId", "timestamp"], name = "index_dns_log_block_subscription_timestamp")
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
    val blockSubscriptionId: Long? = null
)
