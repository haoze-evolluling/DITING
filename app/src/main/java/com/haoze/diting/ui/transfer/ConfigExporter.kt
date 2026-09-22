package com.haoze.diting.ui.transfer

import android.content.Context
import com.haoze.diting.data.AppDatabase
import com.haoze.diting.data.entity.RewriteTargetType
import com.haoze.diting.data.entity.RuleScope
import com.haoze.diting.notification.NotificationSettingsStore
import com.haoze.diting.ui.AppLanguageManager
import com.haoze.diting.ui.ConfigExportSelection
import com.haoze.diting.ui.settings.AppRulesSettingsStore
import com.haoze.diting.ui.settings.AppearanceSettingsStore
import com.haoze.diting.ui.settings.BootstrapDnsSettingsStore
import com.haoze.diting.ui.settings.DnsCacheSettingsStore
import com.haoze.diting.ui.settings.OutboundProxySettingsStore
import com.haoze.diting.ui.settings.ResolutionSettingsStore
import com.haoze.diting.ui.settings.SystemSettingsStore
import com.haoze.diting.vpn.DnsProvider
import com.haoze.diting.vpn.GoUrlRuleManager
import com.haoze.diting.vpn.SubscriptionAutoUpdateSettings
import org.json.JSONArray
import org.json.JSONObject

class ConfigExporter(private val context: Context) {
    private val database = AppDatabase.getInstance(context)

