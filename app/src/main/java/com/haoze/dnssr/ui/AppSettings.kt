package com.haoze.dnssr.ui

import android.content.Context
import com.haoze.dnssr.ui.settings.AppearanceSettingsStore
import com.haoze.dnssr.ui.settings.AppRulesSettingsStore
import com.haoze.dnssr.ui.settings.BootstrapDnsSettingsStore
import com.haoze.dnssr.ui.settings.DnsCacheSettingsStore
import com.haoze.dnssr.ui.settings.OutboundProxySettingsStore
import com.haoze.dnssr.ui.settings.ResolutionSettingsStore
import com.haoze.dnssr.ui.settings.StartupSelfCheck
import com.haoze.dnssr.ui.settings.SystemSettingsStore
import com.haoze.dnssr.ui.theme.ThemeColorStyle
import com.haoze.dnssr.vpn.BlockResponseMode
import com.haoze.dnssr.vpn.BootstrapIpEntry
import com.haoze.dnssr.vpn.DynamicBlockResponseConfig
import com.haoze.dnssr.vpn.cache.DnsCachePolicy
import com.haoze.dnssr.vpn.cache.DnsCachePreset

/**
 * 应用设置统一门面，基于 SharedPreferences。
 * 业务具体存储逻辑已拆分至 [com.haoze.dnssr.ui.settings] 下各个专业模块。
 */
object AppSettings {
    const val KEY_LOG_RETENTION_DAYS = SystemSettingsStore.KEY_LOG_RETENTION_DAYS
    const val KEY_RACE_MODE_ENABLED = ResolutionSettingsStore.KEY_RACE_MODE_ENABLED
    const val KEY_RACE_PROVIDER_IDS = ResolutionSettingsStore.KEY_RACE_PROVIDER_IDS
    const val KEY_RACE_TEST_DOMAIN = ResolutionSettingsStore.KEY_RACE_TEST_DOMAIN
    const val KEY_LATENCY_TEST_PROVIDER_IDS = ResolutionSettingsStore.KEY_LATENCY_TEST_PROVIDER_IDS
    const val KEY_RACE_MODE_STRATEGY = ResolutionSettingsStore.KEY_RACE_MODE_STRATEGY
    const val KEY_BOOTSTRAP_ENABLED = BootstrapDnsSettingsStore.KEY_BOOTSTRAP_ENABLED
    const val KEY_BOOTSTRAP_PRESET_IDS = BootstrapDnsSettingsStore.KEY_BOOTSTRAP_PRESET_IDS
    const val KEY_BOOTSTRAP_CUSTOM_JSON = BootstrapDnsSettingsStore.KEY_BOOTSTRAP_CUSTOM_JSON
    const val KEY_HIDE_FROM_RECENTS_ENABLED = SystemSettingsStore.KEY_HIDE_FROM_RECENTS_ENABLED
    const val KEY_BYPASS_LAN_ENABLED = SystemSettingsStore.KEY_BYPASS_LAN_ENABLED
    const val DEFAULT_BYPASS_LAN_ENABLED = SystemSettingsStore.DEFAULT_BYPASS_LAN_ENABLED
    const val DEFAULT_HOME_COMPONENT_OPACITY = AppearanceSettingsStore.DEFAULT_HOME_COMPONENT_OPACITY

    // 外观与主题设置
    fun getAppThemeMode(context: Context): AppThemeMode = AppearanceSettingsStore.getAppThemeMode(context)
    fun setAppThemeMode(context: Context, mode: AppThemeMode) = AppearanceSettingsStore.setAppThemeMode(context, mode)
    fun getThemeColorStyle(context: Context): ThemeColorStyle = AppearanceSettingsStore.getThemeColorStyle(context)
    fun setThemeColorStyle(context: Context, style: ThemeColorStyle) = AppearanceSettingsStore.setThemeColorStyle(context, style)

