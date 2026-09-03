package com.haoze.dnssr.ui.transfer

import android.content.Context
import com.haoze.dnssr.data.AppDatabase
import com.haoze.dnssr.data.entity.MirrorTemplateEntity
import com.haoze.dnssr.data.entity.RewriteTargetType
import com.haoze.dnssr.data.entity.RuleScope
import com.haoze.dnssr.data.entity.SubscriptionGroupEntity
import com.haoze.dnssr.notification.NotificationSettingsStore
import com.haoze.dnssr.ui.AppLanguageManager
import com.haoze.dnssr.ui.AppLanguageMode
import com.haoze.dnssr.ui.AppSettings
import com.haoze.dnssr.ui.AppThemeMode
import com.haoze.dnssr.ui.ConfigImportProgress
import com.haoze.dnssr.ui.ConfigImportResult
import com.haoze.dnssr.ui.DnsLogMode
import com.haoze.dnssr.ui.HomeProviderVisibility
import com.haoze.dnssr.ui.OutboundProxyConfig
import com.haoze.dnssr.ui.OutboundProxyProtocol
import com.haoze.dnssr.ui.RuntimeDnsSettingsRefresher
import com.haoze.dnssr.ui.theme.ThemeColorStyle
import com.haoze.dnssr.vpn.AdGuardRuleParser
import com.haoze.dnssr.vpn.AllowListManager
import com.haoze.dnssr.vpn.BlockListManager
import com.haoze.dnssr.vpn.DnsProtocol
import com.haoze.dnssr.vpn.DnsProvider
import com.haoze.dnssr.vpn.DynamicBlockResponseConfig
import com.haoze.dnssr.vpn.GoUrlRuleManager
import com.haoze.dnssr.vpn.RewriteRule
import com.haoze.dnssr.vpn.RewriteRuleManager
import com.haoze.dnssr.vpn.SubscriptionAutoUpdateScheduler
import com.haoze.dnssr.vpn.SubscriptionAutoUpdateSettings
import com.haoze.dnssr.vpn.SubscriptionManager
import com.haoze.dnssr.vpn.cache.DnsCacheMode
import com.haoze.dnssr.vpn.cache.DnsCachePreset
import java.io.File

class ConfigImporter(private val context: Context) {
    private val database = AppDatabase.getInstance(context)
    private val ruleIndexDir by lazy { File(context.filesDir, "rule-index") }

    private fun subscriptionManager(scope: RuleScope = RuleScope.DNS) = SubscriptionManager(
        database,
        database.subscriptionDao(),
        BlockListManager(database.blockRuleDao(), ruleIndexDir, scope = scope, reloadCacheAfterChanges = false),
        AllowListManager(database.allowRuleDao(), ruleIndexDir, scope = scope, reloadCacheAfterChanges = false),
        RewriteRuleManager(database.rewriteRuleDao(), ruleIndexDir, scope, reloadCacheAfterChanges = false),
        scope
    )

