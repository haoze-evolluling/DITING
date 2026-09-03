package com.haoze.dnssr.vpn.cache

import androidx.annotation.StringRes
import com.haoze.dnssr.R

enum class DnsCachePreset(
    val storageValue: String,
    @get:StringRes val displayName: Int,
    @get:StringRes val summary: Int,
    @get:StringRes val description: Int,
    val policy: DnsCachePolicy
) {
    CONSERVATIVE(
        storageValue = "conservative",
        displayName = R.string.cache_preset_conservative,
        summary = R.string.cache_preset_conservative_summary,
        description = R.string.cache_preset_conservative_description,
        policy = DnsCachePolicy(
            enabled = true,
            mode = DnsCacheMode.FOLLOW_DNS_TTL,
            maxTtlSeconds = 3600L,
            fixedTtlSeconds = 3600L,
            minTtlEnabled = false,
            minTtlSeconds = 60L,
            staleFallbackEnabled = false,
            staleFallbackSeconds = 300L
        )
    ),
    BALANCED(
        storageValue = "balanced",
        displayName = R.string.cache_preset_balanced,
        summary = R.string.cache_preset_balanced_summary,
        description = R.string.cache_preset_balanced_description,
        policy = DnsCachePolicy(
            enabled = true,
            mode = DnsCacheMode.LIMIT_MAX_TTL,
            maxTtlSeconds = 3600L,
            fixedTtlSeconds = 3600L,
            minTtlEnabled = true,
            minTtlSeconds = 60L,
            staleFallbackEnabled = true,
            staleFallbackSeconds = 300L
        )
    ),
    HIGH_HIT_RATE(
        storageValue = "high_hit_rate",
        displayName = R.string.cache_preset_high_hit_rate,
        summary = R.string.cache_preset_high_hit_rate_summary,
        description = R.string.cache_preset_high_hit_rate_description,
        policy = DnsCachePolicy(
            enabled = true,
            mode = DnsCacheMode.LIMIT_MAX_TTL,
            maxTtlSeconds = 21_600L,
            fixedTtlSeconds = 3600L,
            minTtlEnabled = true,
            minTtlSeconds = 120L,
            staleFallbackEnabled = true,
            staleFallbackSeconds = 900L
        )
    );

    fun toPolicy(enabled: Boolean = true): DnsCachePolicy {
        return policy.copy(enabled = enabled)
    }

    companion object {
        fun fromStorageValue(value: String?): DnsCachePreset? {
            return values().firstOrNull { it.storageValue == value }
        }

        fun fromPolicy(policy: DnsCachePolicy): DnsCachePreset {
            return when {
                policy.mode == DnsCacheMode.FOLLOW_DNS_TTL &&
                    !policy.minTtlEnabled &&
                    !policy.staleFallbackEnabled -> CONSERVATIVE

                policy.mode == DnsCacheMode.LIMIT_MAX_TTL &&
                    policy.maxTtlSeconds <= BALANCED.policy.maxTtlSeconds &&
                    (!policy.minTtlEnabled || policy.minTtlSeconds <= BALANCED.policy.minTtlSeconds) &&
                    (!policy.staleFallbackEnabled || policy.staleFallbackSeconds <= BALANCED.policy.staleFallbackSeconds) -> BALANCED

                else -> HIGH_HIT_RATE
            }
        }
    }
}
