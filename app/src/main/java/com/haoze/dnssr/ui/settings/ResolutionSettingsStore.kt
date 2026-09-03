package com.haoze.dnssr.ui.settings

import android.content.Context
import com.haoze.dnssr.ui.DEFAULT_HOME_VISIBLE_PROTOCOLS
import com.haoze.dnssr.ui.DnsResolutionMode
import com.haoze.dnssr.ui.HomeProviderVisibility
import com.haoze.dnssr.ui.PresetDnsService
import com.haoze.dnssr.vpn.DnsProtocol
import org.json.JSONArray

object ResolutionSettingsStore {
    const val KEY_RACE_MODE_ENABLED = "race_mode_enabled"
    const val KEY_RACE_PROVIDER_IDS = "race_provider_ids"
    const val KEY_RACE_TEST_DOMAIN = "race_test_domain"
    const val KEY_LATENCY_TEST_PROVIDER_IDS = "latency_test_provider_ids"
    const val KEY_RACE_MODE_STRATEGY = "race_mode_strategy"

    internal const val KEY_DNS_RESOLUTION_MODE = "dns_resolution_mode"
    internal const val KEY_PRESET_DNS_SERVICE = "preset_dns_service"
    private const val KEY_SMART_PREDICTION_PROVIDER_IDS = "smart_prediction_provider_ids"
    private const val KEY_PARALLEL_RACE_PROVIDER_IDS = "parallel_race_provider_ids"
    private const val KEY_PRIMARY_BACKUP_PROVIDER_IDS = "primary_backup_provider_ids"
    private const val KEY_HOME_VISIBLE_PROTOCOLS = "home_visible_protocols"
    private const val KEY_HOME_HIDDEN_PROVIDER_IDS = "home_hidden_provider_ids"
    private const val KEY_HOME_VISIBLE_PROVIDER_IDS = "home_visible_provider_ids"

    private val DEFAULT_RACE_PROVIDER_IDS = setOf(
        "preset_alidns_dns",
        "preset_dnspod_dns"
    )
    private val DEFAULT_LATENCY_TEST_PROVIDER_IDS = emptySet<String>()
    private const val DEFAULT_RACE_TEST_DOMAIN = "mihoyo.com"