    suspend fun import(
        config: TransferConfig,
        onProgress: (ConfigImportProgress) -> Unit = {}
    ): ConfigImportResult {
        var added = 0
        var skipped = 0
        var failed = 0
        var excludedAppsUpdated = false
        var blockedAppsUpdated = false
        var appAllowlistUpdated = false
        var httpInspectionUpdated = false
        var outboundProxyUpdated = false
        var dnsCacheUpdated = false
        var appearanceUpdated = false
        var systemSettingsUpdated = false
        var subscriptionsAdded = 0
        var customRulesAdded = 0
        var processed = 0

        val addedDetails = mutableListOf<String>()
        val skippedDetails = mutableListOf<String>()
        val failedDetails = mutableListOf<String>()
        val updatedSettingsDetails = mutableListOf<String>()
        val logs = mutableListOf<String>()

        val total = config.providers.size + config.bootstrapIps.size + config.subscriptions.size +
            config.mirrorTemplates.size + config.customBlockRules.size + config.customAllowRules.size +
            config.customRewriteDomainRules.size + config.customRewriteCnameRules.size + config.customAddressRules.size +
            config.excludedApps.size + config.blockedApps.size + config.appAllowlistRules.size +
            (if (config.bootstrapPresetIds != null) 1 else 0) +
            (if (config.dnsCache != null) 1 else 0) +
            (if (config.outboundProxy != null) 1 else 0) +
            (if (config.httpInspection != null) 1 else 0) +
            (if (config.appearance != null) 1 else 0) +
            (if (config.systemSettings != null) 1 else 0)

        fun report(item: String, logText: String? = null) {
            if (logText != null) logs.add(logText)
            onProgress(ConfigImportProgress(processed, total, item, logText))
        }

        fun complete(item: String, logText: String? = null) {
            processed++
            if (logText != null) logs.add(logText)
            onProgress(ConfigImportProgress(processed, total, item, logText))
        }

        report("正在读取配置文件", "成功解析配置文件（版本 V${config.formatVersion}）")

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
                skipped++
                val detail = "DNS 服务商：${provider.name} [${provider.protocol.name}]"
                skippedDetails.add(detail)
                complete(item, "跳过 $detail (已存在)")
            } else {
                val created = DnsProvider.addUserProvider(
                    context, provider.name, provider.protocol, provider.url, provider.host, provider.port
                )
                providerKeyToIdMap[key] = created.id
                added++
                val detail = "DNS 服务商：${provider.name} [${provider.protocol.name}]"
                addedDetails.add(detail)
                complete(item, "新增 $detail")
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
                updatedSettingsDetails.add(detail)
                logs.add("设置 $detail")
            }
        }
        config.resolutionMode?.let { mode ->
            AppSettings.setDnsResolutionMode(context, mode)
            val detail = "DNS 解析模式 -> ${mode.displayName}"
            updatedSettingsDetails.add(detail)
            logs.add("设置 $detail")
        }
        if (config.raceProviderRefs.isNotEmpty()) {
            val resolvedIds = config.raceProviderRefs.mapNotNull(::resolveProviderRef).toSet()
            if (resolvedIds.isNotEmpty()) {
                AppSettings.setRaceProviderIds(context, resolvedIds)
                val detail = "抢答模式 DNS 节点 (${resolvedIds.size} 个)"
                updatedSettingsDetails.add(detail)
                logs.add("更新 $detail")
            }
        }
        if (config.smartPredictionProviderRefs.isNotEmpty()) {
            val resolvedIds = config.smartPredictionProviderRefs.mapNotNull(::resolveProviderRef).toSet()
            if (resolvedIds.isNotEmpty()) {
                AppSettings.setSmartPredictionProviderIds(context, resolvedIds)
                val detail = "智能预测 DNS 节点 (${resolvedIds.size} 个)"
                updatedSettingsDetails.add(detail)
                logs.add("更新 $detail")
            }
        }
        if (config.parallelRaceProviderRefs.isNotEmpty()) {
            val resolvedIds = config.parallelRaceProviderRefs.mapNotNull(::resolveProviderRef).toSet()
            if (resolvedIds.isNotEmpty()) {
                AppSettings.setParallelRaceProviderIds(context, resolvedIds)
                val detail = "并行抢答 DNS 节点 (${resolvedIds.size} 个)"
                updatedSettingsDetails.add(detail)
                logs.add("更新 $detail")
            }
        }
        if (config.primaryBackupProviderRefs.isNotEmpty()) {
            val resolvedIds = config.primaryBackupProviderRefs.mapNotNull(::resolveProviderRef)
            if (resolvedIds.isNotEmpty()) {
                AppSettings.setPrimaryBackupProviderIds(context, resolvedIds)
                val detail = "主备模式 DNS 节点 (${resolvedIds.size} 个)"
                updatedSettingsDetails.add(detail)
                logs.add("更新 $detail")
            }
        }
        config.presetDnsService?.let { service ->
            AppSettings.setPresetDnsService(context, service)
            val detail = "预置 DNS 服务 -> ${service.displayName}"
            updatedSettingsDetails.add(detail)
            logs.add("设置 $detail")
        }
        config.homeProviderVisibility?.let { visibility ->
            val hiddenIds = visibility.hiddenProviderRefs.mapNotNull(::resolveProviderRef).toSet()
            val visibleIds = visibility.visibleProviderRefs.mapNotNull(::resolveProviderRef).toSet()
            AppSettings.setHomeProviderVisibility(
                context,
                HomeProviderVisibility(
                    visibleProtocols = visibility.visibleProtocols,
                    hiddenProviderIds = hiddenIds,
                    visibleProviderIds = visibleIds
                )
            )
            val detail = "首页服务商卡片可见性设置"
            updatedSettingsDetails.add(detail)
            logs.add("更新 $detail")
        }
        config.raceTestDomain?.takeIf { it.isNotBlank() }?.let { domain ->
            AppSettings.setRaceTestDomain(context, domain)
            val detail = "抢答测速域名 -> $domain"
            updatedSettingsDetails.add(detail)
            logs.add("设置 $detail")
        }

        // Bootstrap IPs
        if (config.bootstrapEnabled != null) {
            AppSettings.setBootstrapEnabled(context, config.bootstrapEnabled)
            val detail = "Bootstrap IP 引导 -> ${if (config.bootstrapEnabled) "已启用" else "已禁用"}"
            updatedSettingsDetails.add(detail)
            logs.add("设置 $detail")
        }
        val existingIps = AppSettings.loadBootstrapIpEntries(context)
            .filterNot { it.isPreset }.map { it.ip.lowercase() }.toMutableSet()
        config.bootstrapIps.forEach { entry ->
            val item = "Bootstrap IP：${entry.name}"
            val detail = "Bootstrap IP：${entry.name} (${entry.ip})"
            if (!existingIps.add(entry.ip.lowercase())) {
                skipped++
                skippedDetails.add(detail)
                complete(item, "跳过 $detail (已存在)")
            } else {
                val saved = AppSettings.addCustomBootstrapIp(context, entry.name, entry.ip)
                if (saved == null) {
                    failed++
                    failedDetails.add(detail)
                    complete(item, "添加 $detail 失败")
                } else {
                    AppSettings.setBootstrapIpEnabled(context, saved.id, entry.enabled)
                    added++
                    addedDetails.add(detail)
                    complete(item, "新增 $detail")
                }
            }
        }

        if (config.bootstrapPresetIds != null) {
            val validPresets = AppSettings.getBootstrapPresetIds(context)
            if (validPresets != config.bootstrapPresetIds) {
                AppSettings.setBootstrapPresetIds(context, config.bootstrapPresetIds)
                val detail = "预置 Bootstrap 节点状态"
                updatedSettingsDetails.add(detail)
                logs.add("更新 $detail")
            }
            complete("预置 Bootstrap IP 节点", "已同步预置 Bootstrap 节点启用状态")
        }

        if (config.dnsCache != null) {
            val cache = config.dnsCache
            AppSettings.setCacheEnabled(context, cache.enabled)
            cache.preset?.let { presetVal ->
                DnsCachePreset.fromStorageValue(presetVal)?.let { preset ->
                    AppSettings.setDnsCachePreset(context, preset)
                }
            }
            val currentPolicy = AppSettings.getDnsCachePolicy(context)
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
            AppSettings.setDnsCachePolicy(context, updatedPolicy)
            dnsCacheUpdated = true
            val detail = "DNS 缓存策略"
            updatedSettingsDetails.add(detail)
            logs.add("更新 $detail")
            complete("DNS 缓存配置", "已应用 DNS 缓存策略")
        }

        if (config.outboundProxy != null) {
            val proxy = config.outboundProxy
            AppSettings.setOutboundProxyConfig(
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
            outboundProxyUpdated = true
            val detail = "出站代理配置 -> ${if (proxy.enabled) "已启用" else "已禁用"} (${proxy.protocol}://${proxy.host}:${proxy.port})"
            updatedSettingsDetails.add(detail)
            logs.add("设置 $detail")
            complete("出站代理配置", "已应用出站代理配置")
        }

        // Mirror templates
        val mirrorDao = database.mirrorTemplateDao()
        config.mirrorTemplates.forEach { template ->
            val item = "镜像模板：${template.name}"
            val detail = "镜像模板：${template.name}"
            val existing = mirrorDao.byName(template.name)
            if (existing != null) {
                skipped++
                skippedDetails.add(detail)
                complete(item, "跳过 $detail (已存在)")
            } else {
                mirrorDao.insert(MirrorTemplateEntity(name = template.name, template = template.template))
                added++
                addedDetails.add(detail)
                complete(item, "新增 $detail")
            }
        }

        // Subscription groups
        val groupDao = database.subscriptionGroupDao()
        val importedGroupIds = mutableMapOf<String, Long>()
        config.subscriptionGroups.forEach { group ->
            val existing = groupDao.byName(group.name)
            val id = existing?.id ?: groupDao.insert(
                SubscriptionGroupEntity(
                    name = group.name,
                    autoUpdateEnabled = group.autoUpdateEnabled
                )
            )
            importedGroupIds[group.name.lowercase()] = id
        }

        // Remote subscriptions
        val existingSubscriptionKeys = database.subscriptionDao().allRemote()
            .map { subscriptionKey(it.url, RuleScope.DNS) }.toMutableSet()
        config.subscriptions.forEach { entry ->
            val item = "规则订阅：${entry.name}"
            val detail = "规则订阅：${entry.name}"
            val key = subscriptionKey(entry.url, entry.scope)
            if (!existingSubscriptionKeys.add(key)) {
                database.subscriptionDao().byUrl(entry.url)?.let { existingSub ->
                    if (existingSub.enabled != entry.enabled) {
                        database.subscriptionDao().setEnabled(existingSub.id, entry.enabled)
                    }
                }
                skipped++
                skippedDetails.add(detail)
                complete(item, "跳过 $detail (已存在)")
            } else {
                val result = subscriptionManager(entry.scope).addRemoteSubscription(
                    url = entry.url,
                    name = entry.name,
                    groupId = entry.groupName?.let { importedGroupIds[it.lowercase()] },
                    kind = entry.kind,
                    mirrorTemplate = entry.mirrorTemplate,
                    mirrorFallback = entry.mirrorFallback
                )
                if (result.isFailure) {
                    failed++
                    failedDetails.add(detail)
                    complete(item, "添加 $detail 失败")
                } else {
                    if (!entry.enabled) {
                        database.subscriptionDao().byUrl(entry.url)?.let {
                            database.subscriptionDao().setEnabled(it.id, false)
                        }
                    }
                    added++
                    subscriptionsAdded++
                    addedDetails.add(detail)
                    complete(item, "新增 $detail")
                }
            }
        }

        // Custom domain, rewrite & address rules
        val blockManager = BlockListManager(database.blockRuleDao(), ruleIndexDir, scope = RuleScope.DNS, reloadCacheAfterChanges = false)
        val allowManager = AllowListManager(database.allowRuleDao(), ruleIndexDir, scope = RuleScope.DNS, reloadCacheAfterChanges = false)
        val rewriteManager = RewriteRuleManager(database.rewriteRuleDao(), ruleIndexDir, RuleScope.DNS, reloadCacheAfterChanges = false)
        val goUrlRuleManager = GoUrlRuleManager(database.goUrlRuleDao())

        if (config.customBlockRules.isNotEmpty()) {
            val parsedBlock = config.customBlockRules.mapNotNull { rule ->
                AdGuardRuleParser.parseLine(rule.rawLine.ifEmpty { rule.pattern })?.let { parsed ->
                    parsed to rule.enabled
                }
            }
            val enabledRules = parsedBlock.filter { it.second }.map { it.first }
            val disabledRules = parsedBlock.filterNot { it.second }.map { it.first }
            val insertedEnabled = if (enabledRules.isNotEmpty()) blockManager.addRulesBatch(enabledRules, "useradd", enabled = true, refreshCache = false) else 0
            val insertedDisabled = if (disabledRules.isNotEmpty()) blockManager.addRulesBatch(disabledRules, "useradd", enabled = false, refreshCache = false) else 0
            val inserted = insertedEnabled + insertedDisabled
            added += inserted
            val skippedCount = config.customBlockRules.size - inserted
            skipped += skippedCount
            customRulesAdded += inserted
            config.customBlockRules.forEach { rule ->
                val id = database.blockRuleDao().idByPattern(rule.pattern, rule.important, rule.appScope, rule.appInverted)
                if (id > 0) {
                    database.blockRuleDao().setEnabled(id, rule.enabled)
                    database.blockRuleDao().setSourceEnabledByRuleId(id, rule.enabled)
                }
                complete("自定义域名屏蔽规则：${rule.pattern}", "处理自定义域名屏蔽规则：${rule.pattern}")
            }
            if (inserted > 0) addedDetails.add("自定义域名屏蔽规则 ($inserted 条)")
            if (skippedCount > 0) skippedDetails.add("自定义域名屏蔽规则 ($skippedCount 条已存在)")
        }

        if (config.customAllowRules.isNotEmpty()) {
            val parsedAllow = config.customAllowRules.mapNotNull { rule ->
                AdGuardRuleParser.parseAllowLine(rule.rawLine.ifEmpty { rule.pattern })?.let { parsed ->
                    parsed to rule.enabled
                }
            }
            val enabledRules = parsedAllow.filter { it.second }.map { it.first }
            val disabledRules = parsedAllow.filterNot { it.second }.map { it.first }
            val insertedEnabled = if (enabledRules.isNotEmpty()) allowManager.addRulesBatch(enabledRules, "useradd", enabled = true, refreshCache = false) else 0
            val insertedDisabled = if (disabledRules.isNotEmpty()) allowManager.addRulesBatch(disabledRules, "useradd", enabled = false, refreshCache = false) else 0
            val inserted = insertedEnabled + insertedDisabled
            added += inserted
            val skippedCount = config.customAllowRules.size - inserted
            skipped += skippedCount
            customRulesAdded += inserted
            config.customAllowRules.forEach { rule ->
                val id = database.allowRuleDao().idByPattern(rule.pattern, rule.important, rule.appScope, rule.appInverted)
                if (id > 0) {
                    database.allowRuleDao().setEnabled(id, rule.enabled)
                    database.allowRuleDao().setSourceEnabledByRuleId(id, rule.enabled)
                }
                complete("自定义域名放行规则：${rule.pattern}", "处理自定义域名放行规则：${rule.pattern}")
            }
            if (inserted > 0) addedDetails.add("自定义域名放行规则 ($inserted 条)")
            if (skippedCount > 0) skippedDetails.add("自定义域名放行规则 ($skippedCount 条已存在)")
        }

        if (config.customRewriteDomainRules.isNotEmpty()) {
            val enabledList = config.customRewriteDomainRules.filter { it.enabled }.map {
                RewriteRule(pattern = it.pattern, targetType = it.targetType, targetValue = it.targetValue, rawLine = it.rawLine)
            }
            val disabledList = config.customRewriteDomainRules.filterNot { it.enabled }.map {
                RewriteRule(pattern = it.pattern, targetType = it.targetType, targetValue = it.targetValue, rawLine = it.rawLine)
            }
            val insertedEnabled = if (enabledList.isNotEmpty()) rewriteManager.addRules(enabledList, "useradd", enabled = true, refreshCache = false) else 0
            val insertedDisabled = if (disabledList.isNotEmpty()) rewriteManager.addRules(disabledList, "useradd", enabled = false, refreshCache = false) else 0
            val inserted = insertedEnabled + insertedDisabled
            added += inserted
            val skippedCount = config.customRewriteDomainRules.size - inserted
            skipped += skippedCount
            customRulesAdded += inserted
            config.customRewriteDomainRules.forEach { rule ->
                val id = database.rewriteRuleDao().idByKey(rule.pattern, rule.targetType, rule.targetValue)
                if (id > 0) {
                    database.rewriteRuleDao().setEnabled(id, rule.enabled)
                    database.rewriteRuleDao().setSourceEnabledByRuleId(id, rule.enabled)
                }
                complete("自定义复写域名规则：${rule.pattern}", "处理自定义复写域名规则：${rule.pattern}")
            }
            if (inserted > 0) addedDetails.add("自定义复写域名规则 ($inserted 条)")
            if (skippedCount > 0) skippedDetails.add("自定义复写域名规则 ($skippedCount 条已存在)")
        }

        if (config.customRewriteCnameRules.isNotEmpty()) {
            val enabledList = config.customRewriteCnameRules.filter { it.enabled }.map {
                RewriteRule(pattern = it.pattern, targetType = it.targetType, targetValue = it.targetValue, rawLine = it.rawLine)
            }
            val disabledList = config.customRewriteCnameRules.filterNot { it.enabled }.map {
                RewriteRule(pattern = it.pattern, targetType = it.targetType, targetValue = it.targetValue, rawLine = it.rawLine)
            }
            val insertedEnabled = if (enabledList.isNotEmpty()) rewriteManager.addRules(enabledList, "useradd", enabled = true, refreshCache = false) else 0
            val insertedDisabled = if (disabledList.isNotEmpty()) rewriteManager.addRules(disabledList, "useradd", enabled = false, refreshCache = false) else 0
            val inserted = insertedEnabled + insertedDisabled
            added += inserted
            val skippedCount = config.customRewriteCnameRules.size - inserted
            skipped += skippedCount
            customRulesAdded += inserted
            config.customRewriteCnameRules.forEach { rule ->
                val id = database.rewriteRuleDao().idByKey(rule.pattern, rule.targetType, rule.targetValue)
                if (id > 0) {
                    database.rewriteRuleDao().setEnabled(id, rule.enabled)
                    database.rewriteRuleDao().setSourceEnabledByRuleId(id, rule.enabled)
                }
                complete("自定义复写 CNAME 规则：${rule.pattern}", "处理自定义复写 CNAME 规则：${rule.pattern}")
            }
            if (inserted > 0) addedDetails.add("自定义复写 CNAME 规则 ($inserted 条)")
            if (skippedCount > 0) skippedDetails.add("自定义复写 CNAME 规则 ($skippedCount 条已存在)")
        }

        if (config.customAddressRules.isNotEmpty()) {
            var urlInserted = 0
            config.customAddressRules.forEach { rule ->
                val line = if (rule.rawLine.isNotBlank()) rule.rawLine else if (rule.kind.equals("allow", true)) "@@${rule.pattern}" else rule.pattern
                val ok = goUrlRuleManager.addRule(line)
                val id = database.goUrlRuleDao().idByPattern(rule.pattern, rule.kind)
                if (id > 0) {
                    database.goUrlRuleDao().setEnabled(id, rule.enabled)
                    database.goUrlRuleDao().setSourceEnabledByRuleId(id, rule.enabled)
                }
                if (ok) {
                    urlInserted++
                    addedDetails.add("自定义地址规则：${rule.pattern}")
                    complete("自定义地址规则：${rule.pattern}", "新增自定义地址规则：${rule.pattern}")
                } else {
                    skippedDetails.add("自定义地址规则：${rule.pattern} (已存在)")
                    complete("自定义地址规则：${rule.pattern}", "跳过自定义地址规则：${rule.pattern} (已存在)")
                }
            }
            added += urlInserted
            skipped += config.customAddressRules.size - urlInserted
            customRulesAdded += urlInserted
        }

        // App lists - preserve packages across devices without dropping uninstalled ones
        if (config.excludedApps.isNotEmpty()) {
            val validPackages = config.excludedApps.filter { it.isNotBlank() && !it.contains(" ") }.toSet()
            val existingPackages = AppSettings.getExcludedAppPackages(context)
            val newPackages = validPackages - existingPackages
            AppSettings.setExcludedAppPackages(context, existingPackages + validPackages)
            AppSettings.removeHttpInspectionAppPackages(context, validPackages)
            AppSettings.setBlockedAppPackages(context, AppSettings.getBlockedAppPackages(context) - validPackages)
            AppSettings.setAppAllowlistPackages(context, AppSettings.getAppAllowlistPackages(context) - validPackages)
            excludedAppsUpdated = newPackages.isNotEmpty()
            added += newPackages.size
            skipped += validPackages.size - newPackages.size
            newPackages.forEach { addedDetails.add("排除应用：$it") }
            (validPackages - newPackages).forEach { skippedDetails.add("排除应用：$it (已存在)") }
            config.excludedApps.forEach { packageName ->
                val isNew = packageName in newPackages
                complete("排除应用：$packageName", if (isNew) "新增排除应用：$packageName" else "跳过排除应用：$packageName (已存在)")
            }
        }

        if (config.blockedApps.isNotEmpty()) {
            val validPackages = config.blockedApps
                .filter { it.isNotBlank() && !it.contains(" ") && it != context.packageName }
                .toSet()
            val existingPackages = AppSettings.getBlockedAppPackages(context)
            val newPackages = validPackages - existingPackages
            AppSettings.setBlockedAppPackages(context, existingPackages + validPackages)
            AppSettings.setExcludedAppPackages(context, AppSettings.getExcludedAppPackages(context) - validPackages)
            AppSettings.removeHttpInspectionAppPackages(context, validPackages)
            AppSettings.setAppAllowlistPackages(context, AppSettings.getAppAllowlistPackages(context) - validPackages)
            blockedAppsUpdated = newPackages.isNotEmpty()
            added += newPackages.size
            skipped += validPackages.size - newPackages.size
            newPackages.forEach { addedDetails.add("禁止联网应用：$it") }
            (validPackages - newPackages).forEach { skippedDetails.add("禁止联网应用：$it (已存在)") }
            config.blockedApps.forEach { packageName ->
                val isNew = packageName in newPackages
                complete("禁止联网应用：$packageName", if (isNew) "新增禁止联网应用：$packageName" else "跳过禁止联网应用：$packageName (已存在)")
            }
        }

        if (AppSettings.isBlockedAppsEnabled(context) != config.blockedAppsEnabled) {
            AppSettings.setBlockedAppsEnabled(context, config.blockedAppsEnabled)
            blockedAppsUpdated = true
            val detail = "禁止联网应用开关 -> ${if (config.blockedAppsEnabled) "已启用" else "已禁用"}"
            updatedSettingsDetails.add(detail)
            logs.add("设置 $detail")
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
            val currentRules = AppSettings.getAppAllowlistRuleMap(context).toMutableMap()
            var rulesModified = false
            effectiveRules.forEach { (pkg, domains) ->
                val existing = currentRules[pkg].orEmpty()
                val merged = existing + domains
                if (merged != existing) {
                    currentRules[pkg] = merged
                    rulesModified = true
                    val isNewApp = existing.isEmpty()
                    added += 1
                    addedDetails.add("单应用域名放行：$pkg (${domains.size} 个域名)")
                    complete("单应用域名放行：$pkg", if (isNewApp) "新增单应用域名放行：$pkg" else "更新单应用域名放行：$pkg")
                } else {
                    skipped += 1
                    skippedDetails.add("单应用域名放行：$pkg (无新增域名)")
                    complete("单应用域名放行：$pkg", "跳过单应用域名放行：$pkg (已存在)")
                }
            }
            if (rulesModified) {
                AppSettings.setAppAllowlistRuleMap(context, currentRules)
                val allAllowlistPackages = currentRules.keys
                AppSettings.setExcludedAppPackages(context, AppSettings.getExcludedAppPackages(context) - allAllowlistPackages)
                AppSettings.setBlockedAppPackages(context, AppSettings.getBlockedAppPackages(context) - allAllowlistPackages)
                AppSettings.removeHttpInspectionAppPackages(context, allAllowlistPackages)
                appAllowlistUpdated = true
            }
        }

        if (config.appAllowlistEnabled) {
            AppSettings.setAppAllowlistEnabled(context, true)
            appAllowlistUpdated = true
            val detail = "单应用域名放行开关 -> 已启用"
            updatedSettingsDetails.add(detail)
            logs.add("设置 $detail")
        }

        if (config.httpInspection != null) {
            val insp = config.httpInspection
            val validPackages = insp.appPackages.filter { it.isNotBlank() && !it.contains(" ") && it != context.packageName }.toSet()
            AppSettings.setHttpInspectionAppPackages(context, validPackages)
            AppSettings.setHttpInspectionEnabled(context, insp.enabled)
            AppSettings.setHttp3InspectionEnabled(context, insp.http3Enabled)
            AppSettings.setExcludedAppPackages(context, AppSettings.getExcludedAppPackages(context) - validPackages)
            AppSettings.setBlockedAppPackages(context, AppSettings.getBlockedAppPackages(context) - validPackages)
            AppSettings.setAppAllowlistPackages(context, AppSettings.getAppAllowlistPackages(context) - validPackages)
            httpInspectionUpdated = true
            val detail = "HTTPS 抓包配置 (${validPackages.size} 个应用) -> ${if (insp.enabled) "已启用" else "已禁用"}"
            updatedSettingsDetails.add(detail)
            logs.add("设置 $detail")
            complete("HTTPS 抓包配置", "已应用 HTTPS 抓包配置")
        }

        if (config.domainRulesEnabled != null && AppSettings.isDomainRulesEnabled(context) != config.domainRulesEnabled) {
            AppSettings.setDomainRulesEnabled(context, config.domainRulesEnabled)
            val detail = "域名规则开关 -> ${if (config.domainRulesEnabled) "已启用" else "已禁用"}"
            updatedSettingsDetails.add(detail)
            logs.add("设置 $detail")
        }
        if (config.addressRulesEnabled != null && AppSettings.isAddressRulesEnabled(context) != config.addressRulesEnabled) {
            AppSettings.setAddressRulesEnabled(context, config.addressRulesEnabled)
            val detail = "地址规则开关 -> ${if (config.addressRulesEnabled) "已启用" else "已禁用"}"
            updatedSettingsDetails.add(detail)
            logs.add("设置 $detail")
        }
        if (config.encryptedDnsBlockingEnabled != null && AppSettings.isEncryptedDnsBlockingEnabled(context) != config.encryptedDnsBlockingEnabled) {
            AppSettings.setEncryptedDnsBlockingEnabled(context, config.encryptedDnsBlockingEnabled)
            val detail = "加密 DNS 拦截开关 -> ${if (config.encryptedDnsBlockingEnabled) "已启用" else "已禁用"}"
            updatedSettingsDetails.add(detail)
            logs.add("设置 $detail")
        }
        if (config.blockResponseMode != null) {
            AppSettings.setBlockResponseMode(context, config.blockResponseMode)
            val detail = "拦截响应策略 -> ${config.blockResponseMode.storageValue}"
            updatedSettingsDetails.add(detail)
            logs.add("设置 $detail")
        }
        if (config.dynamicBlockResponse != null) {
            val dyn = config.dynamicBlockResponse
            AppSettings.setDynamicBlockResponseConfig(
                context,
                DynamicBlockResponseConfig(
                    enabled = dyn.enabled,
                    requestThreshold = dyn.requestThreshold,
                    windowSeconds = dyn.windowSeconds,
                    nxDomainDurationSeconds = dyn.nxDomainDurationSeconds
                )
            )
            val detail = "动态拦截响应配置 -> ${if (dyn.enabled) "已启用" else "已禁用"}"
            updatedSettingsDetails.add(detail)
            logs.add("设置 $detail")
        }
        if (config.allowEditDefaultWhitelist != null) {
            AppSettings.setAllowEditDefaultWhitelist(context, config.allowEditDefaultWhitelist)
            val detail = "允许编辑默认白名单 -> ${if (config.allowEditDefaultWhitelist) "是" else "否"}"
            updatedSettingsDetails.add(detail)
            logs.add("设置 $detail")
        }
        if (config.subscriptionAutoUpdate != null) {
            val auto = config.subscriptionAutoUpdate
            SubscriptionAutoUpdateSettings.save(context, auto.enabled, auto.intervalHours)
            SubscriptionAutoUpdateScheduler.sync(context)
            val detail = "规则订阅自动更新 -> ${if (auto.enabled) "每 ${auto.intervalHours} 小时" else "已禁用"}"
            updatedSettingsDetails.add(detail)
            logs.add("设置 $detail")
        }

        if (config.appearance != null) {
            val app = config.appearance
            app.appThemeMode?.let { AppSettings.setAppThemeMode(context, AppThemeMode.fromStorageValue(it)) }
            app.themeColorStyle?.let { AppSettings.setThemeColorStyle(context, ThemeColorStyle.fromStorageValue(it)) }
            app.homeComponentOpacity?.let { AppSettings.setHomeComponentOpacity(context, it) }
            app.homePowerButtonOpacity?.let { AppSettings.setHomePowerButtonOpacity(context, it) }
            app.homeProviderSelectorOpacity?.let { AppSettings.setHomeProviderSelectorOpacity(context, it) }
            app.homeModeButtonOpacity?.let { AppSettings.setHomeModeButtonOpacity(context, it) }
            app.homePoemOpacity?.let { AppSettings.setHomePoemOpacity(context, it) }
            app.homeDnsDetailOpacity?.let { AppSettings.setHomeDnsDetailOpacity(context, it) }
            if (app.homeSentenceRunning != null && app.homeSentenceStopped != null) {
                AppSettings.setHomeSentences(context, app.homeSentenceRunning, app.homeSentenceStopped)
            }
            app.liquidGlassBottomBarEnabled?.let { AppSettings.setLiquidGlassBottomBarEnabled(context, it) }
            appearanceUpdated = true
            val detail = "外观与主题个性化"
            updatedSettingsDetails.add(detail)
            logs.add("更新 $detail")
            complete("外观与主题设置", "已应用外观与主题个性化配置")
        }

        if (config.systemSettings != null) {
            val sys = config.systemSettings
            sys.bypassLanEnabled?.let { AppSettings.setBypassLanEnabled(context, it) }
            sys.hideFromRecentsEnabled?.let { AppSettings.setHideFromRecentsEnabled(context, it) }
            sys.logRetentionDays?.let { AppSettings.setLogRetentionDays(context, it) }
            sys.dnsLogMode?.let { AppSettings.setDnsLogMode(context, DnsLogMode.fromStorageValue(it)) }
            sys.floatingLogEnabled?.let { AppSettings.setFloatingLogEnabled(context, it) }
            sys.floatingLogPanelSize?.let { AppSettings.setFloatingLogPanelSize(context, it) }
            sys.appTrafficStatsEnabled?.let { AppSettings.setAppTrafficStatsEnabled(context, it) }
            sys.trafficStatsRetentionDays?.let { AppSettings.setTrafficStatsRetentionDays(context, it) }
            sys.trafficStatsHideSystemApps?.let { AppSettings.setTrafficStatsHideSystemApps(context, it) }
            sys.disableStartupUpdateCheck?.let { AppSettings.setStartupUpdateCheckDisabled(context, it) }
            sys.appLanguageMode?.let { AppLanguageManager.setMode(context, AppLanguageMode.fromStorageValue(it)) }
            sys.persistentNotificationEnabled?.let { NotificationSettingsStore.setPersistentNotificationEnabled(context, it) }
            sys.trafficSpeedEnabled?.let { NotificationSettingsStore.setTrafficSpeedEnabled(context, it) }
            if (sys.customRunningNotificationText != null && sys.customStoppedNotificationText != null) {
                NotificationSettingsStore.setCustomTexts(context, sys.customRunningNotificationText, sys.customStoppedNotificationText)
            }
            systemSettingsUpdated = true
            val detail = "系统与通用设置"
            updatedSettingsDetails.add(detail)
            logs.add("更新 $detail")
            complete("系统与通用设置", "已应用系统与通用设置")
        }

        if (customRulesAdded > 0) {
            RuntimeDnsSettingsRefresher.refreshRuleIndexesIfRunning(
                context, refreshBlock = true, refreshAllow = true, refreshRewrite = true, scope = RuleScope.DNS
            )
            RuntimeDnsSettingsRefresher.syncHttpsRequestRulesIfRunning(context)
            logs.add("已同步更新运行时规则索引")
        }

        logs.add("导入完成：新增 $added 项，跳过 $skipped 项" + if (failed > 0) "，失败 $failed 项" else "")

        return ConfigImportResult(
            added = added,
            skipped = skipped,
            failed = failed,
            excludedAppsUpdated = excludedAppsUpdated,
            blockedAppsUpdated = blockedAppsUpdated,
            appAllowlistUpdated = appAllowlistUpdated,
            httpInspectionUpdated = httpInspectionUpdated,
            outboundProxyUpdated = outboundProxyUpdated,
            dnsCacheUpdated = dnsCacheUpdated,
            appearanceUpdated = appearanceUpdated,
            systemSettingsUpdated = systemSettingsUpdated,
            subscriptionsAdded = subscriptionsAdded,
            customRulesAdded = customRulesAdded,
            addedDetails = addedDetails,
            skippedDetails = skippedDetails,
            failedDetails = failedDetails,
            updatedSettingsDetails = updatedSettingsDetails,
            logs = logs
        )
    }

    private fun providerKey(provider: DnsProvider): String = providerKey(
        ImportedProvider(provider.name, provider.protocol, provider.url, provider.host, provider.port)
    )

    private fun providerKey(provider: ImportedProvider): String = when (provider.protocol) {
        DnsProtocol.DOH -> "${provider.protocol.name}:${provider.url.lowercase()}"
        else -> "${provider.protocol.name}:${provider.host.lowercase()}:${provider.port}"
    }

    private fun subscriptionKey(url: String, scope: RuleScope) =
        "${scope.storageValue}:${url.trim().lowercase()}"
}
