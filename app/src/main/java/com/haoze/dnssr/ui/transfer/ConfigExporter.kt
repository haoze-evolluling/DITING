package com.haoze.dnssr.ui.transfer

import android.content.Context
import com.haoze.dnssr.data.AppDatabase
import com.haoze.dnssr.data.entity.RewriteTargetType
import com.haoze.dnssr.data.entity.RuleScope
import com.haoze.dnssr.notification.NotificationSettingsStore
import com.haoze.dnssr.ui.AppLanguageManager
import com.haoze.dnssr.ui.AppSettings
import com.haoze.dnssr.ui.ConfigExportSelection
import com.haoze.dnssr.vpn.DnsProvider
import com.haoze.dnssr.vpn.GoUrlRuleManager
import com.haoze.dnssr.vpn.SubscriptionAutoUpdateSettings
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
            root.put("resolutionMode", AppSettings.getDnsResolutionMode(context).storageValue)
            root.put("presetDnsService", AppSettings.getPresetDnsService(context).name)
            root.put("raceTestDomain", AppSettings.getRaceTestDomain(context))

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
            val homeVisibility = AppSettings.getHomeProviderVisibility(context)
            root.put("homeProviderVisibility", JSONObject().apply {
                put("visibleProtocols", JSONArray().apply {
                    homeVisibility.visibleProtocols.forEach { put(it.name) }
                })
                put("hiddenProviderRefs", serializeProviderIds(homeVisibility.hiddenProviderIds))
                put("visibleProviderRefs", serializeProviderIds(homeVisibility.visibleProviderIds))
            })
            root.put("raceProviderRefs", serializeProviderIds(AppSettings.getRaceProviderIds(context)))
            root.put("smartPredictionProviderRefs", serializeProviderIds(AppSettings.getSmartPredictionProviderIds(context)))
            root.put("parallelRaceProviderRefs", serializeProviderIds(AppSettings.getParallelRaceProviderIds(context)))
            root.put("primaryBackupProviderRefs", JSONArray().apply {
                AppSettings.getPrimaryBackupProviderIds(context).forEach { id ->
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
            root.put("latencyTestProviderRefs", serializeProviderIds(AppSettings.getLatencyTestProviderIds(context)))
        }

        if (selection.bootstrapIps) {
            root.put("bootstrapEnabled", AppSettings.isBootstrapEnabled(context))
            root.put("bootstrapIps", JSONArray().apply {
                AppSettings.loadBootstrapIpEntries(context).filterNot { it.isPreset }.forEach { entry ->
                    put(JSONObject()
                        .put("name", entry.name)
                        .put("ip", entry.ip)
                        .put("enabled", entry.enabled))
                }
            })
            root.put("bootstrapPresetIds", JSONArray().apply {
                AppSettings.loadBootstrapIpEntries(context).filter { it.isPreset && it.enabled }.forEach { put(it.id) }
            })
        }

        if (selection.dnsCache) {
            val cachePolicy = AppSettings.getDnsCachePolicy(context)
            val cachePreset = AppSettings.getDnsCachePreset(context)
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
            val proxyConfig = AppSettings.getOutboundProxyConfig(context)
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
            root.put("domainRulesEnabled", AppSettings.isDomainRulesEnabled(context))
            root.put("addressRulesEnabled", AppSettings.isAddressRulesEnabled(context))
            root.put("encryptedDnsBlockingEnabled", AppSettings.isEncryptedDnsBlockingEnabled(context))
            root.put("blockResponseMode", AppSettings.getBlockResponseMode(context).storageValue)

            val dynConfig = AppSettings.getDynamicBlockResponseConfig(context)
            root.put("dynamicBlockResponse", JSONObject().apply {
                put("enabled", dynConfig.enabled)
                put("requestThreshold", dynConfig.requestThreshold)
                put("windowSeconds", dynConfig.windowSeconds)
                put("nxDomainDurationSeconds", dynConfig.nxDomainDurationSeconds)
            })

            root.put("allowEditDefaultWhitelist", AppSettings.isAllowEditDefaultWhitelist(context))

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
                AppSettings.getExcludedAppPackages(context).forEach(::put)
            })
        }

        if (selection.blockedApps) {
            root.put("blockedApps", JSONArray().apply {
                AppSettings.getBlockedAppPackages(context).forEach(::put)
            })
            root.put("blockedAppsEnabled", AppSettings.isBlockedAppsEnabled(context))
        }

        if (selection.appAllowlist) {
            val rules = AppSettings.getAppAllowlistRuleMap(context)
            val rulesObj = JSONObject()
            rules.forEach { (pkg, domains) ->
                val arr = JSONArray()
                domains.forEach(arr::put)
                rulesObj.put(pkg, arr)
            }
            root.put("appAllowlistRules", rulesObj)
            root.put("appAllowlistEnabled", AppSettings.isAppAllowlistEnabled(context))
        }

        if (selection.httpInspection) {
            root.put("httpInspection", JSONObject().apply {
                put("enabled", AppSettings.isHttpInspectionEnabled(context))
                put("http3Enabled", AppSettings.isHttp3InspectionEnabled(context))
                put("appPackages", JSONArray().apply {
                    AppSettings.getHttpInspectionAppPackages(context).forEach(::put)
                })
            })
        }

        if (selection.appearance) {
            root.put("appearance", JSONObject().apply {
                put("appThemeMode", AppSettings.getAppThemeMode(context).storageValue)
                put("themeColorStyle", AppSettings.getThemeColorStyle(context).storageValue)
                put("homeComponentOpacity", AppSettings.getHomeComponentOpacity(context))
                put("homePowerButtonOpacity", AppSettings.getHomePowerButtonOpacity(context))
                put("homeProviderSelectorOpacity", AppSettings.getHomeProviderSelectorOpacity(context))
                put("homeModeButtonOpacity", AppSettings.getHomeModeButtonOpacity(context))
                put("homePoemOpacity", AppSettings.getHomePoemOpacity(context))
                put("homeDnsDetailOpacity", AppSettings.getHomeDnsDetailOpacity(context))
                put("homeSentenceRunning", AppSettings.getHomeSentenceRunning(context))
                put("homeSentenceStopped", AppSettings.getHomeSentenceStopped(context))
            })
        }

        if (selection.systemSettings) {
            root.put("systemSettings", JSONObject().apply {
                put("bypassLanEnabled", AppSettings.isBypassLanEnabled(context))
                put("hideFromRecentsEnabled", AppSettings.isHideFromRecentsEnabled(context))
                put("logRetentionDays", AppSettings.logRetentionDays(context))
                put("dnsLogMode", AppSettings.getDnsLogMode(context).storageValue)
                put("floatingLogEnabled", AppSettings.isFloatingLogEnabled(context))
                put("floatingLogPanelSize", AppSettings.getFloatingLogPanelSize(context))
                put("appTrafficStatsEnabled", AppSettings.isAppTrafficStatsEnabled(context))
                put("trafficStatsRetentionDays", AppSettings.getTrafficStatsRetentionDays(context))
                put("trafficStatsHideSystemApps", AppSettings.isTrafficStatsHideSystemApps(context))
                put("disableStartupUpdateCheck", AppSettings.isStartupUpdateCheckDisabled(context))
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
