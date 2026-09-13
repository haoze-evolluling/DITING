package com.haoze.dnssr.ui.settings

import android.content.Context
import com.haoze.dnssr.vpn.BootstrapIpDefaults
import com.haoze.dnssr.vpn.BootstrapIpEntry
import com.haoze.dnssr.vpn.BootstrapIpValidator
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

object BootstrapDnsSettingsStore {
    const val KEY_BOOTSTRAP_ENABLED = "bootstrap_enabled"
    const val KEY_BOOTSTRAP_PRESET_IDS = "bootstrap_preset_ids"
    const val KEY_BOOTSTRAP_CUSTOM_JSON = "bootstrap_custom_json"

    private const val DEFAULT_BOOTSTRAP_ENABLED = true
    private val DEFAULT_BOOTSTRAP_PRESET_IDS = setOf(
        "preset_volcengine",
        "preset_dnspod",
        "preset_alidns"
    )

    fun isBootstrapEnabled(context: Context): Boolean {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_BOOTSTRAP_ENABLED, DEFAULT_BOOTSTRAP_ENABLED)
    }

    fun setBootstrapEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_BOOTSTRAP_ENABLED, enabled)
            .apply()
    }

    fun loadBootstrapIpEntries(context: Context): List<BootstrapIpEntry> {
        val selectedPresetIds = getBootstrapPresetIds(context)
        val presets = BootstrapIpDefaults.PRESETS.map { entry ->
            entry.copy(enabled = entry.id in selectedPresetIds)
        }
        return presets + getCustomBootstrapIpEntries(context)
    }

    fun loadEnabledBootstrapIpEntries(context: Context): List<BootstrapIpEntry> {
        if (!isBootstrapEnabled(context)) return emptyList()
        return loadBootstrapIpEntries(context).filter { it.enabled }
    }

    fun setBootstrapIpEnabled(context: Context, id: String, enabled: Boolean) {
        val presetIds = BootstrapIpDefaults.PRESETS.map { it.id }.toSet()
        if (id in presetIds) {
            val selected = getBootstrapPresetIds(context).toMutableSet()
            if (enabled) selected.add(id) else selected.remove(id)
            setBootstrapPresetIds(context, selected)
            return
        }
        val updated = getCustomBootstrapIpEntries(context).map { entry ->
            if (entry.id == id) entry.copy(enabled = enabled) else entry
        }
        saveCustomBootstrapIpEntries(context, updated)
    }

    fun addCustomBootstrapIp(context: Context, name: String, ip: String): BootstrapIpEntry? {
        val trimmedIp = ip.trim()
        if (!BootstrapIpValidator.isValidIp(trimmedIp)) return null
        val entry = BootstrapIpEntry(
            id = "custom_${UUID.randomUUID()}",
            name = name.trim().ifBlank { trimmedIp },
            ip = trimmedIp,
            isPreset = false,
            enabled = true
        )
        saveCustomBootstrapIpEntries(context, getCustomBootstrapIpEntries(context) + entry)
        return entry
    }

    fun deleteCustomBootstrapIp(context: Context, id: String) {
        saveCustomBootstrapIpEntries(
            context,
            getCustomBootstrapIpEntries(context).filter { it.id != id }
        )
    }

    fun isValidBootstrapIp(ip: String?): Boolean {
        return BootstrapIpValidator.isValidIp(ip)
    }

    fun getBootstrapPresetIds(context: Context): Set<String> {
        val json = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_BOOTSTRAP_PRESET_IDS, null)
            ?: return DEFAULT_BOOTSTRAP_PRESET_IDS
        return try {
            val array = JSONArray(json)
            buildSet {
                for (i in 0 until array.length()) {
                    add(array.getString(i))
                }
            }
        } catch (_: Exception) {
            DEFAULT_BOOTSTRAP_PRESET_IDS
        }
    }

    fun setBootstrapPresetIds(context: Context, ids: Set<String>) {
        val validIds = BootstrapIpDefaults.PRESETS.map { it.id }.toSet()
        val array = JSONArray()
        ids.filter { it in validIds }.forEach { array.put(it) }
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_BOOTSTRAP_PRESET_IDS, array.toString())
            .apply()
    }

    private fun getCustomBootstrapIpEntries(context: Context): List<BootstrapIpEntry> {
        val json = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_BOOTSTRAP_CUSTOM_JSON, null)
            ?: return emptyList()
        return try {
            val array = JSONArray(json)
            buildList {
                for (i in 0 until array.length()) {
                    val obj = array.getJSONObject(i)
                    val ip = obj.optString("ip", "").trim()
                    if (!BootstrapIpValidator.isValidIp(ip)) continue
                    add(
                        BootstrapIpEntry(
                            id = obj.optString("id", "").takeIf { it.isNotBlank() } ?: "custom_${UUID.randomUUID()}",
                            name = obj.optString("name", ip).takeIf { it.isNotBlank() } ?: ip,
                            ip = ip,
                            isPreset = false,
                            enabled = obj.optBoolean("enabled", true)
                        )
                    )
                }
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun saveCustomBootstrapIpEntries(context: Context, entries: List<BootstrapIpEntry>) {
        val array = JSONArray()
        entries.filter { !it.isPreset && BootstrapIpValidator.isValidIp(it.ip) }.forEach { entry ->
            array.put(
                JSONObject().apply {
                    put("id", entry.id)
                    put("name", entry.name)
                    put("ip", entry.ip)
                    put("enabled", entry.enabled)
                }
            )
        }
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_BOOTSTRAP_CUSTOM_JSON, array.toString())
            .apply()
    }
}