    fun getHomeComponentOpacity(context: Context): Float = AppearanceSettingsStore.getHomeComponentOpacity(context)
    fun setHomeComponentOpacity(context: Context, opacity: Float) = AppearanceSettingsStore.setHomeComponentOpacity(context, opacity)
    fun getHomePowerButtonOpacity(context: Context): Float = AppearanceSettingsStore.getHomePowerButtonOpacity(context)
    fun setHomePowerButtonOpacity(context: Context, opacity: Float) = AppearanceSettingsStore.setHomePowerButtonOpacity(context, opacity)
    fun getHomeProviderSelectorOpacity(context: Context): Float = AppearanceSettingsStore.getHomeProviderSelectorOpacity(context)
    fun setHomeProviderSelectorOpacity(context: Context, opacity: Float) = AppearanceSettingsStore.setHomeProviderSelectorOpacity(context, opacity)
    fun getHomeModeButtonOpacity(context: Context): Float = AppearanceSettingsStore.getHomeModeButtonOpacity(context)
    fun setHomeModeButtonOpacity(context: Context, opacity: Float) = AppearanceSettingsStore.setHomeModeButtonOpacity(context, opacity)
    fun getHomePoemOpacity(context: Context): Float = AppearanceSettingsStore.getHomePoemOpacity(context)
    fun setHomePoemOpacity(context: Context, opacity: Float) = AppearanceSettingsStore.setHomePoemOpacity(context, opacity)
    fun getHomeDnsDetailOpacity(context: Context): Float = AppearanceSettingsStore.getHomeDnsDetailOpacity(context)
    fun setHomeDnsDetailOpacity(context: Context, opacity: Float) = AppearanceSettingsStore.setHomeDnsDetailOpacity(context, opacity)

    fun getHomeSentenceRunning(context: Context): String = AppearanceSettingsStore.getHomeSentenceRunning(context)
    fun getHomeSentenceStopped(context: Context): String = AppearanceSettingsStore.getHomeSentenceStopped(context)
    fun setHomeSentences(context: Context, running: String, stopped: String) =
        AppearanceSettingsStore.setHomeSentences(context, running, stopped)

    fun isCustomBackgroundEnabled(context: Context): Boolean = AppearanceSettingsStore.isCustomBackgroundEnabled(context)
    fun getCustomBackgroundUri(context: Context): String? = AppearanceSettingsStore.getCustomBackgroundUri(context)
    fun getCustomBackgroundUris(context: Context): List<String> = AppearanceSettingsStore.getCustomBackgroundUris(context)
    fun addCustomBackgroundUri(context: Context, uri: String) = AppearanceSettingsStore.addCustomBackgroundUri(context, uri)
    fun removeCustomBackgroundUri(context: Context, uri: String) = AppearanceSettingsStore.removeCustomBackgroundUri(context, uri)
    fun setCustomBackground(context: Context, enabled: Boolean, uri: String?) =
        AppearanceSettingsStore.setCustomBackground(context, enabled, uri)

    // 应用更新设置
    fun getAppUpdateDownloadPath(context: Context): String = SystemSettingsStore.getAppUpdateDownloadPath(context)
    fun getAppUpdateDownloadVersion(context: Context): String = SystemSettingsStore.getAppUpdateDownloadVersion(context)
    fun rememberAppUpdateDownload(context: Context, path: String, version: String) =
        SystemSettingsStore.rememberAppUpdateDownload(context, path, version)
    fun clearAppUpdateDownload(context: Context) = SystemSettingsStore.clearAppUpdateDownload(context)
    fun isStartupUpdateCheckDisabled(context: Context): Boolean = SystemSettingsStore.isStartupUpdateCheckDisabled(context)
    fun setStartupUpdateCheckDisabled(context: Context, disabled: Boolean) =
        SystemSettingsStore.setStartupUpdateCheckDisabled(context, disabled)

