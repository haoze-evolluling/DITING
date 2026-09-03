package com.haoze.dnssr.data.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index

@Entity(
    tableName = "app_traffic_daily",
    primaryKeys = ["date", "package_name"],
    indices = [
        Index(value = ["date"]),
        Index(value = ["package_name"])
    ]
)
data class AppTrafficDailyEntity(
    @ColumnInfo(name = "date") val date: String,            // YYYY-MM-DD
    @ColumnInfo(name = "package_name") val packageName: String,
    @ColumnInfo(name = "app_name") val appName: String,
    @ColumnInfo(name = "tx_bytes") val txBytes: Long,       // 累计上传字节 (Bytes)
    @ColumnInfo(name = "rx_bytes") val rxBytes: Long,       // 累计下载字节 (Bytes)
    @ColumnInfo(name = "updated_at") val updatedAt: Long    // 更新时间戳 (ms)
)
