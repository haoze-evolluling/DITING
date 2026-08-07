package com.haoze.dnssr.ui

import android.content.Context
import com.haoze.dnssr.data.AppDatabase
import com.haoze.dnssr.data.entity.RuleScope
import com.haoze.dnssr.vpn.AllowListManager
import com.haoze.dnssr.vpn.AdGuardRuleParser
import com.haoze.dnssr.vpn.BlockListManager
import com.haoze.dnssr.vpn.DnsProtocol
import com.haoze.dnssr.vpn.DnsProvider
import com.haoze.dnssr.vpn.SubscriptionManager
import com.haoze.dnssr.vpn.RewriteRuleManager
import org.json.JSONArray
import org.json.JSONObject
import com.haoze.dnssr.vpn.HttpsRuleBackupCodec
import com.haoze.dnssr.vpn.HttpsRuleBackupSource
import com.haoze.dnssr.vpn.HttpsRuleBackupTransfer

data class ConfigExportSelection(
    val providers: Boolean,
    val bootstrapIps: Boolean,
    val subscriptions: Boolean,
    val excludedApps: Boolean,
    val blockedApps: Boolean,
    val appAllowlist: Boolean
)

data class ConfigImportResult(
    val added: Int,
    val skipped: Int,
    val failed: Int,
    val excludedAppsUpdated: Boolean,
    val blockedAppsUpdated: Boolean,
    val appAllowlistUpdated: Boolean
) {
    fun message(): String = "导入完成：新增 $added 项，跳过 $skipped 项，失败 $failed 项"
}

data class ConfigImportProgress(
    val processed: Int,
    val total: Int,
    val currentItem: String
)

enum class RuleExportType(
    val fileNameSuffix: String,
    val displayName: String
) {
    SUBSCRIPTIONS("subscriptions", "订阅规则"),
    MANUAL("manual", "手动添加规则"),
    ALL("all", "全部规则")
}

data class RuleExportRequest(
    val type: RuleExportType,
    val scope: RuleScope
) {
    val fileNameSuffix: String get() = "${scope.storageValue}-${type.fileNameSuffix}"
}

class ConfigTransferManager(private val context: Context) {
    private val database = AppDatabase.getInstance(context)
    private fun subscriptionManager(scope: RuleScope) = SubscriptionManager(
        database,
        database.subscriptionDao(),
        BlockListManager(database.blockRuleDao(), scope = scope),
        AllowListManager(database.allowRuleDao(), scope = scope),
        RewriteRuleManager(database.rewriteRuleDao(), java.io.File(context.filesDir, "rule-index"), scope),
        scope
    )

