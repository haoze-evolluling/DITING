package com.haoze.dnssr.vpn

import android.content.Context
import android.content.SharedPreferences
import com.haoze.dnssr.ui.AppSettings
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

enum class DnsProtocol(val label: String) {
    DNS("DNS"),
    DOH("DoH"),
    DOT("DoT");

    companion object {
        val MANAGED_PROTOCOLS = listOf(DNS, DOH, DOT)

        fun fromStorage(value: String?): DnsProtocol {
            return entries.firstOrNull { it.name.equals(value, ignoreCase = true) } ?: DOH
        }
    }
}

/**
 * DNS upstream provider. HTTP providers use [url]; DNS and DoT providers use [host] and [port].
 */
data class DnsProvider(
    val id: String,
    val name: String,
    val protocol: DnsProtocol = DnsProtocol.DOH,
    val url: String = "",
    val host: String = "",
    val port: Int = DEFAULT_DOT_PORT,
    val isPreset: Boolean = false
) {
    fun isUserProvider(): Boolean = !isPreset

    fun endpointLabel(): String {
        return when (protocol) {
            DnsProtocol.DNS -> "[${protocol.label}] $host:$port"
            DnsProtocol.DOH -> "[${protocol.label}] $url"
            DnsProtocol.DOT -> "[${protocol.label}] $host:$port"
        }
    }

    fun connectionHost(): String {
        return when (protocol) {
            DnsProtocol.DNS -> "$host:$port"
            DnsProtocol.DOH -> url
            DnsProtocol.DOT -> "$host:$port"
        }
    }

    companion object {
        const val DEFAULT_DOT_PORT = 853
        const val DEFAULT_DNS_PORT = 53

        private const val PREFS_NAME = "dns_vpn_prefs"
        private const val KEY_USER_PROVIDERS_JSON = "user_providers_json"
        private const val KEY_SELECTED_PROVIDER_ID = "selected_provider_id"
        private const val DEFAULT_SELECTED_PROVIDER_ID = "preset_alidns_dns"

        val PRESETS = listOf(
            DnsProvider(
                id = "preset_alidns_dns",
                name = "阿里云",
                protocol = DnsProtocol.DNS,
                host = "223.5.5.5",
                port = DEFAULT_DNS_PORT,
                isPreset = true
            ),
            DnsProvider(
                id = "preset_dnspod_dns",
                name = "腾讯云 DNSPod",
                protocol = DnsProtocol.DNS,
                host = "119.29.29.29",
                port = DEFAULT_DNS_PORT,
                isPreset = true
            ),
            DnsProvider(
                id = "preset_360_dns",
                name = "360",
                protocol = DnsProtocol.DNS,
                host = "101.226.4.6",
                port = DEFAULT_DNS_PORT,
                isPreset = true
            ),
            DnsProvider(
                id = "preset_onedns_dns",
                name = "OneDNS",
                protocol = DnsProtocol.DNS,
                host = "117.50.10.10",
                port = DEFAULT_DNS_PORT,
                isPreset = true
            ),
            DnsProvider(
                id = "preset_cloudflare_dns",
                name = "Cloudflare",
                protocol = DnsProtocol.DNS,
                host = "1.1.1.1",
                port = DEFAULT_DNS_PORT,
                isPreset = true
            ),
            DnsProvider(
                id = "preset_google_dns",
                name = "Google",
                protocol = DnsProtocol.DNS,
                host = "8.8.8.8",
                port = DEFAULT_DNS_PORT,
                isPreset = true
            ),
            DnsProvider(
                id = "preset_alidns_doh",
                name = "阿里云",
                protocol = DnsProtocol.DOH,
                url = "https://dns.alidns.com/dns-query",
                isPreset = true
            ),
            DnsProvider(
                id = "preset_dnspod_doh",
                name = "腾讯云 DNSPod",
                protocol = DnsProtocol.DOH,
                url = "https://doh.pub/dns-query",
                isPreset = true
            ),
            DnsProvider(
                id = "preset_360_doh",
                name = "360",
                protocol = DnsProtocol.DOH,
                url = "https://doh.360.cn/dns-query",
                isPreset = true
            ),
            DnsProvider(
                id = "preset_onedns_doh",
                name = "OneDNS",
                protocol = DnsProtocol.DOH,
                url = "https://doh.onedns.net/dns-query",
                isPreset = true
            ),
            DnsProvider(
                id = "preset_cloudflare_doh",
                name = "Cloudflare",
                protocol = DnsProtocol.DOH,
                url = "https://cloudflare-dns.com/dns-query",
                isPreset = true
            ),
            DnsProvider(
                id = "preset_google_doh",
                name = "Google",
                protocol = DnsProtocol.DOH,
                url = "https://dns.google/dns-query",
                isPreset = true
            ),
            DnsProvider(
                id = "preset_alidns_dot",
                name = "阿里云",
                protocol = DnsProtocol.DOT,
                host = "dns.alidns.com",
                port = DEFAULT_DOT_PORT,
                isPreset = true
            ),
            DnsProvider(
                id = "preset_dnspod_dot",
                name = "腾讯云 DNSPod",
                protocol = DnsProtocol.DOT,
                host = "dot.pub",
                port = DEFAULT_DOT_PORT,
                isPreset = true
            ),
            DnsProvider(
                id = "preset_360_dot",
                name = "360",
                protocol = DnsProtocol.DOT,
                host = "dot.360.cn",
                port = DEFAULT_DOT_PORT,
                isPreset = true
            ),
            DnsProvider(
                id = "preset_onedns_dot",
                name = "OneDNS",
                protocol = DnsProtocol.DOT,
                host = "dot.onedns.net",
                port = DEFAULT_DOT_PORT,
                isPreset = true
            ),
            DnsProvider(
                id = "preset_cloudflare_dot",
                name = "Cloudflare",
                protocol = DnsProtocol.DOT,
                host = "one.one.one.one",
                port = DEFAULT_DOT_PORT,
                isPreset = true
            ),
            DnsProvider(
                id = "preset_google_dot",
                name = "Google",
                protocol = DnsProtocol.DOT,
                host = "dns.google",
                port = DEFAULT_DOT_PORT,
                isPreset = true
            )
        )

        private fun prefs(context: Context): SharedPreferences {
            return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        }

        fun loadAll(context: Context): List<DnsProvider> {
            return PRESETS + loadUserProviders(context).filter { it.protocol in DnsProtocol.MANAGED_PROTOCOLS }
        }

        fun loadRuntimeProviders(context: Context): List<DnsProvider> {
            return loadAll(context)
        }

        fun loadSelected(context: Context): DnsProvider {
            val all = loadRuntimeProviders(context)
            val selectedId = prefs(context).getString(KEY_SELECTED_PROVIDER_ID, null)
            if (selectedId in LEGACY_DOH3_PRESET_IDS) {
                saveSelected(context, GOOGLE_DOH_PROVIDER_ID)
                return all.first { it.id == GOOGLE_DOH_PROVIDER_ID }
            }
            return all.find { it.id == selectedId }
                ?: all.find { it.id == DEFAULT_SELECTED_PROVIDER_ID }
                ?: PRESETS.first()
        }

        fun saveSelected(context: Context, id: String) {
            prefs(context).edit().putString(KEY_SELECTED_PROVIDER_ID, id).apply()
        }

        fun presetIdForProtocol(id: String, protocol: DnsProtocol): String? {
            val provider = PRESETS.firstOrNull { it.id == id } ?: return null
            if (provider.name !in SWITCHABLE_PRESET_PROVIDER_NAMES) return null
            return PRESETS.firstOrNull {
                it.name == provider.name && it.protocol == protocol
            }?.id
        }

        fun loadRaceProviderIds(context: Context): Set<String> {
            val all = loadRuntimeProviders(context)
            val allIds = all.map { it.id }.toSet()
            val ids = AppSettings.getRaceProviderIds(context).toMutableSet()
            return ids.filter { it in allIds }.toSet()
        }

        fun saveRaceProviderIds(context: Context, ids: Set<String>) {
            AppSettings.setRaceProviderIds(context, ids)
        }

        fun loadLatencyTestProviderIds(context: Context): Set<String> {
            val all = loadRuntimeProviders(context)
            val allIds = all.map { it.id }.toSet()
            val ids = AppSettings.getLatencyTestProviderIds(context).toMutableSet()
            return ids.filter { it in allIds }.toSet()
        }

        fun saveLatencyTestProviderIds(context: Context, ids: Set<String>) {
            AppSettings.setLatencyTestProviderIds(context, ids)
        }

        fun loadRaceProviders(context: Context): List<DnsProvider> {
            val ids = loadRaceProviderIds(context)
            return loadRuntimeProviders(context).filter { it.id in ids }
        }

        fun loadUserProviders(context: Context): List<DnsProvider> {
            val json = prefs(context).getString(KEY_USER_PROVIDERS_JSON, null) ?: return emptyList()
            return try {
                val array = JSONArray(json)
                var migratedLegacyProtocol = false
                val providers = buildList {
                    for (i in 0 until array.length()) {
                        val obj = array.getJSONObject(i)
                        if (obj.optString("protocol").equals(LEGACY_DOH3_PROTOCOL, ignoreCase = true)) {
                            migratedLegacyProtocol = true
                        }
                        obj.toDnsProvider()?.let(::add)
                    }
                }
                if (migratedLegacyProtocol) saveUserProviders(context, providers)
                providers
            } catch (_: Exception) {
                emptyList()
            }
        }

        fun saveUserProviders(context: Context, providers: List<DnsProvider>) {
            val array = JSONArray()
            providers.forEach { provider ->
                array.put(
                    JSONObject().apply {
                        put("id", provider.id)
                        put("name", provider.name)
                        put("protocol", provider.protocol.name)
                        put("url", provider.url)
                        put("host", provider.host)
                        put("port", provider.port)
                    }
                )
            }
            prefs(context).edit()
                .putString(KEY_USER_PROVIDERS_JSON, array.toString())
                .apply()
        }

        fun addUserProvider(
            context: Context,
            name: String,
            protocol: DnsProtocol,
            url: String,
            host: String,
            port: Int
        ): DnsProvider {
            val provider = DnsProvider(
                id = UUID.randomUUID().toString(),
                name = name.trim(),
                protocol = protocol,
                url = url.trim(),
                host = host.trim(),
                port = port,
                isPreset = false
            )
            val updated = loadUserProviders(context) + provider
            saveUserProviders(context, updated)
            return provider
        }

        fun updateUserProvider(context: Context, provider: DnsProvider) {
            val updated = loadUserProviders(context).map {
                if (it.id == provider.id) provider else it
            }
            saveUserProviders(context, updated)
        }

        fun deleteUserProvider(context: Context, id: String) {
            val prefs = prefs(context)
            val updated = loadUserProviders(context).filter { it.id != id }
            saveUserProviders(context, updated)
            if (prefs.getString(KEY_SELECTED_PROVIDER_ID, null) == id) {
                saveSelected(context, DEFAULT_SELECTED_PROVIDER_ID)
            }
            val raceIds = AppSettings.getRaceProviderIds(context).toMutableSet()
            if (raceIds.remove(id)) {
                AppSettings.setRaceProviderIds(context, raceIds)
            }
            val primaryBackupIds = AppSettings.getPrimaryBackupProviderIds(context).filterNot { it == id }
            AppSettings.setPrimaryBackupProviderIds(context, primaryBackupIds)
            AppSettings.removeProviderFromResolutionModes(context, id)
            val latencyIds = AppSettings.getLatencyTestProviderIds(context).toMutableSet()
            if (latencyIds.remove(id)) {
                AppSettings.setLatencyTestProviderIds(context, latencyIds)
            }
            ProviderHealthStore.remove(context, id)
        }

        fun isValidDohUrl(url: String): Boolean {
            val trimmed = url.trim()
            return trimmed.isNotBlank() && trimmed.startsWith("https://", ignoreCase = true)
        }

        fun isValidDotHost(host: String): Boolean {
            val trimmed = host.trim()
            return trimmed.isNotBlank() && !isIpLiteral(trimmed) && trimmed.contains(".")
        }

        fun isValidDnsHost(host: String): Boolean {
            val trimmed = host.trim()
            return trimmed.isNotBlank() && (isIpLiteral(trimmed) || trimmed.contains("."))
        }

        fun isValidDotPort(port: Int): Boolean {
            return port in 1..65535
        }

        private fun JSONObject.toDnsProvider(): DnsProvider? {
            val protocolValue = optString("protocol", "").takeIf { it.isNotBlank() }
            val protocol = if (protocolValue.equals(LEGACY_DOH3_PROTOCOL, ignoreCase = true)) {
                DnsProtocol.DOH
            } else {
                DnsProtocol.entries.firstOrNull { it.name.equals(protocolValue, ignoreCase = true) }
            } ?: return null
            if (protocol !in DnsProtocol.MANAGED_PROTOCOLS) return null
            return DnsProvider(
                id = getString("id"),
                name = getString("name"),
                protocol = protocol,
                url = optString("url", ""),
                host = optString("host", ""),
                port = optInt("port", DEFAULT_DOT_PORT).takeIf { isValidDotPort(it) } ?: DEFAULT_DOT_PORT,
                isPreset = false
            )
        }

        fun isIpLiteral(value: String): Boolean {
            val trimmed = value.trim()
            val ipv4 = Regex("""^(\d{1,3}\.){3}\d{1,3}$""")
            if (ipv4.matches(trimmed)) {
                return trimmed.split(".").all { part -> part.toIntOrNull() in 0..255 }
            }
            if (trimmed.contains(":")) return true
            return false
        }

        private const val LEGACY_DOH3_PROTOCOL = "DOH3"
        const val GOOGLE_DOH_PROVIDER_ID = "preset_google_doh"
        val LEGACY_DOH3_PRESET_IDS = setOf(
            "preset_alidns_doh3",
            "preset_dnspod_doh3",
            "preset_cloudflare_doh3",
            "preset_google_doh3"
        )
        private val SWITCHABLE_PRESET_PROVIDER_NAMES = setOf("阿里云", "腾讯云 DNSPod")
    }
}
