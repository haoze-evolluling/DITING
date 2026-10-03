package com.haoze.diting.vpn

import com.haoze.diting.ui.DnsResolutionMode
import com.haoze.diting.vpn.cache.DnsCachePolicy
import org.json.JSONArray
import org.json.JSONObject

@ConsistentCopyVisibility
data class HttpsDnsConfigSnapshot private constructor(
    val providers: List<DnsProvider>,
    val mode: DnsResolutionMode,
    val blockResponseMode: BlockResponseMode,
    val dynamicBlockResponseConfig: DynamicBlockResponseConfig,
    val cachePolicy: DnsCachePolicy,
    val bootstrapEnabled: Boolean = false,
    val bootstrapIps: List<BootstrapIpEntry> = emptyList()
) {
    companion object {
        fun create(
            providers: List<DnsProvider>,
            mode: DnsResolutionMode,
            blockResponseMode: BlockResponseMode,
            dynamicBlockResponseConfig: DynamicBlockResponseConfig,
            cachePolicy: DnsCachePolicy,
            bootstrapEnabled: Boolean = false,
            bootstrapIps: List<BootstrapIpEntry> = emptyList()
        ): HttpsDnsConfigSnapshot {
            require(providers.isNotEmpty()) { "DNS provider list must not be empty" }
            val selected = if (mode == DnsResolutionMode.SINGLE) listOf(providers.first()) else providers
            return HttpsDnsConfigSnapshot(
                selected,
                mode,
                blockResponseMode,
                dynamicBlockResponseConfig,
                cachePolicy,
                bootstrapEnabled,
                bootstrapIps
            )
        }
    }
}

internal fun HttpsDnsConfigSnapshot.toJson(): String = JSONObject()
    .put("mode", mode.storageValue)
    .put("blockResponse", blockResponseMode.goValue)
    .put("dynamicResponse", JSONObject()
        .put("enabled", dynamicBlockResponseConfig.enabled)
        .put("requestThreshold", dynamicBlockResponseConfig.requestThreshold)
        .put("windowSeconds", dynamicBlockResponseConfig.windowSeconds)
        .put("nxDomainDurationSeconds", dynamicBlockResponseConfig.nxDomainDurationSeconds))
    .put("cache", JSONObject()
        .put("enabled", cachePolicy.enabled)
        .put("mode", cachePolicy.mode.storageValue)
        .put("maxTtlSeconds", cachePolicy.maxTtlSeconds)
        .put("fixedTtlSeconds", cachePolicy.fixedTtlSeconds)
        .put("minTtlEnabled", cachePolicy.minTtlEnabled)
        .put("minTtlSeconds", cachePolicy.minTtlSeconds)
        .put("staleFallbackEnabled", cachePolicy.staleFallbackEnabled)
        .put("staleFallbackSeconds", cachePolicy.staleFallbackSeconds)
        .put("negativeTtlEnabled", cachePolicy.negativeTtlEnabled)
        .put("negativeTtlSeconds", cachePolicy.negativeTtlSeconds))
    .put("providers", JSONArray().apply {

        providers.forEach { provider ->
            put(JSONObject()
                .put("id", provider.id)
                .put("protocol", provider.protocol.goProtocol)
                .put("server", when (provider.protocol) {
                    DnsProtocol.DNS, DnsProtocol.DOT -> provider.hostPort()
                    DnsProtocol.DOH -> ""
                })
                .put("url", provider.url))
        }
    })
    .put("bootstrap", JSONObject()
        .put("enabled", bootstrapEnabled)
        .put("ips", JSONArray().apply {
            bootstrapIps.forEach { entry ->
                put(JSONObject()
                    .put("id", entry.id)
                    .put("name", entry.name)
                    .put("ip", entry.ip))
            }
        }))
    .toString()

private val DnsProtocol.goProtocol: String
    get() = when (this) {
        DnsProtocol.DNS -> "PLAIN"
        DnsProtocol.DOH -> "DOH"
        DnsProtocol.DOT -> "DOT"
    }

private fun DnsProvider.hostPort(): String =
    if (host.contains(':') && !host.startsWith('[')) "[$host]:$port" else "$host:$port"

private val BlockResponseMode.goValue: String
    get() = when (this) {
        BlockResponseMode.NXDOMAIN -> "NXDOMAIN"
        BlockResponseMode.NODATA -> "NODATA"
        BlockResponseMode.REFUSED -> "REFUSED"
        BlockResponseMode.ZERO_ADDRESS -> "CUSTOM_IP"
    }
