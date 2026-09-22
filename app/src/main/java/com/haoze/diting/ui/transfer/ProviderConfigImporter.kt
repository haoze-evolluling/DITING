package com.haoze.diting.ui.transfer

import com.haoze.diting.ui.HomeProviderVisibility
import com.haoze.diting.ui.settings.ResolutionSettingsStore
import com.haoze.diting.vpn.DnsProtocol
import com.haoze.diting.vpn.DnsProvider

/**
 * Handles importing DNS providers, resolution modes, and provider reference bindings.
 */
internal class ProviderConfigImporter(private val session: ImportSessionContext) {

    private val context get() = session.context

    fun importProvidersAndResolution(config: TransferConfig) {
        val existingUserProviders = DnsProvider.loadUserProviders(context)
        val existingProviderKeys = existingUserProviders.map(::providerKey).toMutableSet()
        val providerKeyToIdMap = mutableMapOf<String, String>()
        existingUserProviders.forEach { provider ->
            providerKeyToIdMap[providerKey(provider)] = provider.id
        }

        config.providers.forEach { provider ->
            val item = "DNS 服务商：${provider.name}"
            val key = providerKey(provider)
            if (!existingProviderKeys.add(key)) {
                session.skipped++
                val detail = "DNS 服务商：${provider.name} [${provider.protocol.name}]"
                session.skippedDetails.add(detail)
                session.complete(item, "跳过 $detail (已存在)")
            } else {
                val created = DnsProvider.addUserProvider(
                    context, provider.name, provider.protocol, provider.url, provider.host, provider.port
                )
                providerKeyToIdMap[key] = created.id
                session.added++
                val detail = "DNS 服务商：${provider.name} [${provider.protocol.name}]"
                session.addedDetails.add(detail)
                session.complete(item, "新增 $detail")
            }
        }

        // Restore provider selection & resolution mode if present
        val allRuntimeProviders = DnsProvider.loadRuntimeProviders(context)
        fun resolveProviderRef(ref: ImportedProviderRef): String? {
            if (ref.isPreset) {
                return DnsProvider.PRESETS.firstOrNull { it.id == ref.id || (it.name == ref.name && it.protocol == ref.protocol) }?.id
            }
            val key = when (ref.protocol) {
                DnsProtocol.DOH -> "${ref.protocol.name}:${ref.url.lowercase()}"
                else -> "${ref.protocol.name}:${ref.host.lowercase()}:${ref.port}"
            }
            return providerKeyToIdMap[key]
                ?: allRuntimeProviders.firstOrNull { it.name == ref.name && it.protocol == ref.protocol }?.id
        }

        config.selectedProvider?.let { ref ->
            resolveProviderRef(ref)?.let { resolvedId ->
                DnsProvider.saveSelected(context, resolvedId)
                val detail = "首选 DNS 服务商 -> ${ref.name}"
                session.addUpdatedSetting(detail, "设置 $detail")
            }
        }
        config.resolutionMode?.let { mode ->
            ResolutionSettingsStore.setDnsResolutionMode(context, mode)
            val detail = "DNS 解析模式 -> ${mode.displayName}"
            session.addUpdatedSetting(detail, "设置 $detail")
        }
        if (config.raceProviderRefs.isNotEmpty()) {
            val resolvedIds = config.raceProviderRefs.mapNotNull(::resolveProviderRef).toSet()
            if (resolvedIds.isNotEmpty()) {
                ResolutionSettingsStore.setRaceProviderIds(context, resolvedIds)
                val detail = "抢答模式 DNS 节点 (${resolvedIds.size} 个)"
                session.addUpdatedSetting(detail, "更新 $detail")
            }
        }
        if (config.smartPredictionProviderRefs.isNotEmpty()) {
            val resolvedIds = config.smartPredictionProviderRefs.mapNotNull(::resolveProviderRef).toSet()
            if (resolvedIds.isNotEmpty()) {
                ResolutionSettingsStore.setSmartPredictionProviderIds(context, resolvedIds)
                val detail = "智能预测 DNS 节点 (${resolvedIds.size} 个)"
                session.addUpdatedSetting(detail, "更新 $detail")
            }
        }
        if (config.parallelRaceProviderRefs.isNotEmpty()) {
            val resolvedIds = config.parallelRaceProviderRefs.mapNotNull(::resolveProviderRef).toSet()
            if (resolvedIds.isNotEmpty()) {
                ResolutionSettingsStore.setParallelRaceProviderIds(context, resolvedIds)
                val detail = "并行抢答 DNS 节点 (${resolvedIds.size} 个)"
                session.addUpdatedSetting(detail, "更新 $detail")
            }
        }
        if (config.primaryBackupProviderRefs.isNotEmpty()) {
            val resolvedIds = config.primaryBackupProviderRefs.mapNotNull(::resolveProviderRef)
            if (resolvedIds.isNotEmpty()) {
                ResolutionSettingsStore.setPrimaryBackupProviderIds(context, resolvedIds)
                val detail = "主备模式 DNS 节点 (${resolvedIds.size} 个)"
                session.addUpdatedSetting(detail, "更新 $detail")
            }
        }
        config.presetDnsService?.let { service ->
            ResolutionSettingsStore.setPresetDnsService(context, service)
            val detail = "预置 DNS 服务 -> ${service.displayName}"
            session.addUpdatedSetting(detail, "设置 $detail")
        }
        config.homeProviderVisibility?.let { visibility ->
            val hiddenIds = visibility.hiddenProviderRefs.mapNotNull(::resolveProviderRef).toSet()
            val visibleIds = visibility.visibleProviderRefs.mapNotNull(::resolveProviderRef).toSet()
            ResolutionSettingsStore.setHomeProviderVisibility(
                context,
                HomeProviderVisibility(
                    visibleProtocols = visibility.visibleProtocols,
                    hiddenProviderIds = hiddenIds,
                    visibleProviderIds = visibleIds
                )
            )
            val detail = "首页服务商卡片可见性设置"
            session.addUpdatedSetting(detail, "更新 $detail")
        }
        config.raceTestDomain?.takeIf { it.isNotBlank() }?.let { domain ->
            ResolutionSettingsStore.setRaceTestDomain(context, domain)
            val detail = "抢答测速域名 -> $domain"
            session.addUpdatedSetting(detail, "设置 $detail")
        }
    }

    private fun providerKey(provider: DnsProvider): String = providerKey(
        ImportedProvider(provider.name, provider.protocol, provider.url, provider.host, provider.port)
    )

    private fun providerKey(provider: ImportedProvider): String = when (provider.protocol) {
        DnsProtocol.DOH -> "${provider.protocol.name}:${provider.url.lowercase()}"
        else -> "${provider.protocol.name}:${provider.host.lowercase()}:${provider.port}"
    }
}
