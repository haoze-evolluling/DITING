package com.haoze.dnssr.ui.transfer

import com.haoze.dnssr.data.entity.RewriteTargetType
import com.haoze.dnssr.data.entity.RuleScope
import com.haoze.dnssr.data.entity.SubscriptionKind
import com.haoze.dnssr.ui.AppSettings
import com.haoze.dnssr.ui.DEFAULT_HOME_VISIBLE_PROTOCOLS
import com.haoze.dnssr.ui.DnsResolutionMode
import com.haoze.dnssr.ui.PresetDnsService
import com.haoze.dnssr.vpn.BlockResponseMode
import com.haoze.dnssr.vpn.DnsProtocol
import com.haoze.dnssr.vpn.DnsProvider
import org.json.JSONArray
import org.json.JSONObject

object ConfigTransferParser {
    const val FORMAT_VERSION = 9
    const val MIN_SUPPORTED_FORMAT_VERSION = 1

    fun parseAndValidate(content: String): TransferConfig {
        val root = try {
            JSONObject(content)
        } catch (_: Exception) {
            throw IllegalArgumentException("配置文件不是有效的 JSON")
        }
        val formatVersion = root.optInt("formatVersion", 1)
        if (formatVersion < MIN_SUPPORTED_FORMAT_VERSION) {
            throw IllegalArgumentException("不支持的配置文件版本（V$formatVersion）")
        }

        val providers = root.optionalArray("providers").mapObjects { obj ->
            val protocolName = obj.requiredString("protocol")
            val protocol = if (protocolName.equals("DOH3", ignoreCase = true)) {
                DnsProtocol.DOH
            } else {
                DnsProtocol.entries.firstOrNull { it.name == protocolName }
            } ?: throw IllegalArgumentException("配置中包含不支持的 DNS 协议")
            val provider = ImportedProvider(
                name = obj.requiredString("name"),
                protocol = protocol,
                url = obj.optString("url", "").trim(),
                host = obj.optString("host", "").trim(),
                port = obj.optInt("port", if (protocol == DnsProtocol.DNS) 53 else 853)
            )
            val valid = when (protocol) {
                DnsProtocol.DOH -> DnsProvider.isValidDohUrl(provider.url)
                DnsProtocol.DOT -> DnsProvider.isValidDotHost(provider.host) && DnsProvider.isValidDotPort(provider.port)
                DnsProtocol.DNS -> DnsProvider.isValidDnsHost(provider.host) && DnsProvider.isValidDotPort(provider.port)
            }
            if (!valid) throw IllegalArgumentException("配置中包含无效的 DNS 服务商")
            provider
        }

        val selectedProvider = root.optJSONObject("selectedProvider")?.let(::parseProviderRef)
        val resolutionMode = root.optString("resolutionMode", "").takeIf { it.isNotEmpty() }?.let {
            DnsResolutionMode.fromStorageValue(it)
        }
        val presetDnsService = root.optString("presetDnsService", "").takeIf { it.isNotEmpty() }?.let {
            PresetDnsService.fromStorageValue(it)
        }
        val homeProviderVisibility = root.optJSONObject("homeProviderVisibility")?.let { obj ->
            val visibleProtocols = if (obj.has("visibleProtocols")) {
                obj.optionalArray("visibleProtocols").mapStrings()
                    .mapNotNull { value -> DnsProtocol.entries.firstOrNull { it.name == value } }
                    .toSet()
            } else {
                DEFAULT_HOME_VISIBLE_PROTOCOLS
            }
            val hiddenProviderRefs = obj.optionalArray("hiddenProviderRefs").mapObjects { parseProviderRef(it) }
            val visibleProviderRefs = obj.optionalArray("visibleProviderRefs").mapObjects { parseProviderRef(it) }
            ImportedHomeProviderVisibility(
                visibleProtocols = visibleProtocols,
                hiddenProviderRefs = hiddenProviderRefs,
                visibleProviderRefs = visibleProviderRefs
            )
        }
        val raceTestDomain = root.optString("raceTestDomain", "").takeIf { it.isNotEmpty() }

        val raceProviderRefs = parseProviderRefArray(root, "raceProviderRefs")
        val smartPredictionProviderRefs = parseProviderRefArray(root, "smartPredictionProviderRefs")
        val parallelRaceProviderRefs = parseProviderRefArray(root, "parallelRaceProviderRefs")
        val primaryBackupProviderRefs = parseProviderRefArray(root, "primaryBackupProviderRefs")
        val latencyTestProviderRefs = parseProviderRefArray(root, "latencyTestProviderRefs")

        val bootstrapEnabled = if (root.has("bootstrapEnabled")) root.optBoolean("bootstrapEnabled", false) else null
        val bootstrapIps = root.optionalArray("bootstrapIps").mapObjects { obj ->
            val ip = obj.requiredString("ip")
            if (!AppSettings.isValidBootstrapIp(ip)) throw IllegalArgumentException("配置中包含无效的 Bootstrap IP")
            ImportedBootstrap(obj.requiredString("name"), ip, obj.optBoolean("enabled", true))
        }
        val bootstrapPresetIds = if (root.has("bootstrapPresetIds")) {
            root.optionalArray("bootstrapPresetIds").mapStrings().toSet()
        } else null

        val dnsCache = root.optJSONObject("dnsCache")?.let { obj ->
            ImportedDnsCache(
                enabled = obj.optBoolean("enabled", true),
                preset = obj.optString("preset", "").takeIf { it.isNotEmpty() },
                mode = obj.optString("mode", "").takeIf { it.isNotEmpty() },
                maxTtlSeconds = if (obj.has("maxTtlSeconds")) obj.optLong("maxTtlSeconds") else null,
                fixedTtlSeconds = if (obj.has("fixedTtlSeconds")) obj.optLong("fixedTtlSeconds") else null,
                minTtlEnabled = if (obj.has("minTtlEnabled")) obj.optBoolean("minTtlEnabled") else null,
                minTtlSeconds = if (obj.has("minTtlSeconds")) obj.optLong("minTtlSeconds") else null,
                staleFallbackEnabled = if (obj.has("staleFallbackEnabled")) obj.optBoolean("staleFallbackEnabled") else null,
                staleFallbackSeconds = if (obj.has("staleFallbackSeconds")) obj.optLong("staleFallbackSeconds") else null
            )
        }

        val outboundProxy = root.optJSONObject("outboundProxy")?.let { obj ->
            ImportedOutboundProxy(
                enabled = obj.optBoolean("enabled", false),
                protocol = obj.optString("protocol", "SOCKS5"),
                host = obj.optString("host", "127.0.0.1"),
                port = obj.optInt("port", 7890),
                username = obj.optString("username", ""),
                password = obj.optString("password", ""),
                proxyAppPackage = obj.optString("proxyAppPackage", "")
            )
        }

        val mirrorTemplates = root.optionalArray("mirrorTemplates").mapObjects { obj ->
            ImportedMirrorTemplate(obj.requiredString("name"), obj.requiredString("template"))
        }

        val subscriptionGroups = root.optionalArray("subscriptionGroups").mapObjects { obj ->
            ImportedSubscriptionGroup(obj.requiredString("name"), obj.optBoolean("autoUpdateEnabled", true))
        }

        val subscriptions = root.optionalArray("subscriptions").mapObjects { obj ->
            val url = obj.requiredString("url")
            if (!url.startsWith("https://") && !url.startsWith("http://")) {
                throw IllegalArgumentException("配置中包含无效的订阅链接")
            }
            val scope = when (val value = obj.optString("scope", RuleScope.DNS.storageValue)) {
                RuleScope.DNS.storageValue, RuleScope.HTTPS.storageValue -> RuleScope.DNS
                else -> throw IllegalArgumentException("配置中包含不支持的订阅作用域：$value")
            }
            val kind = obj.optString("kind", SubscriptionKind.UNIFIED)
            val mirrorTemplate = obj.optString("mirrorTemplate", "").trim().takeIf { it.isNotEmpty() }
            val mirrorFallback = obj.optBoolean("mirrorFallback", true)
            val enabled = obj.optBoolean("enabled", true)
            ImportedSubscription(
                name = obj.requiredString("name"),
                url = url,
                scope = scope,
                groupName = obj.optString("groupName", "").trim().takeIf { it.isNotEmpty() },
                kind = kind,
                mirrorTemplate = mirrorTemplate,
                mirrorFallback = mirrorFallback,
                enabled = enabled
            )
        }

        val customBlockRules = root.optionalArray("customBlockRules").mapObjects { obj ->
            ImportedCustomBlockRule(
                pattern = obj.requiredString("pattern"),
                important = obj.optBoolean("important", false),
                appScope = obj.optString("appScope", "").trim().takeIf { it.isNotEmpty() },
                appInverted = obj.optBoolean("appInverted", false),
                rawLine = obj.optString("rawLine", ""),
                enabled = obj.optBoolean("enabled", true)
            )
        }
        val customAllowRules = root.optionalArray("customAllowRules").mapObjects { obj ->
            ImportedCustomAllowRule(
                pattern = obj.requiredString("pattern"),
                important = obj.optBoolean("important", false),
                appScope = obj.optString("appScope", "").trim().takeIf { it.isNotEmpty() },
                appInverted = obj.optBoolean("appInverted", false),
                rawLine = obj.optString("rawLine", ""),
                enabled = obj.optBoolean("enabled", true)
            )
        }
        val parsedRewriteDomainRules = root.optionalArray("customRewriteDomainRules").mapObjects { obj ->
            ImportedCustomRewriteRule(
                pattern = obj.requiredString("pattern"),
                targetType = obj.optString("targetType", RewriteTargetType.IPV4),
                targetValue = obj.requiredString("targetValue"),
                rawLine = obj.optString("rawLine", ""),
                enabled = obj.optBoolean("enabled", true)
            )
        }
        val parsedRewriteCnameRules = root.optionalArray("customRewriteCnameRules").mapObjects { obj ->
            ImportedCustomRewriteRule(
                pattern = obj.requiredString("pattern"),
                targetType = RewriteTargetType.CNAME,
                targetValue = obj.requiredString("targetValue"),
                rawLine = obj.optString("rawLine", ""),
                enabled = obj.optBoolean("enabled", true)
            )
        }
        val legacyRewriteRules = root.optionalArray("customRewriteRules").mapObjects { obj ->
            ImportedCustomRewriteRule(
                pattern = obj.requiredString("pattern"),
                targetType = obj.optString("targetType", RewriteTargetType.IPV4),
                targetValue = obj.requiredString("targetValue"),
                rawLine = obj.optString("rawLine", ""),
                enabled = obj.optBoolean("enabled", true)
            )
        }
        val customRewriteDomainRules = if (parsedRewriteDomainRules.isNotEmpty()) {
            parsedRewriteDomainRules
        } else {
            legacyRewriteRules.filter { it.targetType == RewriteTargetType.IPV4 || it.targetType == RewriteTargetType.IPV6 }
        }
        val customRewriteCnameRules = if (parsedRewriteCnameRules.isNotEmpty()) {
            parsedRewriteCnameRules
        } else {
            legacyRewriteRules.filter { it.targetType == RewriteTargetType.CNAME }
        }

        val parsedAddressRules = root.optionalArray("customAddressRules").mapObjects { obj ->
            ImportedCustomUrlRule(
                pattern = obj.requiredString("pattern"),
                kind = obj.optString("kind", "block"),
                rawLine = obj.optString("rawLine", ""),
                enabled = obj.optBoolean("enabled", true)
            )
        }
        val legacyUrlRules = root.optionalArray("customUrlRules").mapObjects { obj ->
            ImportedCustomUrlRule(
                pattern = obj.requiredString("pattern"),
                kind = obj.optString("kind", "block"),
                rawLine = obj.optString("rawLine", ""),
                enabled = obj.optBoolean("enabled", true)
            )
        }
        val customAddressRules = if (parsedAddressRules.isNotEmpty()) parsedAddressRules else legacyUrlRules

        val excludedApps = root.optionalArray("excludedApps").mapStrings()
            .filter { it.isNotBlank() }
            .toSet()
        val blockedApps = root.optionalArray("blockedApps").mapStrings()
            .filter { it.isNotBlank() }
            .toSet()
        val blockedAppsEnabled = root.optBoolean("blockedAppsEnabled", false)
        val appAllowlistRules = mutableMapOf<String, Set<String>>()
        if (root.has("appAllowlistRules")) {
            val rulesObj = root.optJSONObject("appAllowlistRules")
            if (rulesObj != null) {
                val keys = rulesObj.keys()
                while (keys.hasNext()) {
                    val pkg = keys.next()
                    if (pkg.isBlank()) continue
                    val arr = rulesObj.optJSONArray(pkg) ?: continue
                    val doms = mutableSetOf<String>()
                    for (i in 0 until arr.length()) {
                        val d = arr.optString(i)?.trim().orEmpty()
                        if (d.isNotEmpty()) doms.add(d)
                    }
                    if (doms.isNotEmpty()) {
                        appAllowlistRules[pkg] = doms
                    }
                }
            }
        }
        // Legacy V7 fallback for app allowlist
        if (appAllowlistRules.isEmpty() && root.has("appAllowlistApps") && root.has("appAllowlistDomains")) {
            val legacyApps = root.optionalArray("appAllowlistApps").mapStrings().toSet()
            val legacyDomains = root.optionalArray("appAllowlistDomains").mapStrings().toSet()
            if (legacyApps.isNotEmpty() && legacyDomains.isNotEmpty()) {
                legacyApps.forEach { pkg ->
                    appAllowlistRules[pkg] = legacyDomains
                }
            }
        }
        val appAllowlistEnabled = root.optBoolean("appAllowlistEnabled", false)

        val httpInspection = root.optJSONObject("httpInspection")?.let { obj ->
            ImportedHttpInspection(
                enabled = obj.optBoolean("enabled", false),
                http3Enabled = obj.optBoolean("http3Enabled", false),
                appPackages = obj.optionalArray("appPackages").mapStrings().toSet()
            )
        }

        val domainRulesEnabled = if (root.has("domainRulesEnabled")) root.optBoolean("domainRulesEnabled", true) else null
        val addressRulesEnabled = if (root.has("addressRulesEnabled")) root.optBoolean("addressRulesEnabled", true) else null
        val encryptedDnsBlockingEnabled = if (root.has("encryptedDnsBlockingEnabled")) root.optBoolean("encryptedDnsBlockingEnabled", false) else null
        val blockResponseMode = if (root.has("blockResponseMode")) BlockResponseMode.fromStorageValue(root.optString("blockResponseMode")) else null

        val dynamicBlockResponse = root.optJSONObject("dynamicBlockResponse")?.let { obj ->
            ImportedDynamicBlockResponse(
                enabled = obj.optBoolean("enabled", false),
                requestThreshold = obj.optInt("requestThreshold", 30),
                windowSeconds = obj.optInt("windowSeconds", 10),
                nxDomainDurationSeconds = obj.optInt("nxDomainDurationSeconds", 300)
            )
        }

        val allowEditDefaultWhitelist = if (root.has("allowEditDefaultWhitelist")) root.optBoolean("allowEditDefaultWhitelist") else null

        val subscriptionAutoUpdate = root.optJSONObject("subscriptionAutoUpdate")?.let { obj ->
            ImportedSubscriptionAutoUpdate(
                enabled = obj.optBoolean("enabled", false),
                intervalHours = obj.optInt("intervalHours", 24)
            )
        }

        val appearance = root.optJSONObject("appearance")?.let { obj ->
            ImportedAppearance(
                appThemeMode = obj.optString("appThemeMode", "").takeIf { it.isNotEmpty() },
                themeColorStyle = obj.optString("themeColorStyle", "").takeIf { it.isNotEmpty() },
                homeComponentOpacity = if (obj.has("homeComponentOpacity")) obj.optDouble("homeComponentOpacity").toFloat() else null,
                homePowerButtonOpacity = if (obj.has("homePowerButtonOpacity")) obj.optDouble("homePowerButtonOpacity").toFloat() else null,
                homeProviderSelectorOpacity = if (obj.has("homeProviderSelectorOpacity")) obj.optDouble("homeProviderSelectorOpacity").toFloat() else null,
                homeModeButtonOpacity = if (obj.has("homeModeButtonOpacity")) obj.optDouble("homeModeButtonOpacity").toFloat() else null,
                homePoemOpacity = if (obj.has("homePoemOpacity")) obj.optDouble("homePoemOpacity").toFloat() else null,
                homeDnsDetailOpacity = if (obj.has("homeDnsDetailOpacity")) obj.optDouble("homeDnsDetailOpacity").toFloat() else null,
                homeSentenceRunning = obj.optString("homeSentenceRunning", "").takeIf { it.isNotEmpty() },
                homeSentenceStopped = obj.optString("homeSentenceStopped", "").takeIf { it.isNotEmpty() }
            )
        }

        val systemSettings = root.optJSONObject("systemSettings")?.let { obj ->
            ImportedSystemSettings(
                bypassLanEnabled = if (obj.has("bypassLanEnabled")) obj.optBoolean("bypassLanEnabled") else null,
                hideFromRecentsEnabled = if (obj.has("hideFromRecentsEnabled")) obj.optBoolean("hideFromRecentsEnabled") else null,
                logRetentionDays = if (obj.has("logRetentionDays")) obj.optInt("logRetentionDays") else null,
                dnsLogMode = obj.optString("dnsLogMode", "").takeIf { it.isNotEmpty() },
                floatingLogEnabled = if (obj.has("floatingLogEnabled")) obj.optBoolean("floatingLogEnabled") else null,
                floatingLogPanelSize = if (obj.has("floatingLogPanelSize")) obj.optInt("floatingLogPanelSize") else null,
                appTrafficStatsEnabled = if (obj.has("appTrafficStatsEnabled")) obj.optBoolean("appTrafficStatsEnabled") else null,
                trafficStatsRetentionDays = if (obj.has("trafficStatsRetentionDays")) obj.optInt("trafficStatsRetentionDays") else null,
                trafficStatsHideSystemApps = if (obj.has("trafficStatsHideSystemApps")) obj.optBoolean("trafficStatsHideSystemApps") else null,
                disableStartupUpdateCheck = if (obj.has("disableStartupUpdateCheck")) obj.optBoolean("disableStartupUpdateCheck") else null,
                appLanguageMode = obj.optString("appLanguageMode", "").takeIf { it.isNotEmpty() },
                persistentNotificationEnabled = if (obj.has("persistentNotificationEnabled")) obj.optBoolean("persistentNotificationEnabled") else null,
                trafficSpeedEnabled = if (obj.has("trafficSpeedEnabled")) obj.optBoolean("trafficSpeedEnabled") else null,
                customRunningNotificationText = obj.optString("customRunningNotificationText", "").takeIf { it.isNotEmpty() },
                customStoppedNotificationText = obj.optString("customStoppedNotificationText", "").takeIf { it.isNotEmpty() }
            )
        }

        return TransferConfig(
            formatVersion = formatVersion,
            providers = providers,
            selectedProvider = selectedProvider,
            resolutionMode = resolutionMode,
            presetDnsService = presetDnsService,
            homeProviderVisibility = homeProviderVisibility,
            raceTestDomain = raceTestDomain,
            raceProviderRefs = raceProviderRefs,
            smartPredictionProviderRefs = smartPredictionProviderRefs,
            parallelRaceProviderRefs = parallelRaceProviderRefs,
            primaryBackupProviderRefs = primaryBackupProviderRefs,
            latencyTestProviderRefs = latencyTestProviderRefs,
            bootstrapEnabled = bootstrapEnabled,
            bootstrapIps = bootstrapIps,
            bootstrapPresetIds = bootstrapPresetIds,
            dnsCache = dnsCache,
            outboundProxy = outboundProxy,
            mirrorTemplates = mirrorTemplates,
            subscriptionGroups = subscriptionGroups,
            subscriptions = subscriptions,
            customBlockRules = customBlockRules,
            customAllowRules = customAllowRules,
            customRewriteDomainRules = customRewriteDomainRules,
            customRewriteCnameRules = customRewriteCnameRules,
            customAddressRules = customAddressRules,
            excludedApps = excludedApps,
            blockedApps = blockedApps,
            blockedAppsEnabled = blockedAppsEnabled,
            appAllowlistRules = appAllowlistRules,
            appAllowlistEnabled = appAllowlistEnabled,
            httpInspection = httpInspection,
            domainRulesEnabled = domainRulesEnabled,
            addressRulesEnabled = addressRulesEnabled,
            encryptedDnsBlockingEnabled = encryptedDnsBlockingEnabled,
            blockResponseMode = blockResponseMode,
            dynamicBlockResponse = dynamicBlockResponse,
            allowEditDefaultWhitelist = allowEditDefaultWhitelist,
            subscriptionAutoUpdate = subscriptionAutoUpdate,
            appearance = appearance,
            systemSettings = systemSettings
        )
    }

