package com.haoze.diting.ui.transfer

import com.haoze.diting.notification.NotificationSettingsStore
import com.haoze.diting.ui.AppLanguageManager
import com.haoze.diting.ui.AppLanguageMode
import com.haoze.diting.ui.AppThemeMode
import com.haoze.diting.ui.DnsLogMode
import com.haoze.diting.ui.Ipv6Mode
import com.haoze.diting.ui.settings.AppearanceSettingsStore
import com.haoze.diting.ui.settings.AppRulesSettingsStore
import com.haoze.diting.ui.settings.SystemSettingsStore
import com.haoze.diting.ui.theme.ThemeColorStyle
import com.haoze.diting.vpn.DynamicBlockResponseConfig
import com.haoze.diting.vpn.SubscriptionAutoUpdateScheduler
import com.haoze.diting.vpn.SubscriptionAutoUpdateSettings

/**
 * Handles importing general rule toggles, block responses, subscription auto-update settings,
 * appearance/themes, and system/notification settings.
 */
internal class PreferenceConfigImporter(private val session: ImportSessionContext) {

    private val context get() = session.context

    fun importPreferences(config: TransferConfig) {
        if (config.domainRulesEnabled != null && AppRulesSettingsStore.isDomainRulesEnabled(context) != config.domainRulesEnabled) {
            AppRulesSettingsStore.setDomainRulesEnabled(context, config.domainRulesEnabled)
            val detail = "域名规则开关 -> ${if (config.domainRulesEnabled) "已启用" else "已禁用"}"
            session.addUpdatedSetting(detail, "设置 $detail")
        }
        // Linkage constraint: if an imported config has HTTPS inspection on while domain rules are off, force-align to both enabled
        if (AppRulesSettingsStore.isHttpInspectionEnabled(context) && !AppRulesSettingsStore.isDomainRulesEnabled(context)) {
            AppRulesSettingsStore.setDomainRulesEnabled(context, true)
            val detail = "域名规则开关 -> 已启用（与 HTTPS 检查联动）"
            session.addUpdatedSetting(detail, "设置 $detail")
        }
        if (config.addressRulesEnabled != null && AppRulesSettingsStore.isAddressRulesEnabled(context) != config.addressRulesEnabled) {
            AppRulesSettingsStore.setAddressRulesEnabled(context, config.addressRulesEnabled)
            val detail = "地址规则开关 -> ${if (config.addressRulesEnabled) "已启用" else "已禁用"}"
            session.addUpdatedSetting(detail, "设置 $detail")
        }
        if (config.encryptedDnsBlockingEnabled != null && AppRulesSettingsStore.isEncryptedDnsBlockingEnabled(context) != config.encryptedDnsBlockingEnabled) {
            AppRulesSettingsStore.setEncryptedDnsBlockingEnabled(context, config.encryptedDnsBlockingEnabled)
            val detail = "加密 DNS 拦截开关 -> ${if (config.encryptedDnsBlockingEnabled) "已启用" else "已禁用"}"
            session.addUpdatedSetting(detail, "设置 $detail")
        }
        if (config.blockResponseMode != null) {
            AppRulesSettingsStore.setBlockResponseMode(context, config.blockResponseMode)
            val detail = "拦截响应策略 -> ${config.blockResponseMode.storageValue}"
            session.addUpdatedSetting(detail, "设置 $detail")
        }
        if (config.dynamicBlockResponse != null) {
            val dyn = config.dynamicBlockResponse
            AppRulesSettingsStore.setDynamicBlockResponseConfig(
                context,
                DynamicBlockResponseConfig(
                    enabled = dyn.enabled,
                    requestThreshold = dyn.requestThreshold,
                    windowSeconds = dyn.windowSeconds,
                    nxDomainDurationSeconds = dyn.nxDomainDurationSeconds
                )
            )
            val detail = "动态拦截响应配置 -> ${if (dyn.enabled) "已启用" else "已禁用"}"
            session.addUpdatedSetting(detail, "设置 $detail")
        }
        if (config.allowEditDefaultWhitelist != null) {
            AppRulesSettingsStore.setAllowEditDefaultWhitelist(context, config.allowEditDefaultWhitelist)
            val detail = "允许编辑默认白名单 -> ${if (config.allowEditDefaultWhitelist) "是" else "否"}"
            session.addUpdatedSetting(detail, "设置 $detail")
        }
        if (config.subscriptionAutoUpdate != null) {
            val auto = config.subscriptionAutoUpdate
            SubscriptionAutoUpdateSettings.save(context, auto.enabled, auto.intervalHours)
            SubscriptionAutoUpdateScheduler.sync(context)
            val detail = "规则订阅自动更新 -> ${if (auto.enabled) "每 ${auto.intervalHours} 小时" else "已禁用"}"
            session.addUpdatedSetting(detail, "设置 $detail")
        }

        if (config.appearance != null) {
            val app = config.appearance
            app.appThemeMode?.let { AppearanceSettingsStore.setAppThemeMode(context, AppThemeMode.fromStorageValue(it)) }
            app.themeColorStyle?.let { AppearanceSettingsStore.setThemeColorStyle(context, ThemeColorStyle.fromStorageValue(it)) }
            app.homeComponentOpacity?.let { AppearanceSettingsStore.setHomeComponentOpacity(context, it) }
            app.homePowerButtonOpacity?.let { AppearanceSettingsStore.setHomePowerButtonOpacity(context, it) }
            app.homeProviderSelectorOpacity?.let { AppearanceSettingsStore.setHomeProviderSelectorOpacity(context, it) }
            app.homeModeButtonOpacity?.let { AppearanceSettingsStore.setHomeModeButtonOpacity(context, it) }
            app.homePoemOpacity?.let { AppearanceSettingsStore.setHomePoemOpacity(context, it) }
            app.homeDnsDetailOpacity?.let { AppearanceSettingsStore.setHomeDnsDetailOpacity(context, it) }
            if (app.homeSentenceRunning != null && app.homeSentenceStopped != null) {
                AppearanceSettingsStore.setHomeSentences(context, app.homeSentenceRunning, app.homeSentenceStopped)
            }
            session.appearanceUpdated = true
            val detail = "外观与主题个性化"
            session.addUpdatedSetting(detail, "更新 $detail")
            session.complete("外观与主题设置", "已应用外观与主题个性化配置")
        }

        if (config.systemSettings != null) {
            val sys = config.systemSettings
            sys.bypassLanEnabled?.let { SystemSettingsStore.setBypassLanEnabled(context, it) }
            sys.ipv6Mode?.let { SystemSettingsStore.setIpv6Mode(context, Ipv6Mode.fromStorageValue(it)) }
            sys.hideFromRecentsEnabled?.let { SystemSettingsStore.setHideFromRecentsEnabled(context, it) }
            sys.logRetentionDays?.let { SystemSettingsStore.setLogRetentionDays(context, it) }
            sys.dnsLogMode?.let { SystemSettingsStore.setDnsLogMode(context, DnsLogMode.fromStorageValue(it)) }
            sys.floatingLogEnabled?.let { SystemSettingsStore.setFloatingLogEnabled(context, it) }
            sys.floatingLogPanelSize?.let { SystemSettingsStore.setFloatingLogPanelSize(context, it) }
            sys.appTrafficStatsEnabled?.let { SystemSettingsStore.setAppTrafficStatsEnabled(context, it) }
            sys.trafficStatsRetentionDays?.let { SystemSettingsStore.setTrafficStatsRetentionDays(context, it) }
            sys.trafficStatsHideSystemApps?.let { SystemSettingsStore.setTrafficStatsHideSystemApps(context, it) }
            sys.disableStartupUpdateCheck?.let { SystemSettingsStore.setStartupUpdateCheckDisabled(context, it) }
            sys.appLanguageMode?.let { AppLanguageManager.setMode(context, AppLanguageMode.fromStorageValue(it)) }
            sys.persistentNotificationEnabled?.let { NotificationSettingsStore.setPersistentNotificationEnabled(context, it) }
            sys.trafficSpeedEnabled?.let { NotificationSettingsStore.setTrafficSpeedEnabled(context, it) }
            if (sys.customRunningNotificationText != null && sys.customStoppedNotificationText != null) {
                NotificationSettingsStore.setCustomTexts(context, sys.customRunningNotificationText, sys.customStoppedNotificationText)
            }
            session.systemSettingsUpdated = true
            val detail = "系统与通用设置"
            session.addUpdatedSetting(detail, "更新 $detail")
            session.complete("系统与通用设置", "已应用系统与通用设置")
        }
    }
}
