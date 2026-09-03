package com.haoze.dnssr.ui.settings

import android.content.Context
import com.haoze.dnssr.vpn.cache.DnsCacheMode
import com.haoze.dnssr.vpn.cache.DnsCachePolicy
import com.haoze.dnssr.vpn.cache.DnsCachePreset

object DnsCacheSettingsStore {
    private const val KEY_DNS_CACHE_ENABLED = "dns_cache_enabled_v2"
    private const val KEY_DNS_CACHE_MODE = "dns_cache_mode_v2"
    private const val KEY_DNS_CACHE_MAX_TTL_SECONDS = "dns_cache_max_ttl_seconds_v2"
    private const val KEY_DNS_CACHE_FIXED_TTL_SECONDS = "dns_cache_fixed_ttl_seconds_v2"
    private const val KEY_DNS_CACHE_MIN_TTL_ENABLED = "dns_cache_min_ttl_enabled_v2"
    private const val KEY_DNS_CACHE_MIN_TTL_SECONDS = "dns_cache_min_ttl_seconds_v2"
    private const val KEY_DNS_CACHE_STALE_FALLBACK_ENABLED = "dns_cache_stale_fallback_enabled_v2"
    private const val KEY_DNS_CACHE_STALE_FALLBACK_SECONDS = "dns_cache_stale_fallback_seconds_v2"
    private const val KEY_DNS_CACHE_PRESET = "dns_cache_preset_v3"

    private const val MIN_CACHE_SECONDS = 30L
    private const val MAX_CACHE_SECONDS = 86_400L
    private const val DEFAULT_CACHE_ENABLED = true
    private const val DEFAULT_CACHE_MAX_TTL_SECONDS = 3600L
    private const val DEFAULT_CACHE_FIXED_TTL_SECONDS = 3600L
    private const val DEFAULT_CACHE_MIN_TTL_SECONDS = 60L
    private const val DEFAULT_CACHE_STALE_FALLBACK_SECONDS = 300L

    fun isCacheEnabled(context: Context): Boolean {
        return getDnsCachePolicy(context).enabled
    }

    fun setCacheEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_DNS_CACHE_ENABLED, enabled)
            .apply()
    }

    fun getDnsCachePolicy(context: Context): DnsCachePolicy {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return DnsCachePolicy(
            enabled = prefs.getBoolean(KEY_DNS_CACHE_ENABLED, DEFAULT_CACHE_ENABLED),
            mode = DnsCacheMode.fromStorageValue(
                prefs.getString(KEY_DNS_CACHE_MODE, DnsCacheMode.LIMIT_MAX_TTL.storageValue)
            ),
            maxTtlSeconds = prefs.getLong(KEY_DNS_CACHE_MAX_TTL_SECONDS, DEFAULT_CACHE_MAX_TTL_SECONDS)
                .coerceIn(MIN_CACHE_SECONDS, MAX_CACHE_SECONDS),
            fixedTtlSeconds = prefs.getLong(KEY_DNS_CACHE_FIXED_TTL_SECONDS, DEFAULT_CACHE_FIXED_TTL_SECONDS)
                .coerceIn(MIN_CACHE_SECONDS, MAX_CACHE_SECONDS),
            minTtlEnabled = prefs.getBoolean(KEY_DNS_CACHE_MIN_TTL_ENABLED, false),
            minTtlSeconds = prefs.getLong(KEY_DNS_CACHE_MIN_TTL_SECONDS, DEFAULT_CACHE_MIN_TTL_SECONDS)
                .coerceIn(MIN_CACHE_SECONDS, MAX_CACHE_SECONDS),
            staleFallbackEnabled = prefs.getBoolean(KEY_DNS_CACHE_STALE_FALLBACK_ENABLED, false),
            staleFallbackSeconds = prefs.getLong(
                KEY_DNS_CACHE_STALE_FALLBACK_SECONDS,
                DEFAULT_CACHE_STALE_FALLBACK_SECONDS
            ).coerceIn(MIN_CACHE_SECONDS, MAX_CACHE_SECONDS)
        )
    }

    fun getDnsCachePreset(context: Context): DnsCachePreset {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return DnsCachePreset.fromStorageValue(prefs.getString(KEY_DNS_CACHE_PRESET, null))
            ?: DnsCachePreset.fromPolicy(getDnsCachePolicy(context))
    }

    fun setDnsCachePreset(context: Context, preset: DnsCachePreset) {
        val enabled = getDnsCachePolicy(context).enabled
        setDnsCachePolicy(context, preset.toPolicy(enabled = enabled), preset)
    }

    fun setDnsCachePolicy(context: Context, policy: DnsCachePolicy) {
        setDnsCachePolicy(context, policy, DnsCachePreset.fromPolicy(policy))
    }

    private fun setDnsCachePolicy(context: Context, policy: DnsCachePolicy, preset: DnsCachePreset) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_DNS_CACHE_PRESET, preset.storageValue)
            .putBoolean(KEY_DNS_CACHE_ENABLED, policy.enabled)
            .putString(KEY_DNS_CACHE_MODE, policy.mode.storageValue)
            .putLong(KEY_DNS_CACHE_MAX_TTL_SECONDS, policy.maxTtlSeconds.coerceIn(MIN_CACHE_SECONDS, MAX_CACHE_SECONDS))
            .putLong(KEY_DNS_CACHE_FIXED_TTL_SECONDS, policy.fixedTtlSeconds.coerceIn(MIN_CACHE_SECONDS, MAX_CACHE_SECONDS))
            .putBoolean(KEY_DNS_CACHE_MIN_TTL_ENABLED, policy.minTtlEnabled)
            .putLong(KEY_DNS_CACHE_MIN_TTL_SECONDS, policy.minTtlSeconds.coerceIn(MIN_CACHE_SECONDS, MAX_CACHE_SECONDS))
            .putBoolean(KEY_DNS_CACHE_STALE_FALLBACK_ENABLED, policy.staleFallbackEnabled)
            .putLong(
                KEY_DNS_CACHE_STALE_FALLBACK_SECONDS,
                policy.staleFallbackSeconds.coerceIn(MIN_CACHE_SECONDS, MAX_CACHE_SECONDS)
            )
            .apply()
    }
}