    fun parseProviderRef(obj: JSONObject): ImportedProviderRef {
        val protocolName = obj.optString("protocol", "DOH")
        val protocol = DnsProtocol.entries.firstOrNull { it.name.equals(protocolName, ignoreCase = true) } ?: DnsProtocol.DOH
        return ImportedProviderRef(
            id = obj.optString("id", ""),
            name = obj.optString("name", ""),
            protocol = protocol,
            url = obj.optString("url", ""),
            host = obj.optString("host", ""),
            port = obj.optInt("port", 853),
            isPreset = obj.optBoolean("isPreset", false)
        )
    }

    private fun parseProviderRefArray(root: JSONObject, key: String): List<ImportedProviderRef> =
        root.optionalArray(key).mapObjects { parseProviderRef(it) }

    internal fun JSONObject.requiredString(key: String): String = optString(key, "").trim()
        .takeIf { it.isNotEmpty() } ?: throw IllegalArgumentException("配置缺少 $key")

    internal fun JSONObject.optionalArray(key: String): JSONArray = when {
        !has(key) -> JSONArray()
        optJSONArray(key) != null -> getJSONArray(key)
        else -> throw IllegalArgumentException("配置字段 $key 格式错误")
    }

    internal fun <T> JSONArray.mapObjects(transform: (JSONObject) -> T): List<T> = buildList {
        for (index in 0 until length()) {
            val item = optJSONObject(index) ?: throw IllegalArgumentException("配置列表格式错误")
            add(transform(item))
        }
    }

    internal fun JSONArray.mapStrings(): List<String> = buildList {
        for (index in 0 until length()) {
            val item = optString(index, "").trim()
            if (item.isEmpty()) throw IllegalArgumentException("配置列表格式错误")
            add(item)
        }
    }
}