    fun getRaceProviderIds(context: Context): Set<String> {
        val json = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_RACE_PROVIDER_IDS, null) ?: return DEFAULT_RACE_PROVIDER_IDS
        return try {
            val array = JSONArray(json)
            val ids = mutableSetOf<String>()
            for (i in 0 until array.length()) {
                ids.add(array.getString(i))
            }
            ids
        } catch (_: Exception) {
            DEFAULT_RACE_PROVIDER_IDS
        }
    }

    fun hasRaceProviderIds(context: Context): Boolean {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .contains(KEY_RACE_PROVIDER_IDS)
    }

    fun setRaceProviderIds(context: Context, ids: Set<String>) {
        val array = JSONArray()
        ids.forEach { array.put(it) }
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_RACE_PROVIDER_IDS, array.toString())
            .apply()
    }

    fun getLatencyTestProviderIds(context: Context): Set<String> {
        val json = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_LATENCY_TEST_PROVIDER_IDS, null) ?: return DEFAULT_LATENCY_TEST_PROVIDER_IDS
        return try {
            val array = JSONArray(json)
            val ids = mutableSetOf<String>()
            for (i in 0 until array.length()) {
                ids.add(array.getString(i))
            }
            ids
        } catch (_: Exception) {
            DEFAULT_LATENCY_TEST_PROVIDER_IDS
        }
    }

    fun hasLatencyTestProviderIds(context: Context): Boolean {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .contains(KEY_LATENCY_TEST_PROVIDER_IDS)
    }

    fun setLatencyTestProviderIds(context: Context, ids: Set<String>) {
        val array = JSONArray()
        ids.forEach { array.put(it) }
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_LATENCY_TEST_PROVIDER_IDS, array.toString())
            .apply()
    }

    fun getRaceTestDomain(context: Context): String {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_RACE_TEST_DOMAIN, DEFAULT_RACE_TEST_DOMAIN)
            ?.takeIf { it.isNotBlank() }
            ?: DEFAULT_RACE_TEST_DOMAIN
    }

    fun setRaceTestDomain(context: Context, domain: String) {
        val trimmed = domain.trim()
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_RACE_TEST_DOMAIN, trimmed.takeIf { it.isNotBlank() } ?: DEFAULT_RACE_TEST_DOMAIN)
            .apply()
    }

    fun getDnsResolutionMode(context: Context): DnsResolutionMode {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return DnsResolutionMode.fromStorageValue(prefs.getString(KEY_DNS_RESOLUTION_MODE, null))
            ?: DnsResolutionMode.SINGLE
    }

    fun setDnsResolutionMode(context: Context, mode: DnsResolutionMode) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_DNS_RESOLUTION_MODE, mode.storageValue)
            .apply()
    }

    private fun getModeProviderIds(context: Context, key: String): Set<String> {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val json = prefs.getString(key, null)
        if (json == null) {
            val migrated = getRaceProviderIds(context)
            setModeProviderIds(context, key, migrated)
            return migrated
        }
        return try {
            val array = JSONArray(json)
            buildSet { for (index in 0 until array.length()) add(array.getString(index)) }
        } catch (_: Exception) {
            emptySet()
        }
    }

    private fun setModeProviderIds(context: Context, key: String, ids: Set<String>) {
        val array = JSONArray()
        ids.forEach(array::put)
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
            .putString(key, array.toString()).apply()
    }

    fun getSmartPredictionProviderIds(context: Context): Set<String> =
        getModeProviderIds(context, KEY_SMART_PREDICTION_PROVIDER_IDS)

    fun setSmartPredictionProviderIds(context: Context, ids: Set<String>) =
        setModeProviderIds(context, KEY_SMART_PREDICTION_PROVIDER_IDS, ids)

    fun getParallelRaceProviderIds(context: Context): Set<String> =
        getModeProviderIds(context, KEY_PARALLEL_RACE_PROVIDER_IDS)

    fun setParallelRaceProviderIds(context: Context, ids: Set<String>) =
        setModeProviderIds(context, KEY_PARALLEL_RACE_PROVIDER_IDS, ids)

    fun getPrimaryBackupProviderIds(context: Context): List<String> {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val json = prefs.getString(KEY_PRIMARY_BACKUP_PROVIDER_IDS, null)
            ?: return getRaceProviderIds(context).toList()
        return try {
            val array = JSONArray(json)
            buildList {
                for (index in 0 until array.length()) add(array.getString(index))
            }.distinct()
        } catch (_: Exception) {
            getRaceProviderIds(context).toList()
        }
    }

    fun setPrimaryBackupProviderIds(context: Context, ids: List<String>) {
        val array = JSONArray()
        ids.distinct().forEach(array::put)
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_PRIMARY_BACKUP_PROVIDER_IDS, array.toString())
            .apply()
    }

    fun removeProviderFromResolutionModes(context: Context, id: String) {
        setSmartPredictionProviderIds(context, getSmartPredictionProviderIds(context) - id)
        setParallelRaceProviderIds(context, getParallelRaceProviderIds(context) - id)
        setPrimaryBackupProviderIds(context, getPrimaryBackupProviderIds(context) - id)
    }

    fun getHomeProviderVisibility(context: Context): HomeProviderVisibility {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return HomeProviderVisibility(
            visibleProtocols = readStringSet(prefs.getString(KEY_HOME_VISIBLE_PROTOCOLS, null))
                ?.mapNotNull { value -> DnsProtocol.entries.firstOrNull { it.name == value } }
                ?.toSet()
                ?: DEFAULT_HOME_VISIBLE_PROTOCOLS,
            hiddenProviderIds = readStringSet(prefs.getString(KEY_HOME_HIDDEN_PROVIDER_IDS, null)) ?: emptySet(),
            visibleProviderIds = readStringSet(prefs.getString(KEY_HOME_VISIBLE_PROVIDER_IDS, null)) ?: emptySet()
        )
    }

    fun setHomeProviderVisibility(context: Context, visibility: HomeProviderVisibility) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_HOME_VISIBLE_PROTOCOLS, writeStringSet(visibility.visibleProtocols.map { it.name }.toSet()))
            .putString(KEY_HOME_HIDDEN_PROVIDER_IDS, writeStringSet(visibility.hiddenProviderIds))
            .putString(KEY_HOME_VISIBLE_PROVIDER_IDS, writeStringSet(visibility.visibleProviderIds))
            .apply()
    }

    fun getPresetDnsService(context: Context): PresetDnsService {
        val value = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_PRESET_DNS_SERVICE, null)
        return PresetDnsService.fromStorageValue(value)
    }

    fun setPresetDnsService(context: Context, service: PresetDnsService) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_PRESET_DNS_SERVICE, service.name)
            .apply()
    }
}
