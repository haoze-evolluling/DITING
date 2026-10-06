package com.haoze.diting.server.backend

import android.content.Context
import android.content.SharedPreferences
import com.haoze.diting.server.model.DnsModeConfig
import com.haoze.diting.server.model.DnsModeProtocol
import com.haoze.diting.server.model.DnsModeStats
import com.haoze.diting.server.model.DnsUpstreamServer
import com.haoze.diting.core.cache.DnsCachePreset
import org.json.JSONArray
import org.json.JSONObject

object DnsModePreferences {
    private const val PREFS_NAME = "diting_dns_mode_prefs"

    private const val KEY_SELECTED_UPSTREAM = "selected_upstream_id"
    private const val KEY_LOCAL_PORT = "local_listen_port"
    private const val KEY_CACHE_ENABLED = "cache_enabled"
    private const val KEY_CACHE_PRESET = "cache_preset"
    private const val KEY_CACHE_TTL = "cache_ttl_seconds"
    private const val KEY_AD_BLOCK_ENABLED = "ad_block_enabled"
    private const val KEY_LOG_QUERIES = "log_queries"
    private const val KEY_LOG_QUERIES_MIGRATED = "log_queries_default_off"
    private const val KEY_SERVICE_ACTIVE = "service_active"
    private const val KEY_CUSTOM_UPSTREAMS = "custom_upstreams"

    private const val KEY_STATS_QUERY_COUNT = "stats_query_count"
    private const val KEY_STATS_CACHE_HIT_COUNT = "stats_cache_hit_count"
    private const val KEY_STATS_BLOCKED_COUNT = "stats_blocked_count"
    private const val KEY_STATS_FAILED_COUNT = "stats_failed_count"
    private const val KEY_STATS_LATENCY_MS = "stats_latency_ms"
    private const val KEY_STATS_LATENCY_TOTAL_MS = "stats_latency_total_ms"
    private const val KEY_STATS_UPTIME_SECONDS = "stats_uptime_seconds"

