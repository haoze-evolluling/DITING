package com.haoze.dnssr.vpn

import com.haoze.dnssr.data.AppDatabase
import com.haoze.dnssr.data.entity.RewriteTargetType
import com.haoze.dnssr.data.entity.RuleScope
import org.json.JSONArray
import org.json.JSONObject
import java.net.URI

enum class HttpsRuleBackupSource(val storageValue: String) {
    SUBSCRIPTIONS("subscriptions"),
    MANUAL("manual"),
    ALL("all")
}

data class HttpsRuleBackup(
    val source: HttpsRuleBackupSource,
    val exportedAt: Long,
    val blockRules: List<AdGuardRuleParser.ParsedRule>,
    val allowRules: List<AdGuardRuleParser.ParsedRule>,
    val rewriteRules: List<RewriteRule>,
    val urlBlockRules: List<String>,
    val urlAllowRules: List<String>
) {
    val totalCount: Int get() = blockRules.size + allowRules.size + rewriteRules.size +
        urlBlockRules.size + urlAllowRules.size
}

data class HttpsRuleBackupRestoreResult(
    val blockCount: Int,
    val allowCount: Int,
    val rewriteCount: Int,
    val urlBlockCount: Int,
    val urlAllowCount: Int,
    val skippedCount: Int
) {
    fun message() = "恢复完成：屏蔽 $blockCount 条，放行 $allowCount 条，CNAME $rewriteCount 条，" +
        "URL 屏蔽 $urlBlockCount 条，URL 放行 $urlAllowCount 条，跳过 $skippedCount 条"
}

object HttpsRuleBackupCodec {
    private const val FORMAT = "dnssr_https_rule_backup"
    private const val VERSION = 1

    fun looksLikeBackup(content: String): Boolean = content.contains("\"format\"") && content.contains(FORMAT)

    fun encode(backup: HttpsRuleBackup): String = JSONObject()
        .put("format", FORMAT)
        .put("version", VERSION)
        .put("scope", RuleScope.HTTPS.storageValue)
        .put("source", backup.source.storageValue)
        .put("exportedAt", backup.exportedAt)
        .put("rules", JSONObject()
            .put("block", JSONArray().apply {
                backup.blockRules.forEach { rule ->
                    put(JSONObject().put("pattern", rule.pattern).put("important", rule.important))
                }
            })
            .put("allow", JSONArray().apply {
                backup.allowRules.forEach { rule -> put(rule.pattern) }
            })
            .put("rewrite", JSONArray().apply {
                backup.rewriteRules.forEach { rule ->
                    put(JSONObject()
                        .put("pattern", rule.pattern)
                        .put("targetType", rule.targetType)
                        .put("targetValue", rule.targetValue))
                }
            })
            .put("urlBlock", JSONArray(backup.urlBlockRules))
            .put("urlAllow", JSONArray(backup.urlAllowRules)))
        .toString(2)

    fun decode(content: String): HttpsRuleBackup {
        val root = try {
            JSONObject(content)
        } catch (_: Exception) {
            throw IllegalArgumentException("HTTPS 规则备份不是有效的 JSON")
        }
        require(root.optString("format") == FORMAT) { "不是 HTTPS 规则备份文件" }
        require(root.optInt("version", -1) == VERSION) { "不支持的 HTTPS 规则备份版本" }
        require(root.optString("scope") == RuleScope.HTTPS.storageValue) { "备份不属于 HTTPS 规则" }
        val source = HttpsRuleBackupSource.entries.firstOrNull { it.storageValue == root.optString("source") }
            ?: throw IllegalArgumentException("备份包含不支持的规则来源")
        val rules = root.optJSONObject("rules") ?: throw IllegalArgumentException("备份缺少规则内容")
        return HttpsRuleBackup(
            source = source,
            exportedAt = root.optLong("exportedAt", 0),
            blockRules = rules.requiredArray("block").mapObjects { item ->
                val pattern = item.requiredString("pattern")
                val important = item.optBoolean("important", false)
                AdGuardRuleParser.parseLine("||$pattern^" + if (important) "${'$'}important" else "")
                    ?: throw IllegalArgumentException("备份包含无效的屏蔽规则")
            },
            allowRules = rules.requiredArray("allow").mapStrings().map { pattern ->
                AdGuardRuleParser.parseAllowLine("@@||$pattern^")
                    ?: throw IllegalArgumentException("备份包含无效的放行规则")
            },
            rewriteRules = rules.requiredArray("rewrite").mapObjects { item ->
                val pattern = item.requiredString("pattern")
                val targetType = item.requiredString("targetType")
                val targetValue = item.requiredString("targetValue")
                require(targetType == RewriteTargetType.CNAME) { "备份包含不支持的覆写规则" }
                val normalizedPattern = AdGuardRuleParser.normalizeDomainForRewrite(pattern)
                    ?: throw IllegalArgumentException("备份包含无效的覆写规则")
                val normalizedTarget = AdGuardRuleParser.normalizeDomainForRewrite(targetValue)
                    ?: throw IllegalArgumentException("备份包含无效的覆写规则")
                RewriteRule(normalizedPattern, targetType, normalizedTarget, "$normalizedPattern -> $normalizedTarget")
            },
            urlBlockRules = rules.requiredArray("urlBlock").mapStrings().map(::normalizeUrlPattern),
            urlAllowRules = rules.requiredArray("urlAllow").mapStrings().map(::normalizeUrlPattern)
        )
    }

