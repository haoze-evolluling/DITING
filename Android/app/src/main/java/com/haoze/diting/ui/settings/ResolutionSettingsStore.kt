package com.haoze.diting.ui.settings

import android.content.Context
import com.haoze.diting.data.RuleDataset
import com.haoze.diting.ui.DEFAULT_HOME_VISIBLE_PROTOCOLS
import com.haoze.diting.ui.DnsResolutionMode
import com.haoze.diting.ui.HomeProviderVisibility
import com.haoze.diting.ui.PresetDnsService
import com.haoze.diting.core.dns.DnsProtocol
import org.json.JSONArray

object ResolutionSettingsStore {
    const val KEY_RACE_PROVIDER_IDS = "race_provider_ids"
    const val KEY_RACE_TEST_DOMAIN = "race_test_domain"
    const val KEY_LATENCY_TEST_PROVIDER_IDS = "latency_test_provider_ids"

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

    fun getRaceProviderIds(context: Context, dataset: RuleDataset = RuleDataset.NORMAL): Set<String> {
        val json = datasetPrefs(context, dataset)
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

    fun hasRaceProviderIds(context: Context, dataset: RuleDataset = RuleDataset.NORMAL): Boolean {
        return datasetPrefs(context, dataset)
            .contains(KEY_RACE_PROVIDER_IDS)
    }

    fun setRaceProviderIds(context: Context, ids: Set<String>, dataset: RuleDataset = RuleDataset.NORMAL) {
        val array = JSONArray()
        ids.forEach { array.put(it) }
        datasetPrefs(context, dataset)
            .edit()
            .putString(KEY_RACE_PROVIDER_IDS, array.toString())
            .apply()
    }

    fun getLatencyTestProviderIds(context: Context, dataset: RuleDataset = RuleDataset.NORMAL): Set<String> {
        val json = datasetPrefs(context, dataset)
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

    fun hasLatencyTestProviderIds(context: Context, dataset: RuleDataset = RuleDataset.NORMAL): Boolean {
        return datasetPrefs(context, dataset)
            .contains(KEY_LATENCY_TEST_PROVIDER_IDS)
    }

    fun setLatencyTestProviderIds(context: Context, ids: Set<String>, dataset: RuleDataset = RuleDataset.NORMAL) {
        val array = JSONArray()
        ids.forEach { array.put(it) }
        datasetPrefs(context, dataset)
            .edit()
            .putString(KEY_LATENCY_TEST_PROVIDER_IDS, array.toString())
            .apply()
    }

    fun getRaceTestDomain(context: Context, dataset: RuleDataset = RuleDataset.NORMAL): String {
        return datasetPrefs(context, dataset)
            .getString(KEY_RACE_TEST_DOMAIN, DEFAULT_RACE_TEST_DOMAIN)
            ?.takeIf { it.isNotBlank() }
            ?: DEFAULT_RACE_TEST_DOMAIN
    }

    fun setRaceTestDomain(context: Context, domain: String, dataset: RuleDataset = RuleDataset.NORMAL) {
        val trimmed = domain.trim()
        datasetPrefs(context, dataset)
            .edit()
            .putString(KEY_RACE_TEST_DOMAIN, trimmed.takeIf { it.isNotBlank() } ?: DEFAULT_RACE_TEST_DOMAIN)
            .apply()
    }

    fun getDnsResolutionMode(context: Context, dataset: RuleDataset = RuleDataset.NORMAL): DnsResolutionMode {
        val prefs = datasetPrefs(context, dataset)
        return DnsResolutionMode.fromStorageValue(prefs.getString(KEY_DNS_RESOLUTION_MODE, null))
            ?: DnsResolutionMode.SINGLE
    }

    fun setDnsResolutionMode(context: Context, mode: DnsResolutionMode, dataset: RuleDataset = RuleDataset.NORMAL) {
        datasetPrefs(context, dataset)
            .edit()
            .putString(KEY_DNS_RESOLUTION_MODE, mode.storageValue)
            .apply()
    }

    private fun getModeProviderIds(context: Context, key: String, dataset: RuleDataset = RuleDataset.NORMAL): Set<String> {
        val prefs = datasetPrefs(context, dataset)
        val json = prefs.getString(key, null) ?: return DEFAULT_RACE_PROVIDER_IDS
        return try {
            val array = JSONArray(json)
            buildSet { for (index in 0 until array.length()) add(array.getString(index)) }
        } catch (_: Exception) {
            DEFAULT_RACE_PROVIDER_IDS
        }
    }

    private fun setModeProviderIds(context: Context, key: String, ids: Set<String>, dataset: RuleDataset = RuleDataset.NORMAL) {
        val array = JSONArray()
        ids.forEach(array::put)
        datasetPrefs(context, dataset).edit()
            .putString(key, array.toString()).apply()
    }

    fun getSmartPredictionProviderIds(context: Context, dataset: RuleDataset = RuleDataset.NORMAL): Set<String> =
        getModeProviderIds(context, KEY_SMART_PREDICTION_PROVIDER_IDS, dataset)

    fun setSmartPredictionProviderIds(context: Context, ids: Set<String>, dataset: RuleDataset = RuleDataset.NORMAL) =
        setModeProviderIds(context, KEY_SMART_PREDICTION_PROVIDER_IDS, ids, dataset)

    fun getParallelRaceProviderIds(context: Context, dataset: RuleDataset = RuleDataset.NORMAL): Set<String> =
        getModeProviderIds(context, KEY_PARALLEL_RACE_PROVIDER_IDS, dataset)

    fun setParallelRaceProviderIds(context: Context, ids: Set<String>, dataset: RuleDataset = RuleDataset.NORMAL) =
        setModeProviderIds(context, KEY_PARALLEL_RACE_PROVIDER_IDS, ids, dataset)

    fun getPrimaryBackupProviderIds(context: Context, dataset: RuleDataset = RuleDataset.NORMAL): List<String> {
        val prefs = datasetPrefs(context, dataset)
        val json = prefs.getString(KEY_PRIMARY_BACKUP_PROVIDER_IDS, null)
            ?: return DEFAULT_RACE_PROVIDER_IDS.toList()
        return try {
            val array = JSONArray(json)
            buildList {
                for (index in 0 until array.length()) add(array.getString(index))
            }.distinct()
        } catch (_: Exception) {
            DEFAULT_RACE_PROVIDER_IDS.toList()
        }
    }

    fun setPrimaryBackupProviderIds(context: Context, ids: List<String>, dataset: RuleDataset = RuleDataset.NORMAL) {
        val array = JSONArray()
        ids.distinct().forEach(array::put)
        datasetPrefs(context, dataset)
            .edit()
            .putString(KEY_PRIMARY_BACKUP_PROVIDER_IDS, array.toString())
            .apply()
    }

    fun removeProviderFromResolutionModes(context: Context, id: String, dataset: RuleDataset = RuleDataset.NORMAL) {
        setSmartPredictionProviderIds(context, getSmartPredictionProviderIds(context, dataset) - id, dataset)
        setParallelRaceProviderIds(context, getParallelRaceProviderIds(context, dataset) - id, dataset)
        setPrimaryBackupProviderIds(context, getPrimaryBackupProviderIds(context, dataset) - id, dataset)
    }

    fun getHomeProviderVisibility(context: Context, dataset: RuleDataset = RuleDataset.NORMAL): HomeProviderVisibility {
        val prefs = datasetPrefs(context, dataset)
        return HomeProviderVisibility(
            visibleProtocols = readStringSet(prefs.getString(KEY_HOME_VISIBLE_PROTOCOLS, null))
                ?.mapNotNull { value -> DnsProtocol.entries.firstOrNull { it.name == value } }
                ?.toSet()
                ?: DEFAULT_HOME_VISIBLE_PROTOCOLS,
            hiddenProviderIds = readStringSet(prefs.getString(KEY_HOME_HIDDEN_PROVIDER_IDS, null)) ?: emptySet(),
            visibleProviderIds = readStringSet(prefs.getString(KEY_HOME_VISIBLE_PROVIDER_IDS, null)) ?: emptySet()
        )
    }

    fun setHomeProviderVisibility(
        context: Context,
        visibility: HomeProviderVisibility,
        dataset: RuleDataset = RuleDataset.NORMAL
    ) {
        datasetPrefs(context, dataset)
            .edit()
            .putString(KEY_HOME_VISIBLE_PROTOCOLS, writeStringSet(visibility.visibleProtocols.map { it.name }.toSet()))
            .putString(KEY_HOME_HIDDEN_PROVIDER_IDS, writeStringSet(visibility.hiddenProviderIds))
            .putString(KEY_HOME_VISIBLE_PROVIDER_IDS, writeStringSet(visibility.visibleProviderIds))
            .apply()
    }

    fun getPresetDnsService(context: Context, dataset: RuleDataset = RuleDataset.NORMAL): PresetDnsService {
        val value = datasetPrefs(context, dataset)
            .getString(KEY_PRESET_DNS_SERVICE, null)
        return PresetDnsService.fromStorageValue(value)
    }

    fun setPresetDnsService(context: Context, service: PresetDnsService, dataset: RuleDataset = RuleDataset.NORMAL) {
        datasetPrefs(context, dataset)
            .edit()
            .putString(KEY_PRESET_DNS_SERVICE, service.name)
            .apply()
    }
}
