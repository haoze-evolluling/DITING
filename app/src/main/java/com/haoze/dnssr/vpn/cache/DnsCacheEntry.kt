package com.haoze.dnssr.vpn.cache

import com.haoze.dnssr.data.entity.DnsCacheEntity

data class DnsCacheEntry(
    val entity: DnsCacheEntity,
    val ttlOffsets: IntArray,
    val staleExpiresAt: Long
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is DnsCacheEntry) return false
        return entity == other.entity &&
                ttlOffsets.contentEquals(other.ttlOffsets) &&
                staleExpiresAt == other.staleExpiresAt
    }

    override fun hashCode(): Int {
        var result = entity.hashCode()
        result = 31 * result + ttlOffsets.contentHashCode()
        result = 31 * result + staleExpiresAt.hashCode()
        return result
    }
}
