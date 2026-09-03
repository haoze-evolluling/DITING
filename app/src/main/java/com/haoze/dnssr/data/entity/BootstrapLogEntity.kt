package com.haoze.dnssr.data.entity

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(
    tableName = "bootstrap_log",
    indices = [
        Index(value = ["timestamp"], name = "index_bootstrap_log_timestamp"),
        Index(value = ["ipId", "timestamp"], name = "index_bootstrap_log_ip_timestamp"),
        Index(value = ["success", "timestamp"], name = "index_bootstrap_log_success_timestamp")
    ]
)
data class BootstrapLogEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val timestamp: Long,
    val ipId: String,
    val ipName: String,
    val ip: String,
    val host: String,
    val success: Boolean,
    val elapsedMs: Long,
    val fallbackUsed: Boolean = false,
    val message: String? = null
)
