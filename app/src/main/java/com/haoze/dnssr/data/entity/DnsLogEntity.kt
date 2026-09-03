package com.haoze.dnssr.data.entity

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

/**
 * DNS 请求日志实体。
 *
 * @param result 请求结果：PASSED（通过）、BLOCKED（被屏蔽）、ERROR（解析失败）。
 * @param packageName 发起 DNS 查询的应用包名（由 5 元组 UID 动态反查得出，可能为空）。
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