    // 排除应用与排序/过滤
    fun getExcludedAppPackages(context: Context): Set<String> = AppRulesSettingsStore.getExcludedAppPackages(context)
    fun setExcludedAppPackages(context: Context, packageNames: Set<String>) =
        AppRulesSettingsStore.setExcludedAppPackages(context, packageNames)
    fun getExcludedAppsFilter(context: Context): String = AppRulesSettingsStore.getExcludedAppsFilter(context)
    fun setExcludedAppsFilter(context: Context, filter: String) = AppRulesSettingsStore.setExcludedAppsFilter(context, filter)
    fun getExcludedAppsSort(context: Context): String = AppRulesSettingsStore.getExcludedAppsSort(context)
    fun setExcludedAppsSort(context: Context, sort: String) = AppRulesSettingsStore.setExcludedAppsSort(context, sort)

    // HTTP / HTTPS / HTTP3 抓包检查
    fun isHttpInspectionEnabled(context: Context): Boolean = AppRulesSettingsStore.isHttpInspectionEnabled(context)
    fun setHttpInspectionEnabled(context: Context, enabled: Boolean) = AppRulesSettingsStore.setHttpInspectionEnabled(context, enabled)
    fun getHttpInspectionAppPackages(context: Context): Set<String> = AppRulesSettingsStore.getHttpInspectionAppPackages(context)
    fun setHttpInspectionAppPackages(context: Context, packageNames: Set<String>) =
        AppRulesSettingsStore.setHttpInspectionAppPackages(context, packageNames)
    fun removeHttpInspectionAppPackages(context: Context, packageNames: Set<String>) =
        AppRulesSettingsStore.removeHttpInspectionAppPackages(context, packageNames)
    fun getHttpInspectionAppsFilter(context: Context): String = AppRulesSettingsStore.getHttpInspectionAppsFilter(context)
    fun setHttpInspectionAppsFilter(context: Context, filter: String) = AppRulesSettingsStore.setHttpInspectionAppsFilter(context, filter)
    fun getHttpInspectionAppsSort(context: Context): String = AppRulesSettingsStore.getHttpInspectionAppsSort(context)
    fun setHttpInspectionAppsSort(context: Context, sort: String) = AppRulesSettingsStore.setHttpInspectionAppsSort(context, sort)
    fun isHttpsInspectionReady(context: Context): Boolean = AppRulesSettingsStore.isHttpsInspectionReady(context)
    fun setHttpsInspectionReady(context: Context, ready: Boolean) = AppRulesSettingsStore.setHttpsInspectionReady(context, ready)
    fun isHttpsInspectionOperational(context: Context): Boolean = AppRulesSettingsStore.isHttpsInspectionOperational(context)
    fun isAddressRulesFullyOperational(context: Context): Boolean = AppRulesSettingsStore.isAddressRulesFullyOperational(context)
    fun checkAndUpdateHttpsInspectionReady(context: Context): Boolean = AppRulesSettingsStore.checkAndUpdateHttpsInspectionReady(context)
    fun isHttp3InspectionEnabled(context: Context): Boolean = AppRulesSettingsStore.isHttp3InspectionEnabled(context)
    fun setHttp3InspectionEnabled(context: Context, enabled: Boolean) = AppRulesSettingsStore.setHttp3InspectionEnabled(context, enabled)

    // 出站代理配置
    fun getOutboundProxyConfig(context: Context): OutboundProxyConfig = OutboundProxySettingsStore.getOutboundProxyConfig(context)
    fun setOutboundProxyConfig(context: Context, config: OutboundProxyConfig) =
        OutboundProxySettingsStore.setOutboundProxyConfig(context, config)
    fun setOutboundProxyStatus(context: Context, state: String, message: String) =
        OutboundProxySettingsStore.setOutboundProxyStatus(context, state, message)
    fun getOutboundProxyStatus(context: Context): Pair<String, String> = OutboundProxySettingsStore.getOutboundProxyStatus(context)

