package com.haoze.dnssr.data.entity

import androidx.room.Entity
import androidx.room.Index
import androidx.room.ColumnInfo
import androidx.room.PrimaryKey

/**
 * DNS 响应缓存实体。
 */
@Entity(
    tableName = "dns_cache",
    indices = [
        Index(value = ["expiresAt"], name = "index_dns_cache_expiresAt"),
        Index(value = ["lastHitAt"], name = "index_dns_cache_lastHitAt"),
        Index(value = ["queryName"], name = "index_dns_cache_queryName"),
        Index(value = ["queryType", "expiresAt"], name = "index_dns_cache_queryType_expiresAt")
    ]
)
data class DnsCacheEntity(
    @PrimaryKey val key: String,
    val queryName: String,
    val queryType: Int,
    val queryClass: Int,
    val createdAt: Long,
    val expiresAt: Long,
    val lastHitAt: Long?,
    @ColumnInfo(defaultValue = "0") val hitCount: Int,
    val originalTtlSeconds: Long,
    val ttlOffsets: String,
    val response: ByteArray,
    val responseSize: Int
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is DnsCacheEntity) return false
        return key == other.key &&
                queryName == other.queryName &&
                queryType == other.queryType &&
                queryClass == other.queryClass &&
                createdAt == other.createdAt &&
                expiresAt == other.expiresAt &&
                lastHitAt == other.lastHitAt &&
                hitCount == other.hitCount &&
                originalTtlSeconds == other.originalTtlSeconds &&
                ttlOffsets == other.ttlOffsets &&
                response.contentEquals(other.response) &&
                responseSize == other.responseSize
    }

    override fun hashCode(): Int {
        var result = key.hashCode()
        result = 31 * result + queryName.hashCode()
        result = 31 * result + queryType
        result = 31 * result + queryClass
        result = 31 * result + createdAt.hashCode()
        result = 31 * result + expiresAt.hashCode()
        result = 31 * result + (lastHitAt?.hashCode() ?: 0)
        result = 31 * result + hitCount
        result = 31 * result + originalTtlSeconds.hashCode()
        result = 31 * result + ttlOffsets.hashCode()
        result = 31 * result + response.contentHashCode()
        result = 31 * result + responseSize
        return result
    }
}
