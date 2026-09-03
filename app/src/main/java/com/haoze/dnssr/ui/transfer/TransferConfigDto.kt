package com.haoze.dnssr.ui.transfer

import com.haoze.dnssr.data.entity.RuleScope
import com.haoze.dnssr.data.entity.SubscriptionKind
import com.haoze.dnssr.ui.DnsResolutionMode
import com.haoze.dnssr.ui.PresetDnsService
import com.haoze.dnssr.vpn.BlockResponseMode
import com.haoze.dnssr.vpn.DnsProtocol

data class TransferConfig(
    val formatVersion: Int = ConfigTransferParser.FORMAT_VERSION,
    val providers: List<ImportedProvider> = emptyList(),
    val selectedProvider: ImportedProviderRef? = null,
    val resolutionMode: DnsResolutionMode? = null,
    val presetDnsService: PresetDnsService? = null,
    val homeProviderVisibility: ImportedHomeProviderVisibility? = null,
    val raceTestDomain: String? = null,
    val raceProviderRefs: List<ImportedProviderRef> = emptyList(),
    val smartPredictionProviderRefs: List<ImportedProviderRef> = emptyList(),
    val parallelRaceProviderRefs: List<ImportedProviderRef> = emptyList(),
    val primaryBackupProviderRefs: List<ImportedProviderRef> = emptyList(),
    val latencyTestProviderRefs: List<ImportedProviderRef> = emptyList(),
    val bootstrapEnabled: Boolean? = null,
    val bootstrapIps: List<ImportedBootstrap> = emptyList(),
    val bootstrapPresetIds: Set<String>? = null,
    val dnsCache: ImportedDnsCache? = null,
    val outboundProxy: ImportedOutboundProxy? = null,
    val mirrorTemplates: List<ImportedMirrorTemplate> = emptyList(),
    val subscriptionGroups: List<ImportedSubscriptionGroup> = emptyList(),
    val subscriptions: List<ImportedSubscription> = emptyList(),
    val customBlockRules: List<ImportedCustomBlockRule> = emptyList(),
    val customAllowRules: List<ImportedCustomAllowRule> = emptyList(),
    val customRewriteDomainRules: List<ImportedCustomRewriteRule> = emptyList(),
    val customRewriteCnameRules: List<ImportedCustomRewriteRule> = emptyList(),
    val customAddressRules: List<ImportedCustomUrlRule> = emptyList(),
    val excludedApps: Set<String> = emptySet(),
    val blockedApps: Set<String> = emptySet(),
    val blockedAppsEnabled: Boolean = false,
    val appAllowlistRules: Map<String, Set<String>> = emptyMap(),
    val appAllowlistEnabled: Boolean = false,
    val httpInspection: ImportedHttpInspection? = null,
    val domainRulesEnabled: Boolean? = null,
    val addressRulesEnabled: Boolean? = null,
    val encryptedDnsBlockingEnabled: Boolean? = null,
    val blockResponseMode: BlockResponseMode? = null,
    val dynamicBlockResponse: ImportedDynamicBlockResponse? = null,
    val allowEditDefaultWhitelist: Boolean? = null,
    val subscriptionAutoUpdate: ImportedSubscriptionAutoUpdate? = null,
    val appearance: ImportedAppearance? = null,
    val systemSettings: ImportedSystemSettings? = null
)

data class ImportedProvider(
    val name: String,
    val protocol: DnsProtocol,
    val url: String,
    val host: String,
    val port: Int
)

data class ImportedProviderRef(
    val id: String,
    val name: String,
    val protocol: DnsProtocol,
    val url: String = "",
    val host: String = "",
    val port: Int = 853,
    val isPreset: Boolean = false
)

data class ImportedHomeProviderVisibility(
    val visibleProtocols: Set<DnsProtocol>,
    val hiddenProviderRefs: List<ImportedProviderRef>,
    val visibleProviderRefs: List<ImportedProviderRef>
)

data class ImportedBootstrap(val name: String, val ip: String, val enabled: Boolean)

data class ImportedDnsCache(
    val enabled: Boolean,
    val preset: String? = null,
    val mode: String? = null,
    val maxTtlSeconds: Long? = null,
    val fixedTtlSeconds: Long? = null,
    val minTtlEnabled: Boolean? = null,
    val minTtlSeconds: Long? = null,
    val staleFallbackEnabled: Boolean? = null,
    val staleFallbackSeconds: Long? = null
)

data class ImportedOutboundProxy(
    val enabled: Boolean,
    val protocol: String,
    val host: String,
    val port: Int,
    val username: String = "",
    val password: String = "",
    val proxyAppPackage: String = ""
)

data class ImportedDynamicBlockResponse(
    val enabled: Boolean,
    val requestThreshold: Int,
    val windowSeconds: Int,
    val nxDomainDurationSeconds: Int
)

data class ImportedSubscriptionAutoUpdate(
    val enabled: Boolean,
    val intervalHours: Int
)

data class ImportedHttpInspection(
    val enabled: Boolean,
    val http3Enabled: Boolean = false,
    val appPackages: Set<String> = emptySet()
)

data class ImportedAppearance(
    val appThemeMode: String? = null,
    val themeColorStyle: String? = null,
    val homeComponentOpacity: Float? = null,
    val homePowerButtonOpacity: Float? = null,
    val homeProviderSelectorOpacity: Float? = null,
    val homeModeButtonOpacity: Float? = null,
    val homePoemOpacity: Float? = null,
    val homeDnsDetailOpacity: Float? = null,
    val homeSentenceRunning: String? = null,
    val homeSentenceStopped: String? = null,
    val liquidGlassBottomBarEnabled: Boolean? = null
)

data class ImportedSystemSettings(
    val bypassLanEnabled: Boolean? = null,
    val hideFromRecentsEnabled: Boolean? = null,
    val logRetentionDays: Int? = null,
    val dnsLogMode: String? = null,
    val floatingLogEnabled: Boolean? = null,
    val floatingLogPanelSize: Int? = null,
    val appTrafficStatsEnabled: Boolean? = null,
    val trafficStatsRetentionDays: Int? = null,
    val trafficStatsHideSystemApps: Boolean? = null,
    val disableStartupUpdateCheck: Boolean? = null,
    val appLanguageMode: String? = null,
    val persistentNotificationEnabled: Boolean? = null,
    val trafficSpeedEnabled: Boolean? = null,
    val customRunningNotificationText: String? = null,
    val customStoppedNotificationText: String? = null
)

data class ImportedMirrorTemplate(val name: String, val template: String)

data class ImportedSubscriptionGroup(val name: String, val autoUpdateEnabled: Boolean)

data class ImportedSubscription(
    val name: String,
    val url: String,
    val scope: RuleScope,
    val groupName: String?,
    val kind: String = SubscriptionKind.UNIFIED,
    val mirrorTemplate: String? = null,
    val mirrorFallback: Boolean = true,
    val enabled: Boolean = true
)

data class ImportedCustomBlockRule(
    val pattern: String,
    val important: Boolean,
    val appScope: String?,
    val appInverted: Boolean,
    val rawLine: String,
    val enabled: Boolean = true
)

data class ImportedCustomAllowRule(
    val pattern: String,
    val important: Boolean,
    val appScope: String?,
    val appInverted: Boolean,
    val rawLine: String,
    val enabled: Boolean = true
)

data class ImportedCustomRewriteRule(
    val pattern: String,
    val targetType: String,
    val targetValue: String,
    val rawLine: String,
    val enabled: Boolean = true
)

data class ImportedCustomUrlRule(
    val pattern: String,
    val kind: String,
    val rawLine: String,
    val enabled: Boolean = true
)