    // 新手引导与初始协议
    fun isSettingsGuideAcknowledged(context: Context, guideId: String): Boolean =
        SystemSettingsStore.isSettingsGuideAcknowledged(context, guideId)
    fun acknowledgeSettingsGuide(context: Context, guideId: String) =
        SystemSettingsStore.acknowledgeSettingsGuide(context, guideId)
    fun resetAllSettingsGuides(context: Context) = SystemSettingsStore.resetAllSettingsGuides(context)
    fun isInitialAgreementAccepted(context: Context): Boolean = SystemSettingsStore.isInitialAgreementAccepted(context)
    fun setInitialAgreementAccepted(context: Context) = SystemSettingsStore.setInitialAgreementAccepted(context)

    // 黑名单应用
    fun getBlockedAppPackages(context: Context): Set<String> = AppRulesSettingsStore.getBlockedAppPackages(context)
    fun isBlockedAppsEnabled(context: Context): Boolean = AppRulesSettingsStore.isBlockedAppsEnabled(context)
    fun setBlockedAppsEnabled(context: Context, enabled: Boolean) = AppRulesSettingsStore.setBlockedAppsEnabled(context, enabled)
    fun setBlockedAppPackages(context: Context, packageNames: Set<String>) =
        AppRulesSettingsStore.setBlockedAppPackages(context, packageNames)
    fun getBlockedAppsFilter(context: Context): String = AppRulesSettingsStore.getBlockedAppsFilter(context)
    fun setBlockedAppsFilter(context: Context, filter: String) = AppRulesSettingsStore.setBlockedAppsFilter(context, filter)
    fun getBlockedAppsSort(context: Context): String = AppRulesSettingsStore.getBlockedAppsSort(context)
    fun setBlockedAppsSort(context: Context, sort: String) = AppRulesSettingsStore.setBlockedAppsSort(context, sort)

    // 域名规则与地址规则总开关
    fun isDomainRulesEnabled(context: Context): Boolean = AppRulesSettingsStore.isDomainRulesEnabled(context)
    fun setDomainRulesEnabled(context: Context, enabled: Boolean) =
        AppRulesSettingsStore.setDomainRulesEnabled(context, enabled)
    fun isAddressRulesEnabled(context: Context): Boolean = AppRulesSettingsStore.isAddressRulesEnabled(context)
    fun setAddressRulesEnabled(context: Context, enabled: Boolean) =
        AppRulesSettingsStore.setAddressRulesEnabled(context, enabled)

    // 加密 DNS 拦截
    fun isEncryptedDnsBlockingEnabled(context: Context): Boolean = AppRulesSettingsStore.isEncryptedDnsBlockingEnabled(context)
    fun setEncryptedDnsBlockingEnabled(context: Context, enabled: Boolean) =
        AppRulesSettingsStore.setEncryptedDnsBlockingEnabled(context, enabled)

    // DNS 缓存策略
    fun isCacheEnabled(context: Context): Boolean = DnsCacheSettingsStore.isCacheEnabled(context)
    fun setCacheEnabled(context: Context, enabled: Boolean) = DnsCacheSettingsStore.setCacheEnabled(context, enabled)
    fun getDnsCachePolicy(context: Context): DnsCachePolicy = DnsCacheSettingsStore.getDnsCachePolicy(context)
    fun getDnsCachePreset(context: Context): DnsCachePreset = DnsCacheSettingsStore.getDnsCachePreset(context)
    fun setDnsCachePreset(context: Context, preset: DnsCachePreset) = DnsCacheSettingsStore.setDnsCachePreset(context, preset)
    fun setDnsCachePolicy(context: Context, policy: DnsCachePolicy) = DnsCacheSettingsStore.setDnsCachePolicy(context, policy)

