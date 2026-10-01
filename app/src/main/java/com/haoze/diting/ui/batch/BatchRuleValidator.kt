package com.haoze.diting.ui.batch

import android.content.Context
import com.haoze.diting.data.RuleDataSources
import com.haoze.diting.data.RuleDataset
import com.haoze.diting.data.entity.AllowRuleEntity
import com.haoze.diting.data.entity.BlockRuleEntity
import com.haoze.diting.data.entity.GoUrlRuleKind
import com.haoze.diting.data.entity.RewriteRuleEntity
import com.haoze.diting.data.entity.RewriteTargetType
import com.haoze.diting.data.entity.RuleScope
import com.haoze.diting.ui.RuntimeDnsSettingsRefresher
import com.haoze.diting.vpn.AdGuardRuleParser
import com.haoze.diting.vpn.AllowListManager
import com.haoze.diting.vpn.BlockListManager
import com.haoze.diting.vpn.DefaultWhitelistSeeder
import com.haoze.diting.vpn.GoUrlRuleManager
import com.haoze.diting.vpn.RewriteRuleManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.net.InetAddress

/**
 * Validates multiline text input for Blacklist, Whitelist, and Rewrite rules.
 * Handles parsing, duplicate detection, and batch insertion.
 */
class BatchRuleValidator(
    private val database: RuleDataSources,
    private val dataset: RuleDataset,
    private val target: BatchRuleTarget
) {
    private val blockRuleDao = database.blockRuleDao()
    private val allowRuleDao = database.allowRuleDao()
    private val rewriteRuleDao = database.rewriteRuleDao()
    private val goUrlRuleDao = database.goUrlRuleDao()
    private val blockListManager = BlockListManager(blockRuleDao, scope = RuleScope.DNS)
    private val allowListManager = AllowListManager(allowRuleDao, scope = RuleScope.DNS)
    private val goUrlRuleManager = GoUrlRuleManager(goUrlRuleDao)
    private val rewriteRuleManager = RewriteRuleManager(rewriteRuleDao, scope = RuleScope.DNS)

    suspend fun validate(input: String): BatchValidationSummary = withContext(Dispatchers.IO) {
        val lines = input.lines()
        val validItems = mutableListOf<BatchRuleItem>()
        val duplicateItems = mutableListOf<BatchRuleItem.Duplicate>()
        val invalidItems = mutableListOf<BatchRuleItem.Invalid>()
        var ignoredCount = 0

        val seenKeys = mutableSetOf<String>()

        lines.forEachIndexed { index, line ->
            val lineNo = index + 1
            val trimmed = line.trim()

            if (trimmed.isEmpty() || trimmed.startsWith("#") || trimmed.startsWith("!")) {
                ignoredCount++
                return@forEachIndexed
            }

            when (target) {
                BatchRuleTarget.BLACKLIST -> validateBlacklistLine(
                    lineNo, trimmed, seenKeys, validItems, duplicateItems, invalidItems
                )
                BatchRuleTarget.WHITELIST -> validateWhitelistLine(
                    lineNo, trimmed, seenKeys, validItems, duplicateItems, invalidItems
                )
                BatchRuleTarget.REWRITE -> validateRewriteLine(
                    lineNo, trimmed, seenKeys, validItems, duplicateItems, invalidItems
                )
            }
        }

        BatchValidationSummary(
            target = target,
            totalLines = lines.size,
            validItems = validItems,
            duplicateItems = duplicateItems,
            invalidItems = invalidItems,
            ignoredCount = ignoredCount
        )
    }

    private suspend fun validateBlacklistLine(
        lineNo: Int,
        raw: String,
        seenKeys: MutableSet<String>,
        validItems: MutableList<BatchRuleItem>,
        duplicateItems: MutableList<BatchRuleItem.Duplicate>,
        invalidItems: MutableList<BatchRuleItem.Invalid>
    ) {
        val isHttpUrl = raw.startsWith("http://", ignoreCase = true) ||
                raw.startsWith("https://", ignoreCase = true) ||
                raw.startsWith("||http://", ignoreCase = true) ||
                raw.startsWith("||https://", ignoreCase = true)

        if (isHttpUrl) {
            if (dataset == RuleDataset.DNS_MODE) {
                invalidItems.add(BatchRuleItem.Invalid(lineNo, raw, "URL 规则仅普通模式支持"))
                return
            }
            val cleaned = if (raw.startsWith("||")) raw.removePrefix("||") else raw
            if (!isValidUrl(cleaned)) {
                invalidItems.add(BatchRuleItem.Invalid(lineNo, raw, "URL 格式无效"))
                return
            }
            val key = "url_block:$cleaned"
            if (!seenKeys.add(key)) {
                duplicateItems.add(BatchRuleItem.Duplicate(lineNo, raw, key, "输入中已存在相同规则"))
                return
            }
            if (goUrlRuleDao.idByPattern(cleaned, GoUrlRuleKind.BLOCK) > 0) {
                duplicateItems.add(BatchRuleItem.Duplicate(lineNo, raw, key, "黑名单中已存在该规则"))
                return
            }
            validItems.add(BatchRuleItem.ValidUrl(lineNo, raw, cleaned, isAllow = false))
            return
        }

        val normalizedLine = when {
            raw.startsWith("||") -> raw
            raw.startsWith("0.0.0.0 ") || raw.startsWith("127.0.0.1 ") -> raw
            else -> "||$raw^"
        }
        val parsed = AdGuardRuleParser.parseLine(normalizedLine)
            ?: AdGuardRuleParser.parseLine(raw)

        if (parsed == null || parsed.pattern.isBlank()) {
            invalidItems.add(BatchRuleItem.Invalid(lineNo, raw, "域名规则格式无效"))
            return
        }

        val key = AdGuardRuleParser.blockRuleKey(parsed)
        if (!seenKeys.add(key)) {
            duplicateItems.add(BatchRuleItem.Duplicate(lineNo, raw, key, "输入中已存在相同规则"))
            return
        }

        val exists = blockRuleDao.idByPattern(
            pattern = parsed.pattern,
            important = parsed.important,
            appScope = parsed.appScope,
            appInverted = parsed.appInverted,
            dnsType = parsed.dnsType,
            isRegex = parsed.isRegex
        ) > 0

        if (exists) {
            duplicateItems.add(BatchRuleItem.Duplicate(lineNo, raw, key, "黑名单中已存在该规则"))
            return
        }

        validItems.add(
            BatchRuleItem.ValidDomain(
                lineNumber = lineNo,
                rawLine = raw,
                pattern = parsed.pattern,
                appScope = parsed.appScope,
                important = parsed.important,
                isWildcard = parsed.isWildcard,
                denyallow = parsed.denyallow,
                isRegex = parsed.isRegex,
                dnsType = parsed.dnsType
            )
        )
    }

    private suspend fun validateWhitelistLine(
        lineNo: Int,
        raw: String,
        seenKeys: MutableSet<String>,
        validItems: MutableList<BatchRuleItem>,
        duplicateItems: MutableList<BatchRuleItem.Duplicate>,
        invalidItems: MutableList<BatchRuleItem.Invalid>
    ) {
        val isHttpUrl = raw.startsWith("http://", ignoreCase = true) ||
                raw.startsWith("https://", ignoreCase = true) ||
                raw.startsWith("@@http://", ignoreCase = true) ||
                raw.startsWith("@@https://", ignoreCase = true)

        if (isHttpUrl) {
            if (dataset == RuleDataset.DNS_MODE) {
                invalidItems.add(BatchRuleItem.Invalid(lineNo, raw, "URL 规则仅普通模式支持"))
                return
            }
            val cleaned = if (raw.startsWith("@@")) raw else "@@$raw"
            val rawUrl = cleaned.removePrefix("@@")
            if (!isValidUrl(rawUrl)) {
                invalidItems.add(BatchRuleItem.Invalid(lineNo, raw, "URL 格式无效"))
                return
            }
            val key = "url_allow:$cleaned"
            if (!seenKeys.add(key)) {
                duplicateItems.add(BatchRuleItem.Duplicate(lineNo, raw, key, "输入中已存在相同规则"))
                return
            }
            if (goUrlRuleDao.idByPattern(cleaned, GoUrlRuleKind.ALLOW) > 0) {
                duplicateItems.add(BatchRuleItem.Duplicate(lineNo, raw, key, "白名单中已存在该规则"))
                return
            }
            validItems.add(BatchRuleItem.ValidUrl(lineNo, raw, cleaned, isAllow = true))
            return
        }

        val normalizedLine = when {
            raw.startsWith("@@") -> raw
            raw.startsWith("||") -> "@@$raw"
            else -> "@@||$raw^"
        }
        val parsed = AdGuardRuleParser.parseAllowLine(normalizedLine)
            ?: AdGuardRuleParser.parseAllowLine("@@$raw")

        if (parsed == null || parsed.pattern.isBlank()) {
            invalidItems.add(BatchRuleItem.Invalid(lineNo, raw, "域名规则格式无效"))
            return
        }

        val key = AdGuardRuleParser.allowRuleKey(parsed)
        if (!seenKeys.add(key)) {
            duplicateItems.add(BatchRuleItem.Duplicate(lineNo, raw, key, "输入中已存在相同规则"))
            return
        }

        val exists = allowRuleDao.idByPattern(
            pattern = parsed.pattern,
            important = parsed.important,
            appScope = parsed.appScope,
            appInverted = parsed.appInverted,
            dnsType = parsed.dnsType,
            isRegex = parsed.isRegex
        ) > 0

        if (exists) {
            duplicateItems.add(BatchRuleItem.Duplicate(lineNo, raw, key, "白名单中已存在该规则"))
            return
        }

        validItems.add(
            BatchRuleItem.ValidDomain(
                lineNumber = lineNo,
                rawLine = raw,
                pattern = parsed.pattern,
                appScope = parsed.appScope,
                important = parsed.important,
                isWildcard = parsed.isWildcard,
                denyallow = parsed.denyallow,
                isRegex = parsed.isRegex,
                dnsType = parsed.dnsType
            )
        )
    }

    private suspend fun validateRewriteLine(
        lineNo: Int,
        raw: String,
        seenKeys: MutableSet<String>,
        validItems: MutableList<BatchRuleItem>,
        duplicateItems: MutableList<BatchRuleItem.Duplicate>,
        invalidItems: MutableList<BatchRuleItem.Invalid>
    ) {
        val extractedPairs = parseRewriteTokens(raw)
        if (extractedPairs.isEmpty()) {
            invalidItems.add(BatchRuleItem.Invalid(lineNo, raw, "覆写规则格式无效，支持 hosts 格式或域名->目标映射"))
            return
        }

        for ((rawDomain, rawTarget) in extractedPairs) {
            val normalizedDomain = AdGuardRuleParser.normalizeDomainForRewrite(rawDomain)
            if (normalizedDomain == null) {
                invalidItems.add(BatchRuleItem.Invalid(lineNo, raw, "域名格式无效: $rawDomain"))
                continue
            }

            val targetTypeAndValue = parseRewriteTarget(rawTarget)
            if (targetTypeAndValue == null) {
                invalidItems.add(BatchRuleItem.Invalid(lineNo, raw, "目标地址格式无效 (须为 IPv4/IPv6 或 CNAME 域名): $rawTarget"))
                continue
            }
            val (targetType, targetValue) = targetTypeAndValue

            val isCname = targetType == RewriteTargetType.CNAME
            if (isCname && rewriteRuleDao.countOtherTypes(normalizedDomain, targetType) > 0) {
                invalidItems.add(BatchRuleItem.Invalid(lineNo, raw, "该域名已存在 IP 覆写规则，不能同时添加 CNAME: $normalizedDomain"))
                continue
            }
            if (!isCname && rewriteRuleDao.countType(normalizedDomain, RewriteTargetType.CNAME) > 0) {
                invalidItems.add(BatchRuleItem.Invalid(lineNo, raw, "该域名已存在 CNAME 覆写规则，不能同时添加 IP: $normalizedDomain"))
                continue
            }

            val key = "rewrite:$normalizedDomain:$targetType:$targetValue"
            if (!seenKeys.add(key)) {
                duplicateItems.add(BatchRuleItem.Duplicate(lineNo, raw, key, "输入中已存在相同规则"))
                continue
            }

            if (rewriteRuleDao.idByKey(normalizedDomain, targetType, targetValue) > 0) {
                duplicateItems.add(BatchRuleItem.Duplicate(lineNo, raw, key, "覆写名单中已存在该规则"))
                continue
            }

            validItems.add(
                BatchRuleItem.ValidRewrite(
                    lineNumber = lineNo,
                    rawLine = "$normalizedDomain -> $targetValue",
                    domain = normalizedDomain,
                    targetType = targetType,
                    targetValue = targetValue
                )
            )
        }
    }

    private fun parseRewriteTokens(raw: String): List<Pair<String, String>> {
        val content = raw.substringBefore('#').trim()
        if (content.contains("\$dnsrewrite=")) {
            val parts = content.split("\$dnsrewrite=", limit = 2)
            val domainPart = parts[0].removePrefix("||").removeSuffix("^").trim()
            val targetPart = parts.getOrNull(1)?.trim().orEmpty()
            if (domainPart.isNotEmpty() && targetPart.isNotEmpty()) {
                return listOf(domainPart to targetPart)
            }
        }

        val delimiter = when {
            content.contains("->") -> "->"
            content.contains("=>") -> "=>"
            content.contains("=") -> "="
            else -> null
        }
        if (delimiter != null) {
            val parts = content.split(delimiter, limit = 2).map { it.trim() }
            if (parts.size == 2 && parts[0].isNotEmpty() && parts[1].isNotEmpty()) {
                return listOf(parts[0] to parts[1])
            }
        }

        val tokens = content.split(Regex("\\s+")).filter { it.isNotEmpty() }
        if (tokens.size >= 2) {
            val first = tokens[0]
            val second = tokens[1]
            if (isIpAddress(first)) {
                return tokens.drop(1).map { domain -> domain to first }
            }
            if (isIpAddress(second)) {
                return listOf(first to second)
            }
            return listOf(first to second)
        }

        return emptyList()
    }

    private fun parseRewriteTarget(target: String): Pair<String, String>? {
        val trimmed = target.trim()
        if (AdGuardRuleParser.looksLikeLiteralIp(trimmed)) {
            val addr = runCatching { InetAddress.getByName(trimmed) }.getOrNull()
            if (addr != null) {
                return when (addr.address.size) {
                    4 -> RewriteTargetType.IPV4 to (addr.hostAddress ?: trimmed)
                    16 -> RewriteTargetType.IPV6 to (addr.hostAddress ?: trimmed)
                    else -> null
                }
            }
        }
        val cname = AdGuardRuleParser.normalizeDomainForRewrite(trimmed) ?: return null
        return RewriteTargetType.CNAME to cname
    }

    private fun isIpAddress(token: String): Boolean {
        return AdGuardRuleParser.looksLikeLiteralIp(token)
    }

    private fun isValidUrl(url: String): Boolean {
        val trimmed = url.trim()
        return (trimmed.startsWith("http://", ignoreCase = true) || trimmed.startsWith("https://", ignoreCase = true)) &&
                trimmed.length > 8 && !trimmed.contains(" ")
    }

    suspend fun commit(context: Context, validItems: List<BatchRuleItem>): Int = withContext(Dispatchers.IO) {
        val now = System.currentTimeMillis()
        var insertedCount = 0

        when (target) {
            BatchRuleTarget.BLACKLIST -> {
                val domainItems = validItems.filterIsInstance<BatchRuleItem.ValidDomain>()
                val urlItems = validItems.filterIsInstance<BatchRuleItem.ValidUrl>()

                if (domainItems.isNotEmpty()) {
                    val entities = domainItems.map { item ->
                        BlockRuleEntity(
                            pattern = item.pattern,
                            rawLine = item.rawLine,
                            addedAt = now,
                            enabled = true,
                            groupName = null,
                            appScope = item.appScope,
                            appInverted = false,
                            isWildcard = item.isWildcard,
                            denyallow = item.denyallow,
                            isRegex = item.isRegex,
                            dnsType = item.dnsType,
                            important = item.important
                        )
                    }
                    insertedCount += blockRuleDao.insertAllForSource(entities, "useradd", sourceEnabled = true)
                    domainItems.forEach { blockListManager.syncCachedPattern(it.pattern) }
                }

                urlItems.forEach { item ->
                    if (goUrlRuleManager.addRule(item.urlPattern)) {
                        insertedCount++
                    }
                }

                RuntimeDnsSettingsRefresher.refreshRuleIndexesIfRunning(
                    context,
                    refreshBlock = true,
                    refreshAllow = false,
                    refreshRewrite = false,
                    dataset = dataset
                )
            }
            BatchRuleTarget.WHITELIST -> {
                val domainItems = validItems.filterIsInstance<BatchRuleItem.ValidDomain>()
                val urlItems = validItems.filterIsInstance<BatchRuleItem.ValidUrl>()

                if (domainItems.isNotEmpty()) {
                    val entities = domainItems.map { item ->
                        AllowRuleEntity(
                            pattern = item.pattern,
                            rawLine = item.rawLine,
                            addedAt = now,
                            enabled = true,
                            groupName = null,
                            appScope = item.appScope,
                            appInverted = false,
                            isWildcard = item.isWildcard,
                            denyallow = item.denyallow,
                            isRegex = item.isRegex,
                            dnsType = item.dnsType,
                            important = item.important
                        )
                    }
                    insertedCount += allowRuleDao.insertAllForSource(
                        entities, DefaultWhitelistSeeder.SOURCE_USER, sourceEnabled = true
                    )
                    domainItems.forEach { allowListManager.syncCachedPattern(it.pattern) }
                }

                urlItems.forEach { item ->
                    if (goUrlRuleManager.addRule(item.urlPattern)) {
                        insertedCount++
                    }
                }

                RuntimeDnsSettingsRefresher.refreshRuleIndexesIfRunning(
                    context,
                    refreshBlock = false,
                    refreshAllow = true,
                    refreshRewrite = false,
                    dataset = dataset
                )
            }
            BatchRuleTarget.REWRITE -> {
                val rewriteItems = validItems.filterIsInstance<BatchRuleItem.ValidRewrite>()
                if (rewriteItems.isNotEmpty()) {
                    val entities = rewriteItems.map { item ->
                        RewriteRuleEntity(
                            pattern = item.domain,
                            targetType = item.targetType,
                            targetValue = item.targetValue,
                            rawLine = item.rawLine,
                            addedAt = now,
                            enabled = true
                        )
                    }
                    insertedCount += rewriteRuleDao.insertAllForSource(entities, "useradd", enabled = true)
                    rewriteRuleManager.refreshCache(rebuildSubscriptionIndex = false)
                }

                RuntimeDnsSettingsRefresher.refreshRuleIndexesIfRunning(
                    context,
                    refreshBlock = false,
                    refreshAllow = false,
                    refreshRewrite = true,
                    dataset = dataset
                )
            }
        }

        insertedCount
    }
}
