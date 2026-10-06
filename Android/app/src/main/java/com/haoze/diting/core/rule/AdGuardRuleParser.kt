package com.haoze.diting.core.rule

import com.haoze.diting.data.entity.RewriteTargetType

/**
 * Parses AdGuard, ABP, hosts, and domains-only rule lists.
 * Delegates line parsing to [AdblockRuleLineParser] and [HostsAndDnsmasqParser].
 */
object AdGuardRuleParser {

    typealias ParsedRule = com.haoze.diting.core.rule.ParsedRule
    typealias ParsedUrlRule = com.haoze.diting.core.rule.ParsedUrlRule
    typealias ParsedCosmeticRule = com.haoze.diting.core.rule.ParsedCosmeticRule
    typealias WildcardPattern = com.haoze.diting.core.rule.WildcardPattern
    typealias CategorizedRules = com.haoze.diting.core.rule.CategorizedRules
    typealias CategorizedLine = com.haoze.diting.core.rule.CategorizedLine

    fun blockRuleKey(
        pattern: String,
        important: Boolean,
        appScope: String?,
        appInverted: Boolean,
        denyallow: String? = null,
        isRegex: Boolean = false,
        dnsType: String? = null
    ): String {
        val base = "block:$pattern:$important:$appScope:$appInverted"
        return if (!denyallow.isNullOrEmpty() || isRegex || !dnsType.isNullOrEmpty()) {
            "$base:${denyallow.orEmpty()}:$isRegex:${dnsType.orEmpty()}"
        } else {
            base
        }
    }

    fun blockRuleKey(rule: ParsedRule): String =
        blockRuleKey(rule.pattern, rule.important, rule.appScope, rule.appInverted, rule.denyallow, rule.isRegex, rule.dnsType)

    fun allowRuleKey(
        pattern: String,
        important: Boolean,
        appScope: String?,
        appInverted: Boolean,
        denyallow: String? = null,
        isRegex: Boolean = false,
        dnsType: String? = null
    ): String {
        val base = "allow:$pattern:$important:$appScope:$appInverted"
        return if (!denyallow.isNullOrEmpty() || isRegex || !dnsType.isNullOrEmpty()) {
            "$base:${denyallow.orEmpty()}:$isRegex:${dnsType.orEmpty()}"
        } else {
            base
        }
    }

    fun allowRuleKey(rule: ParsedRule): String =
        allowRuleKey(rule.pattern, rule.important, rule.appScope, rule.appInverted, rule.denyallow, rule.isRegex, rule.dnsType)

    fun rewriteRuleKey(pattern: String, targetType: String, targetValue: String): String =
        "rewrite:$pattern:$targetType:$targetValue"

    fun rewriteRuleKey(rule: RewriteRule): String =
        rewriteRuleKey(rule.pattern, rule.targetType, rule.targetValue)

    fun parseLine(line: String): ParsedRule? = parseSingle(line, allowRule = false)

    /** Manual allow entry accepts either an exception rule or a plain domain. */
    fun parseAllowLine(line: String): ParsedRule? = parseSingle(line, allowRule = true)

    fun extractBadfilterKeys(lines: Sequence<String>): Set<String> {
        val keys = LinkedHashSet<String>()
        for (line in lines) {
            if (!line.contains("badfilter", ignoreCase = true)) continue
            val parsed = parseCategorizedLine(line)
            keys.addAll(parsed.badfilterKeys)
        }
        return keys
    }

    fun extractBadfilterKeys(text: String): Set<String> =
        extractBadfilterKeys(text.lineSequence())

    fun extractBadfilterKeys(reader: java.io.BufferedReader): Set<String> =
        extractBadfilterKeys(reader.lineSequence())