    // 日志与悬浮窗
    fun logRetentionDays(context: Context): Int = SystemSettingsStore.logRetentionDays(context)
    fun setLogRetentionDays(context: Context, days: Int) = SystemSettingsStore.setLogRetentionDays(context, days)
    fun getDnsLogMode(context: Context): DnsLogMode = SystemSettingsStore.getDnsLogMode(context)
    fun setDnsLogMode(context: Context, mode: DnsLogMode) = SystemSettingsStore.setDnsLogMode(context, mode)
    fun isFloatingLogEnabled(context: Context): Boolean = SystemSettingsStore.isFloatingLogEnabled(context)
    fun setFloatingLogEnabled(context: Context, enabled: Boolean) = SystemSettingsStore.setFloatingLogEnabled(context, enabled)
    fun getFloatingLogPanelSize(context: Context): Int = SystemSettingsStore.getFloatingLogPanelSize(context)
    fun setFloatingLogPanelSize(context: Context, size: Int) = SystemSettingsStore.setFloatingLogPanelSize(context, size)
    fun isMainActivityForeground(context: Context): Boolean = SystemSettingsStore.isMainActivityForeground(context)
    fun setMainActivityForeground(context: Context, foreground: Boolean) =
        SystemSettingsStore.setMainActivityForeground(context, foreground)

    // 流量统计
    fun isAppTrafficStatsEnabled(context: Context): Boolean = SystemSettingsStore.isAppTrafficStatsEnabled(context)
    fun setAppTrafficStatsEnabled(context: Context, enabled: Boolean) = SystemSettingsStore.setAppTrafficStatsEnabled(context, enabled)
    fun getTrafficStatsRetentionDays(context: Context): Int = SystemSettingsStore.getTrafficStatsRetentionDays(context)
    fun setTrafficStatsRetentionDays(context: Context, days: Int) = SystemSettingsStore.setTrafficStatsRetentionDays(context, days)
    fun isTrafficStatsHideSystemApps(context: Context): Boolean = SystemSettingsStore.isTrafficStatsHideSystemApps(context)
    fun setTrafficStatsHideSystemApps(context: Context, hide: Boolean) =
        SystemSettingsStore.setTrafficStatsHideSystemApps(context, hide)

    // 解析模式与竞速模式
    fun getRaceProviderIds(context: Context): Set<String> = ResolutionSettingsStore.getRaceProviderIds(context)
    fun hasRaceProviderIds(context: Context): Boolean = ResolutionSettingsStore.hasRaceProviderIds(context)
    fun setRaceProviderIds(context: Context, ids: Set<String>) = ResolutionSettingsStore.setRaceProviderIds(context, ids)
    fun getLatencyTestProviderIds(context: Context): Set<String> = ResolutionSettingsStore.getLatencyTestProviderIds(context)
    fun hasLatencyTestProviderIds(context: Context): Boolean = ResolutionSettingsStore.hasLatencyTestProviderIds(context)
    fun setLatencyTestProviderIds(context: Context, ids: Set<String>) =
        ResolutionSettingsStore.setLatencyTestProviderIds(context, ids)
    fun getRaceTestDomain(context: Context): String = ResolutionSettingsStore.getRaceTestDomain(context)
    fun setRaceTestDomain(context: Context, domain: String) = ResolutionSettingsStore.setRaceTestDomain(context, domain)
    fun getDnsResolutionMode(context: Context): DnsResolutionMode = ResolutionSettingsStore.getDnsResolutionMode(context)
    fun setDnsResolutionMode(context: Context, mode: DnsResolutionMode) =
        ResolutionSettingsStore.setDnsResolutionMode(context, mode)
    fun getSmartPredictionProviderIds(context: Context): Set<String> =
        ResolutionSettingsStore.getSmartPredictionProviderIds(context)
    fun setSmartPredictionProviderIds(context: Context, ids: Set<String>) =
        ResolutionSettingsStore.setSmartPredictionProviderIds(context, ids)
    fun getParallelRaceProviderIds(context: Context): Set<String> =
        ResolutionSettingsStore.getParallelRaceProviderIds(context)
    fun setParallelRaceProviderIds(context: Context, ids: Set<String>) =
        ResolutionSettingsStore.setParallelRaceProviderIds(context, ids)
    fun getPrimaryBackupProviderIds(context: Context): List<String> =
        ResolutionSettingsStore.getPrimaryBackupProviderIds(context)
    fun setPrimaryBackupProviderIds(context: Context, ids: List<String>) =
        ResolutionSettingsStore.setPrimaryBackupProviderIds(context, ids)
    fun removeProviderFromResolutionModes(context: Context, id: String) =
        ResolutionSettingsStore.removeProviderFromResolutionModes(context, id)
    fun getPresetDnsService(context: Context): PresetDnsService = ResolutionSettingsStore.getPresetDnsService(context)
    fun setPresetDnsService(context: Context, service: PresetDnsService) =
        ResolutionSettingsStore.setPresetDnsService(context, service)
    fun getHomeProviderVisibility(context: Context): HomeProviderVisibility =
        ResolutionSettingsStore.getHomeProviderVisibility(context)
    fun setHomeProviderVisibility(context: Context, visibility: HomeProviderVisibility) =
        ResolutionSettingsStore.setHomeProviderVisibility(context, visibility)

