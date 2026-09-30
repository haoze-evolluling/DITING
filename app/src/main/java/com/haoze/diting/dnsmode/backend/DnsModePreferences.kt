package com.haoze.diting.dnsmode.backend

import android.content.Context
import android.content.SharedPreferences
import com.haoze.diting.dnsmode.model.DnsModeConfig

object DnsModePreferences {
    private const val PREFS_NAME = "diting_dns_mode_prefs"

    private const val KEY_SELECTED_UPSTREAM = "selected_upstream_id"
    private const val KEY_LOCAL_PORT = "local_listen_port"
    private const val KEY_CACHE_ENABLED = "cache_enabled"
    private const val KEY_CACHE_TTL = "cache_ttl_seconds"
    private const val KEY_AD_BLOCK_ENABLED = "ad_block_enabled"
    private const val KEY_LOG_QUERIES = "log_queries"
    private const val KEY_SERVICE_ACTIVE = "service_active"

    private fun getPrefs(context: Context): SharedPreferences {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    fun loadConfig(context: Context): DnsModeConfig {
        val prefs = getPrefs(context)
        val rawPort = prefs.getInt(KEY_LOCAL_PORT, 1053)
        val port = if (rawPort == 5353 || rawPort == 5354) 1053 else rawPort
        return DnsModeConfig(
            selectedUpstreamId = prefs.getString(KEY_SELECTED_UPSTREAM, "alidns") ?: "alidns",
            localListenPort = port,
            cacheEnabled = prefs.getBoolean(KEY_CACHE_ENABLED, true),
            cacheTtlSeconds = prefs.getInt(KEY_CACHE_TTL, 300),
            adBlockEnabled = prefs.getBoolean(KEY_AD_BLOCK_ENABLED, false),
            logQueries = prefs.getBoolean(KEY_LOG_QUERIES, true)
        )
    }

    fun saveConfig(context: Context, config: DnsModeConfig) {
        getPrefs(context).edit()
            .putString(KEY_SELECTED_UPSTREAM, config.selectedUpstreamId)
            .putInt(KEY_LOCAL_PORT, config.localListenPort)
            .putBoolean(KEY_CACHE_ENABLED, config.cacheEnabled)
            .putInt(KEY_CACHE_TTL, config.cacheTtlSeconds)
            .putBoolean(KEY_AD_BLOCK_ENABLED, config.adBlockEnabled)
            .putBoolean(KEY_LOG_QUERIES, config.logQueries)
            .apply()
    }

    fun setSelectedUpstreamId(context: Context, upstreamId: String) {
        getPrefs(context).edit().putString(KEY_SELECTED_UPSTREAM, upstreamId).apply()
    }

    fun setLocalListenPort(context: Context, port: Int) {
        getPrefs(context).edit().putInt(KEY_LOCAL_PORT, port).apply()
    }

    fun setCacheEnabled(context: Context, enabled: Boolean) {
        getPrefs(context).edit().putBoolean(KEY_CACHE_ENABLED, enabled).apply()
    }

    fun setAdBlockEnabled(context: Context, enabled: Boolean) {
        getPrefs(context).edit().putBoolean(KEY_AD_BLOCK_ENABLED, enabled).apply()
    }

    fun setServiceActive(context: Context, active: Boolean) {
        getPrefs(context).edit().putBoolean(KEY_SERVICE_ACTIVE, active).apply()
    }

    fun isServiceActive(context: Context): Boolean {
        return getPrefs(context).getBoolean(KEY_SERVICE_ACTIVE, false)
    }
}
