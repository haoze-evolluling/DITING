package com.haoze.dnssr.vpn.cache

import kotlin.math.max
import kotlin.math.min

enum class DnsCacheMode(
    val storageValue: String,
    val displayName: String
) {
    FOLLOW_DNS_TTL("follow_dns_ttl", "跟随 DNS TTL"),
    LIMIT_MAX_TTL("limit_max_ttl", "限制最长缓存时间"),
    FIXED_TTL("fixed_ttl", "固定缓存时间");

    companion object {
        fun fromStorageValue(value: String?): DnsCacheMode {
            return values().firstOrNull { it.storageValue == value } ?: LIMIT_MAX_TTL
        }
    }
}

data class DnsCachePolicy(
    val enabled: Boolean = true,
    val mode: DnsCacheMode = DnsCacheMode.LIMIT_MAX_TTL,
    val maxTtlSeconds: Long = 3600L,
    val fixedTtlSeconds: Long = 3600L,
    val minTtlEnabled: Boolean = false,
    val minTtlSeconds: Long = 60L,
    val staleFallbackEnabled: Boolean = false,
    val staleFallbackSeconds: Long = 300L
) {
    fun effectiveTtlSeconds(upstreamTtlSeconds: Long): Long {
        if (upstreamTtlSeconds <= 0L) return 0L
        val modeTtl = when (mode) {
            DnsCacheMode.FOLLOW_DNS_TTL -> upstreamTtlSeconds
            DnsCacheMode.LIMIT_MAX_TTL -> min(upstreamTtlSeconds, maxTtlSeconds.coerceAtLeast(0L))
            DnsCacheMode.FIXED_TTL -> fixedTtlSeconds.coerceAtLeast(0L)
        }
        return if (minTtlEnabled) {
            max(modeTtl, minTtlSeconds.coerceAtLeast(0L))
        } else {
            modeTtl
        }
    }
}