    private fun getPrefs(context: Context): SharedPreferences {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    fun loadConfig(context: Context): DnsModeConfig {
        val prefs = getPrefs(context)
        val rawPort = prefs.getInt(KEY_LOCAL_PORT, 1053)
        val port = if (rawPort == 5353 || rawPort == 5354) 1053 else rawPort
        // logQueries was never user-editable and used to default to true, so any
        // stored true came from the old default rather than a choice: flip it to
        // the new privacy-preserving default once.
        if (!prefs.getBoolean(KEY_LOG_QUERIES_MIGRATED, false)) {
            prefs.edit()
                .putBoolean(KEY_LOG_QUERIES, false)
                .putBoolean(KEY_LOG_QUERIES_MIGRATED, true)
                .apply()
        }
        val presetStorage = prefs.getString(KEY_CACHE_PRESET, null)
        val cachePreset = DnsCachePreset.fromStorageValue(presetStorage) ?: DnsCachePreset.BALANCED
        return DnsModeConfig(
            selectedUpstreamId = prefs.getString(KEY_SELECTED_UPSTREAM, "preset_alidns_dns") ?: "preset_alidns_dns",
            localListenPort = port,
            cacheEnabled = prefs.getBoolean(KEY_CACHE_ENABLED, true),
            cachePreset = cachePreset,
            cacheTtlSeconds = prefs.getInt(KEY_CACHE_TTL, 300),
            adBlockEnabled = prefs.getBoolean(KEY_AD_BLOCK_ENABLED, false),
            logQueries = prefs.getBoolean(KEY_LOG_QUERIES, false)
        )
    }

    fun saveConfig(context: Context, config: DnsModeConfig) {
        getPrefs(context).edit()
            .putString(KEY_SELECTED_UPSTREAM, config.selectedUpstreamId)
            .putInt(KEY_LOCAL_PORT, config.localListenPort)
            .putBoolean(KEY_CACHE_ENABLED, config.cacheEnabled)
            .putString(KEY_CACHE_PRESET, config.cachePreset.storageValue)
            .putInt(KEY_CACHE_TTL, config.cacheTtlSeconds)
            .putBoolean(KEY_AD_BLOCK_ENABLED, config.adBlockEnabled)
            .putBoolean(KEY_LOG_QUERIES, config.logQueries)
            .apply()
    }

    fun loadStats(context: Context): DnsModeStats {
        val prefs = getPrefs(context)
        return DnsModeStats(
            queryCount = prefs.getLong(KEY_STATS_QUERY_COUNT, 0L),
            cacheHitCount = prefs.getLong(KEY_STATS_CACHE_HIT_COUNT, 0L),
            blockedCount = prefs.getLong(KEY_STATS_BLOCKED_COUNT, 0L),
            failedCount = prefs.getLong(KEY_STATS_FAILED_COUNT, 0L),
            latencyMs = prefs.getLong(KEY_STATS_LATENCY_MS, 0L),
            latencyTotalMs = prefs.getLong(KEY_STATS_LATENCY_TOTAL_MS, 0L),
            uptimeSeconds = prefs.getLong(KEY_STATS_UPTIME_SECONDS, 0L)
        )
    }

    fun saveStats(context: Context, stats: DnsModeStats) {
        getPrefs(context).edit()
            .putLong(KEY_STATS_QUERY_COUNT, stats.queryCount)
            .putLong(KEY_STATS_CACHE_HIT_COUNT, stats.cacheHitCount)
            .putLong(KEY_STATS_BLOCKED_COUNT, stats.blockedCount)
            .putLong(KEY_STATS_FAILED_COUNT, stats.failedCount)
            .putLong(KEY_STATS_LATENCY_MS, stats.latencyMs)
            .putLong(KEY_STATS_LATENCY_TOTAL_MS, stats.latencyTotalMs)
            .putLong(KEY_STATS_UPTIME_SECONDS, stats.uptimeSeconds)
            .apply()
    }

    fun clearStats(context: Context) {
        getPrefs(context).edit()
            .remove(KEY_STATS_QUERY_COUNT)
            .remove(KEY_STATS_CACHE_HIT_COUNT)
            .remove(KEY_STATS_BLOCKED_COUNT)
            .remove(KEY_STATS_FAILED_COUNT)
            .remove(KEY_STATS_LATENCY_MS)
            .remove(KEY_STATS_LATENCY_TOTAL_MS)
            .remove(KEY_STATS_UPTIME_SECONDS)
            .apply()
    }

    fun setServiceActive(context: Context, active: Boolean) {
        getPrefs(context).edit().putBoolean(KEY_SERVICE_ACTIVE, active).apply()
    }

    fun isServiceActive(context: Context): Boolean {
        return getPrefs(context).getBoolean(KEY_SERVICE_ACTIVE, false)
    }

    fun loadCustomUpstreams(context: Context): List<DnsUpstreamServer> {
        return deserializeUpstreams(getPrefs(context).getString(KEY_CUSTOM_UPSTREAMS, null))
    }

    fun saveCustomUpstreams(context: Context, servers: List<DnsUpstreamServer>) {
        getPrefs(context).edit()
            .putString(KEY_CUSTOM_UPSTREAMS, serializeUpstreams(servers))
            .apply()
    }

    fun serializeUpstreams(servers: List<DnsUpstreamServer>): String {
        val array = JSONArray()
        servers.forEach { server ->
            array.put(
                JSONObject()
                    .put("id", server.id)
                    .put("name", server.name)
                    .put("address", server.address)
                    .put("port", server.port)
                    .put("protocol", server.protocol.name)
            )
        }
        return array.toString()
    }

    fun deserializeUpstreams(json: String?): List<DnsUpstreamServer> {
        if (json.isNullOrBlank()) return emptyList()
        return runCatching {
            val array = JSONArray(json)
            (0 until array.length()).mapNotNull { index ->
                val item = array.optJSONObject(index) ?: return@mapNotNull null
                val id = item.optString("id")
                val name = item.optString("name")
                val address = item.optString("address")
                if (id.isBlank() || name.isBlank() || address.isBlank()) return@mapNotNull null
                DnsUpstreamServer(
                    id = id,
                    name = name,
                    address = address,
                    port = item.optInt("port", 53),
                    protocol = runCatching {
                        DnsModeProtocol.fromStorage(item.optString("protocol"))
                    }.getOrDefault(DnsModeProtocol.DNS),
                    isCustom = true
                )
            }
        }.getOrDefault(emptyList())
    }
}