    suspend fun export(selection: ConfigExportSelection): String {
        val root = JSONObject()
            .put("formatVersion", FORMAT_VERSION)
            .put("exportedAt", System.currentTimeMillis())

        if (selection.providers) {
            root.put("providers", JSONArray().apply {
                DnsProvider.loadUserProviders(context).forEach { provider ->
                    put(JSONObject()
                        .put("name", provider.name)
                        .put("protocol", provider.protocol.name)
                        .put("url", provider.url)
                        .put("host", provider.host)
                        .put("port", provider.port))
                }
            })
        }
        if (selection.bootstrapIps) {
            root.put("bootstrapIps", JSONArray().apply {
                AppSettings.loadBootstrapIpEntries(context).filterNot { it.isPreset }.forEach { entry ->
                    put(JSONObject()
                        .put("name", entry.name)
                        .put("ip", entry.ip)
                        .put("enabled", entry.enabled))
                }
            })
        }
        if (selection.subscriptions) {
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
                        .put("scope", subscription.scope)
                        .put("groupName", groups.firstOrNull { it.id == subscription.groupId }?.name))
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
            root.put("appAllowlistApps", JSONArray().apply { AppSettings.getAppAllowlistPackages(context).forEach(::put) })
            root.put("appAllowlistDomains", JSONArray().apply { AppSettings.getAppAllowlistDomains(context).forEach(::put) })
            root.put("appAllowlistEnabled", AppSettings.isAppAllowlistEnabled(context))
        }
        return root.toString(2)
    }

    suspend fun exportRules(
        request: RuleExportRequest,
        onProgress: (Float, String) -> Unit = { _, _ -> }
    ): RuleExportResult {
        if (request.scope == RuleScope.HTTPS) {
            onProgress(0f, "正在读取 HTTPS 规则")
            val source = when (request.type) {
                RuleExportType.SUBSCRIPTIONS -> HttpsRuleBackupSource.SUBSCRIPTIONS
                RuleExportType.MANUAL -> HttpsRuleBackupSource.MANUAL
                RuleExportType.ALL -> HttpsRuleBackupSource.ALL
            }
            val backup = HttpsRuleBackupTransfer.export(database, source)
            onProgress(0.6f, "正在生成 HTTPS 备份")
            return RuleExportResult(
                content = HttpsRuleBackupCodec.encode(backup),
                blockRuleCount = backup.blockRules.size,
                allowRuleCount = backup.allowRules.size,
                rewriteRuleCount = backup.rewriteRules.size,
                urlBlockRuleCount = backup.urlBlockRules.size,
                urlAllowRuleCount = backup.urlAllowRules.size
            ).also { onProgress(0.6f, "正在写入文件") }
        }
        onProgress(0f, "正在读取白名单规则")
        val allowRules = when (request.type) {
            RuleExportType.SUBSCRIPTIONS -> database.allowRuleDao().enabledSubscriptionRules(request.scope.storageValue)
            RuleExportType.MANUAL -> database.allowRuleDao().enabledCustomRules(request.scope.storageValue)
            RuleExportType.ALL -> database.allowRuleDao().enabledSubscriptionRules(request.scope.storageValue) +
                database.allowRuleDao().enabledCustomRules(request.scope.storageValue)
        }
        val allowPatterns = allowRules
            .map { it.pattern }
            .mapNotNull(AdGuardRuleParser::parseAllowLine)
            .mapTo(sortedSetOf()) { it.pattern }
        onProgress(0.2f, "正在读取拦截规则")
        val blockRules = when (request.type) {
            RuleExportType.SUBSCRIPTIONS -> database.blockRuleDao().enabledSubscriptionRules(request.scope.storageValue)
            RuleExportType.MANUAL -> database.blockRuleDao().enabledCustomRules(request.scope.storageValue)
            RuleExportType.ALL -> database.blockRuleDao().enabledSubscriptionRules(request.scope.storageValue) +
                database.blockRuleDao().enabledCustomRules(request.scope.storageValue)
        }
        val blockPatterns = blockRules
            .filter { it.important || it.pattern !in allowPatterns }
            .mapTo(sortedSetOf()) { rule -> if (rule.important) "||${rule.pattern}^${'$'}important" else "||${rule.pattern}^" }
        onProgress(0.4f, "正在生成导出文件")
        val exportedAt = java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.US)
            .format(java.util.Date())
        val totalRules = blockPatterns.size + allowPatterns.size
        var generatedRules = 0
        val content = buildString {
            appendLine("! 谛听 rules export")
            appendLine("! Exported at: $exportedAt")
            appendLine("! Block rules: ${blockPatterns.size}; allow rules: ${allowPatterns.size}")
            appendLine()
            blockPatterns.forEach {
                appendLine(it)
                generatedRules++
                onProgress(0.4f + 0.2f * generatedRules / totalRules.coerceAtLeast(1), "正在生成导出文件")
            }
            allowPatterns.forEach {
                appendLine("@@||$it^")
                generatedRules++
                onProgress(0.4f + 0.2f * generatedRules / totalRules.coerceAtLeast(1), "正在生成导出文件")
            }
        }
        onProgress(0.6f, "正在写入文件")
        return RuleExportResult(content, blockPatterns.size, allowPatterns.size)
    }

    suspend fun import(
        content: String,
        onProgress: (ConfigImportProgress) -> Unit = {}
    ): ConfigImportResult {
        val config = parseAndValidate(content)
        var added = 0
        var skipped = 0
        var failed = 0
        var excludedAppsUpdated = false
        var blockedAppsUpdated = false
        var appAllowlistUpdated = false
        var processed = 0
        val total = config.providers.size + config.bootstrapIps.size + config.subscriptions.size +
            config.excludedApps.size + config.blockedApps.size + config.appAllowlistApps.size + config.appAllowlistDomains.size

        fun report(item: String) {
            onProgress(ConfigImportProgress(processed, total, item))
        }

        fun complete(item: String) {
            processed++
            onProgress(ConfigImportProgress(processed, total, item))
        }

        val existingProviderKeys = DnsProvider.loadUserProviders(context)
            .map(::providerKey).toMutableSet()
        config.providers.forEach { provider ->
            val item = "DNS 服务商：${provider.name}"
            report(item)
            val key = providerKey(provider)
            if (!existingProviderKeys.add(key)) {
                skipped++
            } else {
                DnsProvider.addUserProvider(
                    context, provider.name, provider.protocol, provider.url, provider.host, provider.port
                )
                added++
            }
            complete(item)
        }

        val existingIps = AppSettings.loadBootstrapIpEntries(context)
            .filterNot { it.isPreset }.map { it.ip.lowercase() }.toMutableSet()
        config.bootstrapIps.forEach { entry ->
            val item = "Bootstrap IP：${entry.name}"
            report(item)
            if (!existingIps.add(entry.ip.lowercase())) {
                skipped++
            } else {
                val saved = AppSettings.addCustomBootstrapIp(context, entry.name, entry.ip)
                if (saved == null) {
                    failed++
                } else {
                    AppSettings.setBootstrapIpEnabled(context, saved.id, entry.enabled)
                    added++
                }
            }
            complete(item)
        }

        val groupDao = database.subscriptionGroupDao()
        val importedGroupIds = mutableMapOf<String, Long>()
        config.subscriptionGroups.forEach { group ->
            val existing = groupDao.byName(group.name)
            val id = existing?.id ?: groupDao.insert(
                com.haoze.dnssr.data.entity.SubscriptionGroupEntity(
                    name = group.name,
                    autoUpdateEnabled = group.autoUpdateEnabled
                )
            )
            importedGroupIds[group.name.lowercase()] = id
        }

        val existingSubscriptionKeys = database.subscriptionDao().allRemote()
            .map { subscriptionKey(it.url, RuleScope.fromStorage(it.scope)) }.toMutableSet()
        config.subscriptions.forEach { entry ->
            val item = "规则订阅：${entry.name}"
            report(item)
            val key = subscriptionKey(entry.url, entry.scope)
            if (!existingSubscriptionKeys.add(key)) {
                skipped++
            } else {
                val result = subscriptionManager(entry.scope).addRemoteSubscription(
                    entry.url,
                    entry.name,
                    entry.groupName?.let { importedGroupIds[it.lowercase()] }
                )
                if (result.isFailure) {
                    failed++
                } else {
                    added++
                }
            }
            complete(item)
        }

        if (config.excludedApps.isNotEmpty()) {
            val installedPackages = context.packageManager.getInstalledApplications(0)
                .mapTo(mutableSetOf()) { it.packageName }
            val validPackages = config.excludedApps.filter { it in installedPackages }.toSet()
            val invalidCount = config.excludedApps.size - validPackages.size
            val existingPackages = AppSettings.getExcludedAppPackages(context)
            val newPackages = validPackages - existingPackages
            AppSettings.setExcludedAppPackages(context, existingPackages + validPackages)
            AppSettings.removeHttpInspectionAppPackages(context, validPackages)
            AppSettings.setBlockedAppPackages(context, AppSettings.getBlockedAppPackages(context) - validPackages)
            AppSettings.setAppAllowlistPackages(context, AppSettings.getAppAllowlistPackages(context) - validPackages)
            excludedAppsUpdated = newPackages.isNotEmpty()
            added += newPackages.size
            skipped += validPackages.size - newPackages.size + invalidCount
            config.excludedApps.forEach { packageName -> complete("排除应用：$packageName") }
        }
        if (config.blockedApps.isNotEmpty()) {
            val installedPackages = context.packageManager.getInstalledApplications(0)
                .mapTo(mutableSetOf()) { it.packageName }
            val validPackages = config.blockedApps
                .filter { it in installedPackages && it != context.packageName }
                .toSet()
            val invalidCount = config.blockedApps.size - validPackages.size
            val existingPackages = AppSettings.getBlockedAppPackages(context)
            val newPackages = validPackages - existingPackages
            AppSettings.setBlockedAppPackages(context, existingPackages + validPackages)
            AppSettings.setExcludedAppPackages(context, AppSettings.getExcludedAppPackages(context) - validPackages)
            AppSettings.removeHttpInspectionAppPackages(context, validPackages)
            AppSettings.setAppAllowlistPackages(context, AppSettings.getAppAllowlistPackages(context) - validPackages)
            blockedAppsUpdated = newPackages.isNotEmpty()
            added += newPackages.size
            skipped += validPackages.size - newPackages.size + invalidCount
            config.blockedApps.forEach { packageName -> complete("禁止联网应用：$packageName") }
        }
        if (AppSettings.isBlockedAppsEnabled(context) != config.blockedAppsEnabled) {
            AppSettings.setBlockedAppsEnabled(context, config.blockedAppsEnabled)
            blockedAppsUpdated = true
        }
        if (config.appAllowlistApps.isNotEmpty()) {
            val installed = context.packageManager.getInstalledApplications(0).mapTo(mutableSetOf()) { it.packageName }
            val valid = config.appAllowlistApps.filter { it in installed && it != context.packageName }.toSet()
            val newPackages = valid - AppSettings.getAppAllowlistPackages(context)
            AppSettings.setAppAllowlistPackages(context, AppSettings.getAppAllowlistPackages(context) + valid)
            AppSettings.setExcludedAppPackages(context, AppSettings.getExcludedAppPackages(context) - valid)
            AppSettings.setBlockedAppPackages(context, AppSettings.getBlockedAppPackages(context) - valid)
            AppSettings.removeHttpInspectionAppPackages(context, valid)
            added += newPackages.size; skipped += valid.size - newPackages.size
            config.appAllowlistApps.forEach { complete("应用白名单访问：$it") }
            appAllowlistUpdated = newPackages.isNotEmpty()
        }
        val validDomains = config.appAllowlistDomains.mapNotNull { AdGuardRuleParser.parseAllowLine(it)?.pattern }.toSet()
        if (validDomains.isNotEmpty()) {
            val newDomains = validDomains - AppSettings.getAppAllowlistDomains(context)
            AppSettings.setAppAllowlistDomains(context, AppSettings.getAppAllowlistDomains(context) + validDomains)
            added += newDomains.size; skipped += validDomains.size - newDomains.size
            config.appAllowlistDomains.forEach { complete("应用白名单域名：$it") }
            appAllowlistUpdated = appAllowlistUpdated || newDomains.isNotEmpty()
        }
        if (config.appAllowlistEnabled && AppSettings.getAppAllowlistPackages(context).isNotEmpty() && AppSettings.getAppAllowlistDomains(context).isNotEmpty()) {
            AppSettings.setAppAllowlistEnabled(context, true); appAllowlistUpdated = true
        }
        return ConfigImportResult(added, skipped, failed, excludedAppsUpdated, blockedAppsUpdated, appAllowlistUpdated)
    }

    private fun parseAndValidate(content: String): TransferConfig {
        val root = try {
            JSONObject(content)
        } catch (_: Exception) {
            throw IllegalArgumentException("配置文件不是有效的 JSON")
        }
        val formatVersion = root.optInt("formatVersion", -1)
        if (formatVersion !in SUPPORTED_FORMAT_VERSIONS) {
            throw IllegalArgumentException("不支持的配置文件版本")
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
        val bootstrapIps = root.optionalArray("bootstrapIps").mapObjects { obj ->
            val ip = obj.requiredString("ip")
            if (!AppSettings.isValidBootstrapIp(ip)) throw IllegalArgumentException("配置中包含无效的 Bootstrap IP")
            ImportedBootstrap(obj.requiredString("name"), ip, obj.optBoolean("enabled", true))
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
                RuleScope.DNS.storageValue -> RuleScope.DNS
                RuleScope.HTTPS.storageValue -> RuleScope.HTTPS
                else -> throw IllegalArgumentException("配置中包含不支持的订阅作用域：$value")
            }
            ImportedSubscription(obj.requiredString("name"), url, scope, obj.optString("groupName", "").trim().takeIf { it.isNotEmpty() })
        }
        val excludedApps = root.optionalArray("excludedApps").mapStrings()
            .filter { it.isNotBlank() }
            .toSet()
        val blockedApps = root.optionalArray("blockedApps").mapStrings()
            .filter { it.isNotBlank() }
            .toSet()
        val blockedAppsEnabled = when {
            formatVersion >= 4 -> root.optBoolean("blockedAppsEnabled", false)
            formatVersion == 3 -> blockedApps.isNotEmpty()
            else -> false
        }
        val appAllowlistApps = root.optionalArray("appAllowlistApps").mapStrings().toSet()
        val appAllowlistDomains = root.optionalArray("appAllowlistDomains").mapStrings().toSet()
        val appAllowlistEnabled = root.optBoolean("appAllowlistEnabled", false)
        return TransferConfig(providers, bootstrapIps, subscriptionGroups, subscriptions, excludedApps, blockedApps, blockedAppsEnabled, appAllowlistApps, appAllowlistDomains, appAllowlistEnabled)
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

    private fun JSONObject.requiredString(key: String): String = optString(key, "").trim()
        .takeIf { it.isNotEmpty() } ?: throw IllegalArgumentException("配置缺少 $key")

    private fun JSONObject.optionalArray(key: String): JSONArray = when {
        !has(key) -> JSONArray()
        optJSONArray(key) != null -> getJSONArray(key)
        else -> throw IllegalArgumentException("配置字段 $key 格式错误")
    }

    private fun <T> JSONArray.mapObjects(transform: (JSONObject) -> T): List<T> = buildList {
        for (index in 0 until length()) {
            val item = optJSONObject(index) ?: throw IllegalArgumentException("配置列表格式错误")
            add(transform(item))
        }
    }

    private fun JSONArray.mapStrings(): List<String> = buildList {
        for (index in 0 until length()) {
            val item = optString(index, "").trim()
            if (item.isEmpty()) throw IllegalArgumentException("配置列表格式错误")
            add(item)
        }
    }

    private data class TransferConfig(
        val providers: List<ImportedProvider>,
        val bootstrapIps: List<ImportedBootstrap>,
        val subscriptionGroups: List<ImportedSubscriptionGroup>,
        val subscriptions: List<ImportedSubscription>,
        val excludedApps: Set<String>,
        val blockedApps: Set<String>,
        val blockedAppsEnabled: Boolean,
        val appAllowlistApps: Set<String>,
        val appAllowlistDomains: Set<String>,
        val appAllowlistEnabled: Boolean
    )

    private data class ImportedProvider(
        val name: String,
        val protocol: DnsProtocol,
        val url: String,
        val host: String,
        val port: Int
    )

    private data class ImportedBootstrap(val name: String, val ip: String, val enabled: Boolean)
    private data class ImportedSubscriptionGroup(val name: String, val autoUpdateEnabled: Boolean)
    private data class ImportedSubscription(val name: String, val url: String, val scope: RuleScope, val groupName: String?)

    companion object {
        private const val FORMAT_VERSION = 7
        private val SUPPORTED_FORMAT_VERSIONS = setOf(1, 2, 3, 4, 5, 6, FORMAT_VERSION)
    }
}

data class RuleExportResult(
    val content: String,
    val blockRuleCount: Int,
    val allowRuleCount: Int,
    val rewriteRuleCount: Int = 0,
    val urlBlockRuleCount: Int = 0,
    val urlAllowRuleCount: Int = 0
) {
    fun summary(): String = buildString {
        append("屏蔽 $blockRuleCount 条，放行 $allowRuleCount 条")
        if (rewriteRuleCount > 0) append("，CNAME $rewriteRuleCount 条")
        if (urlBlockRuleCount > 0 || urlAllowRuleCount > 0) {
            append("，URL 屏蔽 $urlBlockRuleCount 条，URL 放行 $urlAllowRuleCount 条")
        }
    }
}
