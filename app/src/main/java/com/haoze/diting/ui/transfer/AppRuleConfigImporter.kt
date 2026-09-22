package com.haoze.diting.ui.transfer

import com.haoze.diting.ui.settings.AppRulesSettingsStore
import com.haoze.diting.vpn.AdGuardRuleParser

/**
 * Handles importing app exclusion, blocked apps, per-app domain allowlists,
 * and HTTPS inspection settings while resolving mutual exclusion conflicts.
 */
internal class AppRuleConfigImporter(private val session: ImportSessionContext) {

    private val context get() = session.context

    fun importAppRules(config: TransferConfig) {
        // App lists - preserve packages across devices without dropping uninstalled ones
        if (config.excludedApps.isNotEmpty()) {
            val validPackages = config.excludedApps.filter { it.isNotBlank() && !it.contains(" ") }.toSet()
            val existingPackages = AppRulesSettingsStore.getExcludedAppPackages(context)
            val newPackages = validPackages - existingPackages
            AppRulesSettingsStore.setExcludedAppPackages(context, existingPackages + validPackages)
            AppRulesSettingsStore.removeHttpInspectionAppPackages(context, validPackages)
            AppRulesSettingsStore.setBlockedAppPackages(context, AppRulesSettingsStore.getBlockedAppPackages(context) - validPackages)
            AppRulesSettingsStore.setAppAllowlistPackages(context, AppRulesSettingsStore.getAppAllowlistPackages(context) - validPackages)
            session.excludedAppsUpdated = newPackages.isNotEmpty()
            session.added += newPackages.size
            session.skipped += validPackages.size - newPackages.size
            newPackages.forEach { session.addedDetails.add("排除应用：$it") }
            (validPackages - newPackages).forEach { session.skippedDetails.add("排除应用：$it (已存在)") }
            config.excludedApps.forEach { packageName ->
                val isNew = packageName in newPackages
                session.complete("排除应用：$packageName", if (isNew) "新增排除应用：$packageName" else "跳过排除应用：$packageName (已存在)")
            }
        }

        if (config.blockedApps.isNotEmpty()) {
            val validPackages = config.blockedApps
                .filter { it.isNotBlank() && !it.contains(" ") && it != context.packageName }
                .toSet()
            val existingPackages = AppRulesSettingsStore.getBlockedAppPackages(context)
            val newPackages = validPackages - existingPackages
            AppRulesSettingsStore.setBlockedAppPackages(context, existingPackages + validPackages)
            AppRulesSettingsStore.setExcludedAppPackages(context, AppRulesSettingsStore.getExcludedAppPackages(context) - validPackages)
            AppRulesSettingsStore.removeHttpInspectionAppPackages(context, validPackages)
            AppRulesSettingsStore.setAppAllowlistPackages(context, AppRulesSettingsStore.getAppAllowlistPackages(context) - validPackages)
            session.blockedAppsUpdated = newPackages.isNotEmpty()
            session.added += newPackages.size
            session.skipped += validPackages.size - newPackages.size
            newPackages.forEach { session.addedDetails.add("禁止联网应用：$it") }
            (validPackages - newPackages).forEach { session.skippedDetails.add("禁止联网应用：$it (已存在)") }
            config.blockedApps.forEach { packageName ->
                val isNew = packageName in newPackages
                session.complete("禁止联网应用：$packageName", if (isNew) "新增禁止联网应用：$packageName" else "跳过禁止联网应用：$packageName (已存在)")
            }
        }

        if (AppRulesSettingsStore.isBlockedAppsEnabled(context) != config.blockedAppsEnabled) {
            AppRulesSettingsStore.setBlockedAppsEnabled(context, config.blockedAppsEnabled)
            session.blockedAppsUpdated = true
            val detail = "禁止联网应用开关 -> ${if (config.blockedAppsEnabled) "已启用" else "已禁用"}"
            session.addUpdatedSetting(detail, "设置 $detail")
        }

        val effectiveRules = mutableMapOf<String, Set<String>>()
        if (config.appAllowlistRules.isNotEmpty()) {
            config.appAllowlistRules.forEach { (pkg, domains) ->
                if (pkg.isNotBlank() && !pkg.contains(" ") && pkg != context.packageName) {
                    val validDomains = domains.mapNotNull { AdGuardRuleParser.parseAllowLine(it)?.pattern }.toSet()
                    if (validDomains.isNotEmpty()) {
                        effectiveRules[pkg] = validDomains
                    }
                }
            }
        }

        if (effectiveRules.isNotEmpty()) {
            val currentRules = AppRulesSettingsStore.getAppAllowlistRuleMap(context).toMutableMap()
            var rulesModified = false
            effectiveRules.forEach { (pkg, domains) ->
                val existing = currentRules[pkg].orEmpty()
                val merged = existing + domains
                if (merged != existing) {
                    currentRules[pkg] = merged
                    rulesModified = true
                    val isNewApp = existing.isEmpty()
                    session.added += 1
                    session.addedDetails.add("单应用域名放行：$pkg (${domains.size} 个域名)")
                    session.complete("单应用域名放行：$pkg", if (isNewApp) "新增单应用域名放行：$pkg" else "更新单应用域名放行：$pkg")
                } else {
                    session.skipped += 1
                    session.skippedDetails.add("单应用域名放行：$pkg (无新增域名)")
                    session.complete("单应用域名放行：$pkg", "跳过单应用域名放行：$pkg (已存在)")
                }
            }
            if (rulesModified) {
                AppRulesSettingsStore.setAppAllowlistRuleMap(context, currentRules)
                val allAllowlistPackages = currentRules.keys
                AppRulesSettingsStore.setExcludedAppPackages(context, AppRulesSettingsStore.getExcludedAppPackages(context) - allAllowlistPackages)
                AppRulesSettingsStore.setBlockedAppPackages(context, AppRulesSettingsStore.getBlockedAppPackages(context) - allAllowlistPackages)
                AppRulesSettingsStore.removeHttpInspectionAppPackages(context, allAllowlistPackages)
                session.appAllowlistUpdated = true
            }
        }

        if (config.appAllowlistEnabled) {
            AppRulesSettingsStore.setAppAllowlistEnabled(context, true)
            session.appAllowlistUpdated = true
            val detail = "单应用域名放行开关 -> 已启用"
            session.addUpdatedSetting(detail, "设置 $detail")
        }

        if (config.httpInspection != null) {
            val insp = config.httpInspection
            val validPackages = insp.appPackages.filter { it.isNotBlank() && !it.contains(" ") && it != context.packageName }.toSet()
            AppRulesSettingsStore.setHttpInspectionAppPackages(context, validPackages)
            AppRulesSettingsStore.setHttpInspectionEnabled(context, insp.enabled)
            AppRulesSettingsStore.setHttp3InspectionEnabled(context, insp.http3Enabled)
            AppRulesSettingsStore.setExcludedAppPackages(context, AppRulesSettingsStore.getExcludedAppPackages(context) - validPackages)
            AppRulesSettingsStore.setBlockedAppPackages(context, AppRulesSettingsStore.getBlockedAppPackages(context) - validPackages)
            AppRulesSettingsStore.setAppAllowlistPackages(context, AppRulesSettingsStore.getAppAllowlistPackages(context) - validPackages)
            session.httpInspectionUpdated = true
            val detail = "HTTPS 抓包配置 (${validPackages.size} 个应用) -> ${if (insp.enabled) "已启用" else "已禁用"}"
            session.addUpdatedSetting(detail, "设置 $detail")
            session.complete("HTTPS 抓包配置", "已应用 HTTPS 抓包配置")
        }
    }
}