    fun parseCategorized(text: String): CategorizedRules {
        val badfilterKeys = extractBadfilterKeys(text)
        val blockRules = LinkedHashMap<String, ParsedRule>()
        val allowRules = LinkedHashMap<String, ParsedRule>()
        val rewriteRules = LinkedHashMap<String, RewriteRule>()
        val urlBlockRules = LinkedHashMap<String, ParsedUrlRule>()
        val urlAllowRules = LinkedHashMap<String, ParsedUrlRule>()
        val cosmeticRules = LinkedHashMap<String, ParsedCosmeticRule>()
        var duplicates = 0
        var invalid = 0
        var unsupported = 0
        var ignored = 0
        var total = 0

        text.lineSequence().forEach { originalLine ->
            total++
            val lineResult = parseCategorizedLine(originalLine)
            invalid += lineResult.invalidCount
            unsupported += lineResult.unsupportedCount
            ignored += lineResult.ignoredCount

            for (rule in lineResult.blockRules) {
                val key = blockRuleKey(rule)
                if (blockRules.putIfAbsent(key, rule) != null) duplicates++
            }
            for (rule in lineResult.allowRules) {
                val key = allowRuleKey(rule)
                if (allowRules.putIfAbsent(key, rule) != null) duplicates++
            }
            for (rule in lineResult.rewriteRules) {
                val key = rewriteRuleKey(rule)
                if (rewriteRules.putIfAbsent(key, rule) != null) duplicates++
            }
            for (rule in lineResult.urlBlockRules) {
                val key = "url_block:${rule.pattern}:${rule.appScope}"
                if (urlBlockRules.putIfAbsent(key, rule) != null) duplicates++
            }
            for (rule in lineResult.urlAllowRules) {
                val key = "url_allow:${rule.pattern}:${rule.appScope}"
                if (urlAllowRules.putIfAbsent(key, rule) != null) duplicates++
            }
            for (rule in lineResult.cosmeticRules) {
                val key = "cosmetic:${rule.domain}:${rule.selector}:${rule.isException}"
                if (cosmeticRules.putIfAbsent(key, rule) != null) duplicates++
            }
        }

        var badfilteredCount = 0
        if (badfilterKeys.isNotEmpty()) {
            val blockIter = blockRules.iterator()
            while (blockIter.hasNext()) {
                val entry = blockIter.next()
                if (entry.key in badfilterKeys) {
                    blockIter.remove()
                    badfilteredCount++
                }
            }
            val allowIter = allowRules.iterator()
            while (allowIter.hasNext()) {
                val entry = allowIter.next()
                if (entry.key in badfilterKeys) {
                    allowIter.remove()
                    badfilteredCount++
                }
            }
            val rewriteIter = rewriteRules.iterator()
            while (rewriteIter.hasNext()) {
                val entry = rewriteIter.next()
                if (entry.key in badfilterKeys) {
                    rewriteIter.remove()
                    badfilteredCount++
                }
            }
        }

        return CategorizedRules(
            blockRules = blockRules.values.toList(),
            allowRules = allowRules.values.toList(),
            rewriteRules = rewriteRules.values.toList(),
            urlBlockRules = urlBlockRules.values.toList(),
            urlAllowRules = urlAllowRules.values.toList(),
            cosmeticRules = cosmeticRules.values.toList(),
            duplicateCount = duplicates,
            invalidCount = invalid,
            unsupportedCount = unsupported,
            ignoredCount = ignored,
            badfilteredCount = badfilteredCount,
            totalLines = total
        )
    }

    /** Parses one line without retaining cross-line state for streaming imports. */
    fun parseCategorizedLine(originalLine: String): CategorizedLine {
        val line = originalLine.trim().trimStart('\uFEFF')
        if (line.isEmpty() || line.startsWith("!") || line.startsWith("#") ||
            (line.startsWith("[") && line.endsWith("]"))
        ) {
            return CategorizedLine(ignoredCount = 1)
        }

        // 1. dnsmasq syntax: address=/domain/ip or address=/domain/ or server=/domain/ip
        if (line.startsWith("address=/") || line.startsWith("server=/")) {
            return HostsAndDnsmasqParser.parseDnsmasqLine(line, originalLine)
        }

        // 2. hosts syntax: IP domain1 [domain2 ...]
        val hosts = HostsAndDnsmasqParser.parseHostsLineDetailed(line, originalLine)
        if (hosts != null) {
            return hosts
        }

        // 3. AdGuard / ABP / plain domain / cosmetic / url
        val allow = line.startsWith("@@")
        return AdblockRuleLineParser.parseAdblockOrDomainLine(line, originalLine, allow)
    }

    private fun parseSingle(line: String, allowRule: Boolean): ParsedRule? {
        val trimmed = line.trim().trimStart('\uFEFF')
        if (!allowRule && trimmed.startsWith("@@")) return null
        if (allowRule && !trimmed.startsWith("@@")) {
            val cat = AdblockRuleLineParser.parseAdblockOrDomainLine(trimmed, line, allow = true)
            return cat.allowRules.firstOrNull()
        }
        val cat = parseCategorizedLine(line)
        return if (allowRule) cat.allowRules.firstOrNull() else cat.blockRules.firstOrNull()
    }

    fun looksLikeLiteralIp(value: String): Boolean =
        AdGuardDomainUtils.looksLikeLiteralIp(value)

    fun normalizeWildcardDomain(value: String): String? =
        AdGuardDomainUtils.normalizeWildcardDomain(value)

    fun normalizeDomainForRewrite(value: String): String? =
        AdGuardDomainUtils.normalizeDomainForRewrite(value)

    fun parseHostsRewriteLine(line: String): List<RewriteRule> =
        HostsAndDnsmasqParser.parseHostsRewriteLine(line)
}
