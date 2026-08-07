package com.haoze.dnssr.data.entity

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(
    tableName = "http_request_log",
    indices = [
        Index(value = ["timestamp"], name = "index_http_request_log_timestamp"),
        Index(value = ["outcome", "timestamp"], name = "index_http_request_log_outcome_timestamp"),
        Index(value = ["authority"], name = "index_http_request_log_authority"),
        Index(
            value = ["blockSubscriptionId", "timestamp"],
            name = "index_http_request_log_block_subscription_timestamp"
        )
    ]
)
data class HttpRequestLogEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val timestamp: Long,
    val packageName: String,
    val authority: String?,
    val protocol: String,
    val outcome: String,
    val matchedRule: String? = null,
    val blockSubscriptionId: Long? = null
)