    suspend fun export(selection: ConfigExportSelection): String {
        val root = JSONObject()
            .put("formatVersion", ConfigTransferParser.FORMAT_VERSION)
            .put("exportedAt", System.currentTimeMillis())

        if (selection.providers) {
            val userProviders = DnsProvider.loadUserProviders(context)
            root.put("providers", JSONArray().apply {
                userProviders.forEach { provider ->
                    put(JSONObject()
                        .put("name", provider.name)
                        .put("protocol", provider.protocol.name)
                        .put("url", provider.url)
                        .put("host", provider.host)
                        .put("port", provider.port))
                }
            })
            val selected = DnsProvider.loadSelected(context)
            root.put("selectedProvider", JSONObject().apply {
                put("id", selected.id)
                put("name", selected.name)
                put("protocol", selected.protocol.name)
                put("isPreset", selected.isPreset)
            })
            root.put("resolutionMode", ResolutionSettingsStore.getDnsResolutionMode(context).storageValue)
            root.put("presetDnsService", ResolutionSettingsStore.getPresetDnsService(context).name)
            root.put("raceTestDomain", ResolutionSettingsStore.getRaceTestDomain(context))

            val allRuntime = DnsProvider.loadRuntimeProviders(context)
            fun serializeProviderIds(ids: Set<String>): JSONArray = JSONArray().apply {
                ids.forEach { id ->
                    val provider = allRuntime.firstOrNull { it.id == id }
                    if (provider != null) {
                        put(JSONObject().apply {
                            put("id", provider.id)
                            put("name", provider.name)
                            put("protocol", provider.protocol.name)
                            put("isPreset", provider.isPreset)
                        })
                    }
                }
            }
            val homeVisibility = ResolutionSettingsStore.getHomeProviderVisibility(context)
            root.put("homeProviderVisibility", JSONObject().apply {
                put("visibleProtocols", JSONArray().apply {
                    homeVisibility.visibleProtocols.forEach { put(it.name) }
                })
                put("hiddenProviderRefs", serializeProviderIds(homeVisibility.hiddenProviderIds))
                put("visibleProviderRefs", serializeProviderIds(homeVisibility.visibleProviderIds))
            })
            root.put("raceProviderRefs", serializeProviderIds(ResolutionSettingsStore.getRaceProviderIds(context)))
            root.put("smartPredictionProviderRefs", serializeProviderIds(ResolutionSettingsStore.getSmartPredictionProviderIds(context)))
            root.put("parallelRaceProviderRefs", serializeProviderIds(ResolutionSettingsStore.getParallelRaceProviderIds(context)))
            root.put("primaryBackupProviderRefs", JSONArray().apply {
                ResolutionSettingsStore.getPrimaryBackupProviderIds(context).forEach { id ->
                    val provider = allRuntime.firstOrNull { it.id == id }
                    if (provider != null) {
                        put(JSONObject().apply {
                            put("id", provider.id)
                            put("name", provider.name)
                            put("protocol", provider.protocol.name)
                            put("isPreset", provider.isPreset)
                        })
                    }
                }
            })
            root.put("latencyTestProviderRefs", serializeProviderIds(ResolutionSettingsStore.getLatencyTestProviderIds(context)))
        }

        if (selection.bootstrapIps) {
            root.put("bootstrapEnabled", BootstrapDnsSettingsStore.isBootstrapEnabled(context))
            root.put("bootstrapIps", JSONArray().apply {
                BootstrapDnsSettingsStore.loadBootstrapIpEntries(context).filterNot { it.isPreset }.forEach { entry ->
                    put(JSONObject()
                        .put("name", entry.name)
                        .put("ip", entry.ip)
                        .put("enabled", entry.enabled))
                }
            })
            root.put("bootstrapPresetIds", JSONArray().apply {
                BootstrapDnsSettingsStore.loadBootstrapIpEntries(context).filter { it.isPreset && it.enabled }.forEach { put(it.id) }
            })
        }

        if (selection.dnsCache) {
            val cachePolicy = DnsCacheSettingsStore.getDnsCachePolicy(context)
            val cachePreset = DnsCacheSettingsStore.getDnsCachePreset(context)
            root.put("dnsCache", JSONObject().apply {
                put("enabled", cachePolicy.enabled)
                put("preset", cachePreset.storageValue)
                put("mode", cachePolicy.mode.storageValue)
                put("maxTtlSeconds", cachePolicy.maxTtlSeconds)
                put("fixedTtlSeconds", cachePolicy.fixedTtlSeconds)
                put("minTtlEnabled", cachePolicy.minTtlEnabled)
                put("minTtlSeconds", cachePolicy.minTtlSeconds)
                put("staleFallbackEnabled", cachePolicy.staleFallbackEnabled)
                put("staleFallbackSeconds", cachePolicy.staleFallbackSeconds)
            })
        }

        if (selection.outboundProxy) {
            val proxyConfig = OutboundProxySettingsStore.getOutboundProxyConfig(context)
            root.put("outboundProxy", JSONObject().apply {
                put("enabled", proxyConfig.enabled)
                put("protocol", proxyConfig.protocol.storageValue)
                put("host", proxyConfig.host)
                put("port", proxyConfig.port)
                put("username", proxyConfig.username)
                put("password", proxyConfig.password)
                put("proxyAppPackage", proxyConfig.proxyAppPackage)
            })
        }

        if (selection.subscriptions) {
            root.put("domainRulesEnabled", AppRulesSettingsStore.isDomainRulesEnabled(context))
            root.put("addressRulesEnabled", AppRulesSettingsStore.isAddressRulesEnabled(context))
            root.put("encryptedDnsBlockingEnabled", AppRulesSettingsStore.isEncryptedDnsBlockingEnabled(context))
            root.put("blockResponseMode", AppRulesSettingsStore.getBlockResponseMode(context).storageValue)

            val dynConfig = AppRulesSettingsStore.getDynamicBlockResponseConfig(context)
            root.put("dynamicBlockResponse", JSONObject().apply {
                put("enabled", dynConfig.enabled)
                put("requestThreshold", dynConfig.requestThreshold)
                put("windowSeconds", dynConfig.windowSeconds)
                put("nxDomainDurationSeconds", dynConfig.nxDomainDurationSeconds)
            })

            root.put("allowEditDefaultWhitelist", AppRulesSettingsStore.isAllowEditDefaultWhitelist(context))

            root.put("subscriptionAutoUpdate", JSONObject().apply {
                put("enabled", SubscriptionAutoUpdateSettings.isEnabled(context))
                put("intervalHours", SubscriptionAutoUpdateSettings.intervalHours(context))
            })

            val mirrorTemplates = database.mirrorTemplateDao().all()
            root.put("mirrorTemplates", JSONArray().apply {
                mirrorTemplates.forEach { template ->
                    put(JSONObject().put("name", template.name).put("template", template.template))
                }
            })

            val groups = database.subscriptionGroupDao().all()
            root.put("subscriptionGroups", JSONArray().apply {
                groups.forEach { group ->
                    put(JSONObject().put("name", group.name).put("autoUpdateEnabled", group.autoUpdateEnabled))
                }
            })
            root.put("subscriptions", JSONArray().apply {
                database.subscriptionDao().allRemote().forEach { subscription ->
                    put(JSONObject()
                        .put("name", subscription.name)
                        .put("url", subscription.url)
                        .put("kind", subscription.kind)
                        .put("scope", RuleScope.DNS.storageValue)
                        .put("mirrorTemplate", subscription.mirrorTemplate)
                        .put("mirrorFallback", subscription.mirrorFallback)
                        .put("enabled", subscription.enabled)
                        .put("groupName", groups.firstOrNull { it.id == subscription.groupId }?.name))
                }
            })
        }

        if (selection.customDomainRules) {
            root.put("customBlockRules", JSONArray().apply {
                database.blockRuleDao().bySource("useradd").forEach { rule ->
                    put(JSONObject().apply {
                        put("pattern", rule.pattern)
                        put("important", rule.important)
                        put("appScope", rule.appScope)
                        put("appInverted", rule.appInverted)
                        put("rawLine", rule.rawLine)
                        put("enabled", rule.enabled)
                    })
                }
            })
            root.put("customAllowRules", JSONArray().apply {
                database.allowRuleDao().bySource("useradd").forEach { rule ->
                    put(JSONObject().apply {
                        put("pattern", rule.pattern)
                        put("important", rule.important)
                        put("appScope", rule.appScope)
                        put("appInverted", rule.appInverted)
                        put("rawLine", rule.rawLine)
                        put("enabled", rule.enabled)
                    })
                }
            })
        }

        if (selection.customRewriteDomainRules) {
            root.put("customRewriteDomainRules", JSONArray().apply {
                database.rewriteRuleDao().rulesBySource("useradd")
                    .filter { it.targetType == RewriteTargetType.IPV4 || it.targetType == RewriteTargetType.IPV6 }
                    .forEach { rule ->
                        put(JSONObject().apply {
                            put("pattern", rule.pattern)
                            put("targetType", rule.targetType)
                            put("targetValue", rule.targetValue)
                            put("rawLine", rule.rawLine)
                            put("enabled", rule.enabled)
                        })
                    }
            })
        }

        if (selection.customRewriteCnameRules) {
            root.put("customRewriteCnameRules", JSONArray().apply {
                database.rewriteRuleDao().rulesBySource("useradd")
                    .filter { it.targetType == RewriteTargetType.CNAME }
                    .forEach { rule ->
                        put(JSONObject().apply {
                            put("pattern", rule.pattern)
                            put("targetType", rule.targetType)
                            put("targetValue", rule.targetValue)
                            put("rawLine", rule.rawLine)
                            put("enabled", rule.enabled)
                        })
                    }
            })
        }

        if (selection.customAddressRules) {
            root.put("customAddressRules", JSONArray().apply {
                database.goUrlRuleDao().rulesBySource(GoUrlRuleManager.USER_SOURCE).forEach { rule ->
                    put(JSONObject().apply {
                        put("pattern", rule.pattern)
                        put("kind", rule.kind)
                        put("rawLine", rule.rawLine)
                        put("enabled", rule.enabled)
                    })
                }
            })
        }

        if (selection.excludedApps) {
            root.put("excludedApps", JSONArray().apply {
                AppRulesSettingsStore.getExcludedAppPackages(context).forEach(::put)
            })
        }

        if (selection.blockedApps) {
            root.put("blockedApps", JSONArray().apply {
                AppRulesSettingsStore.getBlockedAppPackages(context).forEach(::put)
            })
            root.put("blockedAppsEnabled", AppRulesSettingsStore.isBlockedAppsEnabled(context))
        }

        if (selection.appAllowlist) {
            val rules = AppRulesSettingsStore.getAppAllowlistRuleMap(context)
            val rulesObj = JSONObject()
            rules.forEach { (pkg, domains) ->
                val arr = JSONArray()
                domains.forEach(arr::put)
                rulesObj.put(pkg, arr)
            }
            root.put("appAllowlistRules", rulesObj)
            root.put("appAllowlistEnabled", AppRulesSettingsStore.isAppAllowlistEnabled(context))
        }

        if (selection.httpInspection) {
            root.put("httpInspection", JSONObject().apply {
                put("enabled", AppRulesSettingsStore.isHttpInspectionEnabled(context))
                put("http3Enabled", AppRulesSettingsStore.isHttp3InspectionEnabled(context))
                put("appPackages", JSONArray().apply {
                    AppRulesSettingsStore.getHttpInspectionAppPackages(context).forEach(::put)
                })
            })
        }

        if (selection.appearance) {
            root.put("appearance", JSONObject().apply {
                put("appThemeMode", AppearanceSettingsStore.getAppThemeMode(context).storageValue)
                put("themeColorStyle", AppearanceSettingsStore.getThemeColorStyle(context).storageValue)
                put("homeComponentOpacity", AppearanceSettingsStore.getHomeComponentOpacity(context))
                put("homePowerButtonOpacity", AppearanceSettingsStore.getHomePowerButtonOpacity(context))
                put("homeProviderSelectorOpacity", AppearanceSettingsStore.getHomeProviderSelectorOpacity(context))
                put("homeModeButtonOpacity", AppearanceSettingsStore.getHomeModeButtonOpacity(context))
                put("homePoemOpacity", AppearanceSettingsStore.getHomePoemOpacity(context))
                put("homeDnsDetailOpacity", AppearanceSettingsStore.getHomeDnsDetailOpacity(context))
                put("homeSentenceRunning", AppearanceSettingsStore.getHomeSentenceRunning(context))
                put("homeSentenceStopped", AppearanceSettingsStore.getHomeSentenceStopped(context))
            })
        }

        if (selection.systemSettings) {
            root.put("systemSettings", JSONObject().apply {
                put("bypassLanEnabled", SystemSettingsStore.isBypassLanEnabled(context))
                put("ipv6Mode", SystemSettingsStore.getIpv6Mode(context).storageValue)
                put("hideFromRecentsEnabled", SystemSettingsStore.isHideFromRecentsEnabled(context))
                put("logRetentionDays", SystemSettingsStore.logRetentionDays(context))
                put("dnsLogMode", SystemSettingsStore.getDnsLogMode(context).storageValue)
                put("floatingLogEnabled", SystemSettingsStore.isFloatingLogEnabled(context))
                put("floatingLogPanelSize", SystemSettingsStore.getFloatingLogPanelSize(context))
                put("appTrafficStatsEnabled", SystemSettingsStore.isAppTrafficStatsEnabled(context))
                put("trafficStatsRetentionDays", SystemSettingsStore.getTrafficStatsRetentionDays(context))
                put("trafficStatsHideSystemApps", SystemSettingsStore.isTrafficStatsHideSystemApps(context))
                put("disableStartupUpdateCheck", SystemSettingsStore.isStartupUpdateCheckDisabled(context))
                put("appLanguageMode", AppLanguageManager.getMode(context).storageValue)
                put("persistentNotificationEnabled", NotificationSettingsStore.isPersistentNotificationEnabled(context))
                put("trafficSpeedEnabled", NotificationSettingsStore.isTrafficSpeedEnabled(context))
                put("customRunningNotificationText", NotificationSettingsStore.getCustomRunningText(context))
                put("customStoppedNotificationText", NotificationSettingsStore.getCustomStoppedText(context))
            })
        }

        return root.toString(2)
    }
}
