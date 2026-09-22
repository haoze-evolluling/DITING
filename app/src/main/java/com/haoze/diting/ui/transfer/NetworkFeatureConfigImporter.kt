package com.haoze.diting.ui.transfer

import com.haoze.diting.ui.OutboundProxyConfig
import com.haoze.diting.ui.OutboundProxyProtocol
import com.haoze.diting.ui.settings.BootstrapDnsSettingsStore
import com.haoze.diting.ui.settings.DnsCacheSettingsStore
import com.haoze.diting.ui.settings.OutboundProxySettingsStore
import com.haoze.diting.vpn.cache.DnsCacheMode
import com.haoze.diting.vpn.cache.DnsCachePreset

/**
 * Handles importing Bootstrap DNS, DNS cache policies, and Outbound Proxy configurations.
 */
internal class NetworkFeatureConfigImporter(private val session: ImportSessionContext) {

    private val context get() = session.context

    fun importNetworkFeatures(config: TransferConfig) {
        if (config.bootstrapEnabled != null) {
            BootstrapDnsSettingsStore.setBootstrapEnabled(context, config.bootstrapEnabled)
            val detail = "Bootstrap IP 引导 -> ${if (config.bootstrapEnabled) "已启用" else "已禁用"}"
            session.addUpdatedSetting(detail, "设置 $detail")
        }

        val existingIps = BootstrapDnsSettingsStore.loadBootstrapIpEntries(context)
            .filterNot { it.isPreset }.map { it.ip.lowercase() }.toMutableSet()
        config.bootstrapIps.forEach { entry ->
            val item = "Bootstrap IP：${entry.name}"
            val detail = "Bootstrap IP：${entry.name} (${entry.ip})"
            if (!existingIps.add(entry.ip.lowercase())) {
                session.skipped++
                session.skippedDetails.add(detail)
                session.complete(item, "跳过 $detail (已存在)")
            } else {
                val saved = BootstrapDnsSettingsStore.addCustomBootstrapIp(context, entry.name, entry.ip)
                if (saved == null) {
                    session.failed++
                    session.failedDetails.add(detail)
                    session.complete(item, "添加 $detail 失败")
                } else {
                    BootstrapDnsSettingsStore.setBootstrapIpEnabled(context, saved.id, entry.enabled)
                    session.added++
                    session.addedDetails.add(detail)
                    session.complete(item, "新增 $detail")
                }
            }
        }

        if (config.bootstrapPresetIds != null) {
            val validPresets = BootstrapDnsSettingsStore.getBootstrapPresetIds(context)
            if (validPresets != config.bootstrapPresetIds) {
                BootstrapDnsSettingsStore.setBootstrapPresetIds(context, config.bootstrapPresetIds)
                val detail = "预置 Bootstrap 节点状态"
                session.addUpdatedSetting(detail, "更新 $detail")
            }
            session.complete("预置 Bootstrap IP 节点", "已同步预置 Bootstrap 节点启用状态")
        }

        if (config.dnsCache != null) {
            val cache = config.dnsCache
            DnsCacheSettingsStore.setCacheEnabled(context, cache.enabled)
            cache.preset?.let { presetVal ->
                DnsCachePreset.fromStorageValue(presetVal)?.let { preset ->
                    DnsCacheSettingsStore.setDnsCachePreset(context, preset)
                }
            }
            val currentPolicy = DnsCacheSettingsStore.getDnsCachePolicy(context)
            val updatedPolicy = currentPolicy.copy(
                enabled = cache.enabled,
                mode = cache.mode?.let { DnsCacheMode.fromStorageValue(it) } ?: currentPolicy.mode,
                maxTtlSeconds = cache.maxTtlSeconds ?: currentPolicy.maxTtlSeconds,
                fixedTtlSeconds = cache.fixedTtlSeconds ?: currentPolicy.fixedTtlSeconds,
                minTtlEnabled = cache.minTtlEnabled ?: currentPolicy.minTtlEnabled,
                minTtlSeconds = cache.minTtlSeconds ?: currentPolicy.minTtlSeconds,
                staleFallbackEnabled = cache.staleFallbackEnabled ?: currentPolicy.staleFallbackEnabled,
                staleFallbackSeconds = cache.staleFallbackSeconds ?: currentPolicy.staleFallbackSeconds
            )
            DnsCacheSettingsStore.setDnsCachePolicy(context, updatedPolicy)
            session.dnsCacheUpdated = true
            val detail = "DNS 缓存策略"
            session.addUpdatedSetting(detail, "更新 $detail")
            session.complete("DNS 缓存配置", "已应用 DNS 缓存策略")
        }

        if (config.outboundProxy != null) {
            val proxy = config.outboundProxy
            OutboundProxySettingsStore.setOutboundProxyConfig(
                context,
                OutboundProxyConfig(
                    enabled = proxy.enabled,
                    protocol = OutboundProxyProtocol.fromStorageValue(proxy.protocol),
                    host = proxy.host,
                    port = proxy.port,
                    username = proxy.username,
                    password = proxy.password,
                    proxyAppPackage = proxy.proxyAppPackage
                )
            )
            session.outboundProxyUpdated = true
            val detail = "出站代理配置 -> ${if (proxy.enabled) "已启用" else "已禁用"} (${proxy.protocol}://${proxy.host}:${proxy.port})"
            session.addUpdatedSetting(detail, "设置 $detail")
            session.complete("出站代理配置", "已应用出站代理配置")
        }
    }
}