    // 拦截响应与动态拦截
    fun getBlockResponseMode(context: Context): BlockResponseMode = AppRulesSettingsStore.getBlockResponseMode(context)
    fun setBlockResponseMode(context: Context, mode: BlockResponseMode) = AppRulesSettingsStore.setBlockResponseMode(context, mode)
    fun getDynamicBlockResponseConfig(context: Context): DynamicBlockResponseConfig =
        AppRulesSettingsStore.getDynamicBlockResponseConfig(context)
    fun setDynamicBlockResponseConfig(context: Context, config: DynamicBlockResponseConfig) =
        AppRulesSettingsStore.setDynamicBlockResponseConfig(context, config)

    // Bootstrap 引导 DNS
    fun isBootstrapEnabled(context: Context): Boolean = BootstrapDnsSettingsStore.isBootstrapEnabled(context)
    fun setBootstrapEnabled(context: Context, enabled: Boolean) = BootstrapDnsSettingsStore.setBootstrapEnabled(context, enabled)
    fun loadBootstrapIpEntries(context: Context): List<BootstrapIpEntry> =
        BootstrapDnsSettingsStore.loadBootstrapIpEntries(context)
    fun loadEnabledBootstrapIpEntries(context: Context): List<BootstrapIpEntry> =
        BootstrapDnsSettingsStore.loadEnabledBootstrapIpEntries(context)
    fun getBootstrapPresetIds(context: Context): Set<String> =
        BootstrapDnsSettingsStore.getBootstrapPresetIds(context)
    fun setBootstrapPresetIds(context: Context, ids: Set<String>) =
        BootstrapDnsSettingsStore.setBootstrapPresetIds(context, ids)
    fun setBootstrapIpEnabled(context: Context, id: String, enabled: Boolean) =
        BootstrapDnsSettingsStore.setBootstrapIpEnabled(context, id, enabled)
    fun addCustomBootstrapIp(context: Context, name: String, ip: String): BootstrapIpEntry? =
        BootstrapDnsSettingsStore.addCustomBootstrapIp(context, name, ip)
    fun deleteCustomBootstrapIp(context: Context, id: String) = BootstrapDnsSettingsStore.deleteCustomBootstrapIp(context, id)
    fun isValidBootstrapIp(ip: String?): Boolean = BootstrapDnsSettingsStore.isValidBootstrapIp(ip)

