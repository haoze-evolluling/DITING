package com.haoze.dnssr.vpn.cache

import com.haoze.dnssr.data.entity.DnsCacheEntity

data class DnsCacheEntry(
    val entity: DnsCacheEntity,
    val ttlOffsets: IntArray,
    val staleExpiresAt: Long,
    var currentHitCount: Int = entity.hitCount,
    var currentLastHitAt: Long? = entity.lastHitAt
) {
    fun toEntity(): DnsCacheEntity =
        if (currentHitCount != entity.hitCount || currentLastHitAt != entity.lastHitAt) {
            entity.copy(hitCount = currentHitCount, lastHitAt = currentLastHitAt)
        } else {
            entity
        }

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is DnsCacheEntry) return false
        return entity == other.entity &&
                ttlOffsets.contentEquals(other.ttlOffsets) &&
                staleExpiresAt == other.staleExpiresAt &&
                currentHitCount == other.currentHitCount &&
                currentLastHitAt == other.currentLastHitAt
    }

    override fun hashCode(): Int {
        var result = entity.hashCode()
        result = 31 * result + ttlOffsets.contentHashCode()
        result = 31 * result + staleExpiresAt.hashCode()
        result = 31 * result + currentHitCount.hashCode()
        result = 31 * result + (currentLastHitAt?.hashCode() ?: 0)
        return result
    }
}