    private fun JSONObject.requiredArray(key: String): JSONArray = optJSONArray(key)
        ?: throw IllegalArgumentException("备份缺少 $key 规则")

    private fun JSONObject.requiredString(key: String): String = optString(key).trim()
        .takeIf { it.isNotEmpty() } ?: throw IllegalArgumentException("备份缺少 $key")

    private fun <T> JSONArray.mapObjects(transform: (JSONObject) -> T): List<T> {
        val objects = buildList {
            for (index in 0 until length()) {
                add(optJSONObject(index) ?: throw IllegalArgumentException("备份规则格式错误"))
            }
        }
        return objects.map(transform)
    }

    private fun JSONArray.mapStrings(): List<String> = buildList {
        for (index in 0 until length()) {
            val value = optString(index, "").trim()
            if (value.isEmpty()) throw IllegalArgumentException("备份规则格式错误")
            add(value)
        }
    }

    private fun normalizeUrlPattern(value: String): String {
        val uri = runCatching { URI(value) }.getOrNull()
            ?: throw IllegalArgumentException("备份包含无效的 URL 规则")
        val scheme = uri.scheme?.lowercase()
        require(scheme == "http" || scheme == "https") { "备份包含无效的 URL 规则" }
        require(!uri.host.isNullOrBlank() && uri.userInfo == null && uri.fragment == null) {
            "备份包含无效的 URL 规则"
        }
        val host = uri.host.lowercase()
        val port = uri.port.let { port ->
            if (port == -1 || (scheme == "http" && port == 80) || (scheme == "https" && port == 443)) "" else ":$port"
        }
        val path = (uri.rawPath ?: "/").ifBlank { "/" }
        return "$scheme://$host$port$path"
    }
}

object HttpsRuleBackupTransfer {
    suspend fun export(database: AppDatabase, source: HttpsRuleBackupSource): HttpsRuleBackup {
        val scope = RuleScope.HTTPS.storageValue
        val blockRules = when (source) {
            HttpsRuleBackupSource.SUBSCRIPTIONS -> database.blockRuleDao().enabledSubscriptionRules(scope)
            HttpsRuleBackupSource.MANUAL -> database.blockRuleDao().enabledCustomRules(scope)
            HttpsRuleBackupSource.ALL -> database.blockRuleDao().enabledSubscriptionRules(scope) +
                database.blockRuleDao().enabledCustomRules(scope)
        }.map { AdGuardRuleParser.ParsedRule(it.pattern, "||${it.pattern}^", it.important) }
            .distinctBy { "${it.pattern}:${it.important}" }
        val allowRules = when (source) {
            HttpsRuleBackupSource.SUBSCRIPTIONS -> database.allowRuleDao().enabledSubscriptionRules(scope)
            HttpsRuleBackupSource.MANUAL -> database.allowRuleDao().enabledCustomRules(scope)
            HttpsRuleBackupSource.ALL -> database.allowRuleDao().enabledSubscriptionRules(scope) +
                database.allowRuleDao().enabledCustomRules(scope)
        }.map { rule -> AdGuardRuleParser.ParsedRule(rule.pattern, "@@||${rule.pattern}^") }
            .distinctBy { it.pattern }
        val rewriteRules = when (source) {
            HttpsRuleBackupSource.SUBSCRIPTIONS -> database.rewriteRuleDao().enabledSubscriptionRules(scope)
            HttpsRuleBackupSource.MANUAL -> database.rewriteRuleDao().enabledManualRules(scope)
            HttpsRuleBackupSource.ALL -> database.rewriteRuleDao().enabledSubscriptionRules(scope) +
                database.rewriteRuleDao().enabledManualRules(scope)
        }.map { RewriteRule(it.pattern, it.targetType, it.targetValue, "${it.pattern} -> ${it.targetValue}") }
            .distinctBy { "${it.pattern}:${it.targetType}:${it.targetValue}" }
        val urlRules = when (source) {
            HttpsRuleBackupSource.SUBSCRIPTIONS -> emptyList()
            HttpsRuleBackupSource.MANUAL -> database.goUrlRuleDao().enabledRulesBySource("useradd")
            HttpsRuleBackupSource.ALL -> database.goUrlRuleDao().enabledRulesBySource("useradd")
        }
        return HttpsRuleBackup(
            source,
            System.currentTimeMillis(),
            blockRules,
            allowRules,
            rewriteRules,
            urlRules.filter { it.kind == "block" }.map { it.pattern }.sorted(),
            urlRules.filter { it.kind == "allow" }.map { it.pattern }.sorted()
        )
    }

    suspend fun restore(
        backup: HttpsRuleBackup,
        blockManager: BlockListManager,
        allowManager: AllowListManager,
        rewriteManager: RewriteRuleManager,
        goUrlRuleManager: GoUrlRuleManager
    ): HttpsRuleBackupRestoreResult {
        val block = blockManager.addRulesBatch(backup.blockRules, "useradd")
        val allow = allowManager.addRulesBatch(backup.allowRules, "useradd")
        val rewrite = rewriteManager.addRules(backup.rewriteRules, "useradd", true)
        val urlBlock = backup.urlBlockRules.count { goUrlRuleManager.addRule(it) }
        val urlAllow = backup.urlAllowRules.count { goUrlRuleManager.addRule("@@$it") }
        return HttpsRuleBackupRestoreResult(
            block,
            allow,
            rewrite,
            urlBlock,
            urlAllow,
            backup.totalCount - block - allow - rewrite - urlBlock - urlAllow
        )
    }
}