    // 后台隐藏与局域网分流
    fun isHideFromRecentsEnabled(context: Context): Boolean = SystemSettingsStore.isHideFromRecentsEnabled(context)
    fun setHideFromRecentsEnabled(context: Context, enabled: Boolean) =
        SystemSettingsStore.setHideFromRecentsEnabled(context, enabled)
    fun isBypassLanEnabled(context: Context): Boolean = SystemSettingsStore.isBypassLanEnabled(context)
    fun setBypassLanEnabled(context: Context, enabled: Boolean) =
        SystemSettingsStore.setBypassLanEnabled(context, enabled)
    fun getIpv6Mode(context: Context): Ipv6Mode = SystemSettingsStore.getIpv6Mode(context)
    fun setIpv6Mode(context: Context, mode: Ipv6Mode) =
        SystemSettingsStore.setIpv6Mode(context, mode)

    // 白名单设置
    fun isAllowEditDefaultWhitelist(context: Context): Boolean = AppRulesSettingsStore.isAllowEditDefaultWhitelist(context)
    fun setAllowEditDefaultWhitelist(context: Context, enabled: Boolean) =
        AppRulesSettingsStore.setAllowEditDefaultWhitelist(context, enabled)
    fun isDefaultWhitelistInitialized(context: Context): Boolean = AppRulesSettingsStore.isDefaultWhitelistInitialized(context)
    fun setDefaultWhitelistInitialized(context: Context, initialized: Boolean) =
        AppRulesSettingsStore.setDefaultWhitelistInitialized(context, initialized)

    // 单应用域名放行（原应用白名单）
    fun getAppAllowlistRuleMap(context: Context): Map<String, Set<String>> = AppRulesSettingsStore.getAppAllowlistRuleMap(context)
    fun setAppAllowlistRuleMap(context: Context, rules: Map<String, Set<String>>) = AppRulesSettingsStore.setAppAllowlistRuleMap(context, rules)
    fun getAppAllowlistDomainsForApp(context: Context, packageName: String): Set<String> = AppRulesSettingsStore.getAppAllowlistDomainsForApp(context, packageName)
    fun setAppAllowlistDomainsForApp(context: Context, packageName: String, domains: Set<String>) = AppRulesSettingsStore.setAppAllowlistDomainsForApp(context, packageName, domains)
    fun removeAppAllowlistForApp(context: Context, packageName: String) = AppRulesSettingsStore.removeAppAllowlistForApp(context, packageName)
    fun getAppAllowlistPackages(context: Context): Set<String> = AppRulesSettingsStore.getAppAllowlistPackages(context)
    fun setAppAllowlistPackages(context: Context, packageNames: Set<String>) =
        AppRulesSettingsStore.setAppAllowlistPackages(context, packageNames)
    fun isAppAllowlistEnabled(context: Context): Boolean = AppRulesSettingsStore.isAppAllowlistEnabled(context)
    fun setAppAllowlistEnabled(context: Context, enabled: Boolean) =
        AppRulesSettingsStore.setAppAllowlistEnabled(context, enabled)
    fun getAppAllowlistFilter(context: Context): String = AppRulesSettingsStore.getAppAllowlistFilter(context)
    fun setAppAllowlistFilter(context: Context, filter: String) = AppRulesSettingsStore.setAppAllowlistFilter(context, filter)
    fun getAppAllowlistSort(context: Context): String = AppRulesSettingsStore.getAppAllowlistSort(context)
    fun setAppAllowlistSort(context: Context, sort: String) = AppRulesSettingsStore.setAppAllowlistSort(context, sort)

    // 数据重置提示
    fun isDataResetNoticePending(context: Context): Boolean = SystemSettingsStore.isDataResetNoticePending(context)
    fun setDataResetNoticePending(context: Context, pending: Boolean) =
        SystemSettingsStore.setDataResetNoticePending(context, pending)
    fun dismissDataResetNotice(context: Context) = SystemSettingsStore.dismissDataResetNotice(context)

    // 启动自检与配置修复
    fun performStartupSelfCheck(context: Context) = StartupSelfCheck.performStartupSelfCheck(context)
}
