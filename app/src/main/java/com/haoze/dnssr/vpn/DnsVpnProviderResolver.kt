package com.haoze.dnssr.vpn

import android.content.Context
import android.content.Intent
import com.haoze.dnssr.ui.AppSettings
import com.haoze.dnssr.ui.DnsResolutionMode
import java.security.MessageDigest

/**
 * Resolves the effective DNS provider list from the start [Intent] and
 * [AppSettings].
 */
object DnsVpnProviderResolver {

    /**
     * Resolves the [DnsProvider] list that should take effect, from the Intent
     * extras or the persisted settings.
     */
    fun resolveDnsProviders(context: Context, intent: Intent?): List<DnsProvider> {
        val protocol = DnsProtocol.fromStorage(intent?.getStringExtra(DnsVpnService.EXTRA_DNS_PROTOCOL))
        val url = intent?.getStringExtra(DnsVpnService.EXTRA_DOH_URL)
        if (!url.isNullOrBlank()) {
            val name = intent.getStringExtra(DnsVpnService.EXTRA_DNS_NAME)?.takeIf { it.isNotBlank() } ?: "自定义"
            return listOf(
                DnsProvider(
                    id = runtimeCustomProviderId(url),
                    name = name,
                    protocol = DnsProtocol.DOH,
                    url = url,
                    isPreset = false
                )
            )
        }
        if (protocol == DnsProtocol.DOT || protocol == DnsProtocol.DNS) {
            val host = intent?.getStringExtra(DnsVpnService.EXTRA_DNS_HOST)
            if (!host.isNullOrBlank()) {
                val port = intent.getIntExtra(DnsVpnService.EXTRA_DNS_PORT, DnsProvider.DEFAULT_DOT_PORT)
                val name = intent.getStringExtra(DnsVpnService.EXTRA_DNS_NAME)?.takeIf { it.isNotBlank() } ?: "自定义"
                return listOf(
                    DnsProvider(
                        id = runtimeCustomProviderId("$host:$port"),
                        name = name,
                        protocol = protocol,
                        host = host,
                        port = port,
                        isPreset = false
                    )
                )
            }
        }
        when (AppSettings.getDnsResolutionMode(context)) {
            DnsResolutionMode.SINGLE -> Unit
            DnsResolutionMode.SMART_PREDICTION,
            DnsResolutionMode.PARALLEL_RACE -> {
                val ids = if (AppSettings.getDnsResolutionMode(context) == DnsResolutionMode.SMART_PREDICTION) {
                    AppSettings.getSmartPredictionProviderIds(context)
                } else {
                    AppSettings.getParallelRaceProviderIds(context)
                }
                val raceProviders = DnsProvider.loadRuntimeProviders(context).filter { it.id in ids }
                if (raceProviders.size >= 2) return raceProviders
            }
            DnsResolutionMode.PRIMARY_BACKUP -> {
                val byId = DnsProvider.loadRuntimeProviders(context).associateBy { it.id }
                val ordered = AppSettings.getPrimaryBackupProviderIds(context).mapNotNull(byId::get)
                if (ordered.size >= 2) return ordered
            }
        }
        return listOf(DnsProvider.loadSelected(context))
    }

    /**
     * Generates a unique runtime provider ID for a dynamically supplied custom
     * DNS URL/host.
     */
    fun runtimeCustomProviderId(url: String): String {
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(url.trim().toByteArray(Charsets.UTF_8))
        val suffix = digest.take(8).joinToString(separator = "") { byte ->
            "%02x".format(byte.toInt() and 0xff)
        }
        return "runtime_custom_$suffix"
    }
}
