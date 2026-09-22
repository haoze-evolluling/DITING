package com.haoze.diting.vpn

import android.net.InetAddresses
import android.os.Build
import com.haoze.diting.data.entity.RewriteTargetType
import java.net.IDN
import java.net.InetAddress

/** Parses the DNS subset of AdGuard, hosts, and domains-only rule lists. */
object AdGuardRuleParser {

    data class ParsedRule(
        val pattern: String,
        val rawLine: String,
        val important: Boolean = false,
        val appScope: String? = null,
        val appInverted: Boolean = false,
        val isWildcard: Boolean = false,
        val denyallow: String? = null,
        val isRegex: Boolean = false,
        val dnsType: String? = null
    )

    data class WildcardPattern(val pattern: String) {
        val isAll: Boolean = pattern == "*"
        val baseDomain: String? = if (pattern.startsWith("*.") && pattern.length > 2) {
            pattern.substring(2).lowercase().trimEnd('.')
        } else null

        private val requiredLiterals: Array<String> = if (isAll) emptyArray() else {
            pattern.lowercase().split('*').filter { it.isNotEmpty() }.toTypedArray()
        }
        private val regex: Regex? = if (isAll) null else {
            val globRegex = buildString {
                append("^")
                for (c in pattern) {
                    if (c == '*') {
                        append(".*")
                    } else {
                        append(Regex.escape(c.toString()))
                    }
                }
                append("$")
            }
            Regex(globRegex, RegexOption.IGNORE_CASE)
        }

        fun matches(domainInput: String): Boolean {
            if (isAll) return true
            val domain = domainInput.trimEnd('.').lowercase()
            if (baseDomain != null && domain == baseDomain) return true
            for (literal in requiredLiterals) {
                if (!domain.contains(literal)) return false
            }
            val r = regex ?: return false
            if (r.matches(domain)) return true
            var dot = domain.indexOf('.')
            while (dot >= 0 && dot < domain.length - 1) {
                val suffix = domain.substring(dot + 1)
                if (r.matches(suffix)) return true
                dot = domain.indexOf('.', dot + 1)
            }
            return false
        }
    }

    data class CategorizedRules(
        val blockRules: List<ParsedRule> = emptyList(),
        val allowRules: List<ParsedRule> = emptyList(),
        val rewriteRules: List<RewriteRule> = emptyList(),
        val duplicateCount: Int = 0,
        val invalidCount: Int = 0,
        val unsupportedCount: Int = 0,
        val ignoredCount: Int = 0,
        val badfilteredCount: Int = 0,
        val totalLines: Int = 0
    ) {
        val size: Int get() = blockRules.size + allowRules.size + rewriteRules.size
        val skippedCount: Int get() = invalidCount + unsupportedCount
        fun isEmpty(): Boolean = blockRules.isEmpty() && allowRules.isEmpty() && rewriteRules.isEmpty()
    }

    data class CategorizedLine(
        val blockRules: List<ParsedRule> = emptyList(),
        val allowRules: List<ParsedRule> = emptyList(),
        val rewriteRules: List<RewriteRule> = emptyList(),
        val badfilterKeys: Set<String> = emptySet(),
        val invalidCount: Int = 0,
        val unsupportedCount: Int = 0,
        val ignoredCount: Int = 0
    )

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

    private val SINKHOLE_ADDRESSES = setOf("0", "0.0.0.0", "127.0.0.1", "::", "::1")
    private val DOMAIN_LABEL = Regex("^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$")
    private val VALID_DNS_TYPES = setOf(
        "A", "AAAA", "CNAME", "HTTPS", "SVCB", "TXT", "MX", "PTR", "SRV", "SOA", "NS", "ANY", "CAA", "DS", "DNSKEY"
    )

    private val WEB_ONLY_MODIFIER_PREFIXES = listOf(
        "domain=", "~domain=", "to=", "~to=",
        "method=", "~method=", "header=", "~header=", "redirect=", "redirect-rule=",
        "removeparam=", "removeheader=", "replace=", "urltransform=", "cookie=",
        "csp=", "permissions=", "jsonprune=", "xmlprune=", "referrerpolicy=", "reason="
    )

    private val WEB_ONLY_MODIFIER_TOKENS = setOf(
        "third-party", "~third-party", "strict-third-party", "strict-first-party",
        "match-case", "network", "document", "~document", "subdocument", "~subdocument",
        "script", "~script", "stylesheet", "~stylesheet", "image", "~image",
        "font", "~font", "media", "~media", "object", "~object",
        "xmlhttprequest", "~xmlhttprequest", "websocket", "~websocket",
        "ping", "~ping", "other", "~other", "popup", "~popup",
        "elemhide", "ehide", "generichide", "ghide", "specifichide", "shide",
        "genericblock", "urlblock", "content", "jsinject", "extension",
        "hls", "inline-script", "inline-font"
    )

    private fun isWebOnlyModifier(lower: String): Boolean {
        if (lower in WEB_ONLY_MODIFIER_TOKENS) return true
        return WEB_ONLY_MODIFIER_PREFIXES.any { lower.startsWith(it) }
    }

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
            (line.startsWith("[") && line.endsWith("]")) ||
            line.contains("##") || line.contains("#@#") || line.contains("#?#") || line.contains("#$#")
        ) {
            return CategorizedLine(ignoredCount = 1)
        }

        // 1. dnsmasq syntax: address=/domain/ip or address=/domain/ or server=/domain/ip
        if (line.startsWith("address=/") || line.startsWith("server=/")) {
            return parseDnsmasqLine(line, originalLine)
        }

        // 2. hosts syntax: IP domain1 [domain2 ...]
        val hosts = parseHostsLineDetailed(line, originalLine)
        if (hosts != null) {
            return hosts
        }

        // 3. AdGuard / ABP / plain domain
        val allow = line.startsWith("@@")
        return parseAdblockOrDomainLine(line, originalLine, allow)
    }

    private fun parseDnsmasqLine(line: String, originalLine: String): CategorizedLine {
        val content = if (line.contains(" #")) {
            line.substringBefore(" #")
        } else if (line.contains("\t#")) {
            line.substringBefore("\t#")
        } else {
            line
        }.trim()

        val withoutPrefix = if (content.startsWith("address=/")) {
            content.removePrefix("address=/")
        } else {
            content.removePrefix("server=/")
        }
        val parts = withoutPrefix.split('/')
        if (parts.size < 2) return CategorizedLine(invalidCount = 1)

        val target = parts.last().trim()
        val domainParts = parts.dropLast(1).map { it.trim() }.filter { it.isNotEmpty() }
        if (domainParts.isEmpty()) return CategorizedLine(invalidCount = 1)

        val isSinkhole = target.isEmpty() || target == "#" || target.lowercase() in SINKHOLE_ADDRESSES

        if (isSinkhole) {
            val blockList = mutableListOf<ParsedRule>()
            var invalidCount = 0
            for (d in domainParts) {
                val isWildcard = d.contains('*')
                val normalized = if (isWildcard) normalizeWildcardDomain(d) else normalizeDomain(d)
                if (normalized != null) {
                    blockList += ParsedRule(normalized, originalLine, isWildcard = isWildcard)
                } else {
                    invalidCount++
                }
            }
            return if (blockList.isEmpty() && invalidCount > 0) {
                CategorizedLine(invalidCount = invalidCount)
            } else {
                CategorizedLine(blockRules = blockList, invalidCount = invalidCount)
            }
        }

        if (looksLikeLiteralIp(target)) {
            val address = parseNumericAddressSafe(target)
            if (address != null) {
                val targetType = if (address.address.size == 4) RewriteTargetType.IPV4 else RewriteTargetType.IPV6
                val targetValue = address.hostAddress ?: return CategorizedLine(invalidCount = 1)
                val rewriteList = mutableListOf<RewriteRule>()
                var invalidCount = 0
                for (d in domainParts) {
                    val normalized = normalizeDomain(d)
                    if (normalized != null) {
                        rewriteList += RewriteRule(normalized, targetType, targetValue, originalLine)
                    } else {
                        invalidCount++
                    }
                }
                return if (rewriteList.isEmpty() && invalidCount > 0) {
                    CategorizedLine(invalidCount = invalidCount)
                } else {
                    CategorizedLine(rewriteRules = rewriteList, invalidCount = invalidCount)
                }
            }
        }

        val targetDomain = normalizeDomain(target)
        if (targetDomain != null) {
            val rewriteList = mutableListOf<RewriteRule>()
            var invalidCount = 0
            for (d in domainParts) {
                val normalized = normalizeDomain(d)
                if (normalized != null) {
                    rewriteList += RewriteRule(normalized, RewriteTargetType.CNAME, targetDomain, originalLine)
                } else {
                    invalidCount++
                }
            }
            return if (rewriteList.isEmpty() && invalidCount > 0) {
                CategorizedLine(invalidCount = invalidCount)
            } else {
                CategorizedLine(rewriteRules = rewriteList, invalidCount = invalidCount)
            }
        }

        return CategorizedLine(invalidCount = 1)
    }

    private fun parseHostsLineDetailed(line: String, originalLine: String): CategorizedLine? {
        val content = line.substringBefore('#').trim()
        val fields = content.split(Regex("\\s+")).filter(String::isNotEmpty)
        if (fields.size < 2 || !looksLikeLiteralIp(fields.first())) return null

        val ipStr = fields.first().lowercase()
        val hosts = fields.drop(1)
        var invalidCount = 0

        if (ipStr in SINKHOLE_ADDRESSES) {
            val rules = mutableListOf<ParsedRule>()
            for (host in hosts) {
                val normalized = normalizeDomain(host)
                if (normalized != null) {
                    rules += ParsedRule(normalized, originalLine)
                } else {
                    invalidCount++
                }
            }
            return if (rules.isEmpty() && invalidCount > 0) {
                CategorizedLine(invalidCount = invalidCount)
            } else {
                CategorizedLine(blockRules = rules, invalidCount = invalidCount)
            }
        }

        val address = parseNumericAddressSafe(fields.first())
            ?: return CategorizedLine(invalidCount = 1)
        val targetType = if (address.address.size == 4) RewriteTargetType.IPV4 else RewriteTargetType.IPV6
        val targetValue = address.hostAddress ?: return CategorizedLine(invalidCount = 1)

        val rewriteRules = mutableListOf<RewriteRule>()
        for (host in hosts) {
            val normalized = normalizeDomain(host)
            if (normalized != null) {
                rewriteRules += RewriteRule(normalized, targetType, targetValue, originalLine)
            } else {
                invalidCount++
            }
        }
        return if (rewriteRules.isEmpty() && invalidCount > 0) {
            CategorizedLine(invalidCount = invalidCount)
        } else {
            CategorizedLine(rewriteRules = rewriteRules, invalidCount = invalidCount)
        }
    }

    private fun parseAdblockOrDomainLine(line: String, originalLine: String, allow: Boolean): CategorizedLine {
        var value = line.substringBefore('#').trim()
        if (value.isEmpty()) return CategorizedLine(invalidCount = 1)
        if (allow) value = value.removePrefix("@@")

        var isRegex = false
        var regexPattern: String? = null
        var modifiersStr: String? = null

        if (value.startsWith("/")) {
            val lastSlash = value.lastIndexOf('/')
            if (lastSlash <= 0) return CategorizedLine(invalidCount = 1)
            val extractedRegex = value.substring(1, lastSlash).trim()
            if (extractedRegex.isEmpty()) return CategorizedLine(invalidCount = 1)
            try {
                Regex(extractedRegex)
            } catch (_: Exception) {
                return CategorizedLine(invalidCount = 1)
            }
            isRegex = true
            regexPattern = extractedRegex

            val tail = value.substring(lastSlash + 1).trim()
            if (tail.isNotEmpty()) {
                if (!tail.startsWith("$")) {
                    return CategorizedLine(invalidCount = 1)
                }
                modifiersStr = tail.substring(1)
            }
            value = ""
        } else {
            val modifierIndex = value.indexOf('$')
            if (modifierIndex >= 0) {
                modifiersStr = value.substring(modifierIndex + 1)
                value = value.substring(0, modifierIndex).trim()
            }
        }

        var important = false
        var appScope: String? = null
        var appInverted = false
        var dnsrewriteTargetType: String? = null
        var dnsrewriteTargetValue: String? = null
        var dnsrewriteIsBlock = false
        var isBadfilter = false
        var denyallow: String? = null
        var dnsType: String? = null

        if (!modifiersStr.isNullOrEmpty()) {
            val modifiers = modifiersStr.split(',').map { it.trim() }.filter { it.isNotEmpty() }
            for (token in modifiers) {
                val lower = token.lowercase()
                when {
                    lower == "important" -> {
                        important = true
                    }
                    lower.startsWith("app=") || lower.startsWith("~app=") -> {
                        val isNegativePrefix = lower.startsWith("~app=")
                        val appValue = if (isNegativePrefix) token.substring(5).trim() else token.substring(4).trim()
                        if (appValue.isEmpty()) return CategorizedLine(unsupportedCount = 1)
                        val pkgs = appValue.split('|').map { it.trim() }.filter { it.isNotEmpty() }
                        if (pkgs.isEmpty()) return CategorizedLine(unsupportedCount = 1)
                        val hasInverted = isNegativePrefix || pkgs.any { it.startsWith("~") }
                        val cleanPkgs = pkgs.map { it.removePrefix("~").trim().lowercase() }.filter { it.isNotEmpty() }
                        if (cleanPkgs.isEmpty()) return CategorizedLine(unsupportedCount = 1)
                        appInverted = hasInverted
                        appScope = cleanPkgs.joinToString("|")
                    }
                    lower.startsWith("denyallow=") || lower.startsWith("~denyallow=") -> {
                        val isNegative = lower.startsWith("~denyallow=")
                        val rawSpec = if (isNegative) token.substring(11).trim() else token.substring(10).trim()
                        if (rawSpec.isEmpty()) return CategorizedLine(invalidCount = 1)
                        val rawDomains = rawSpec.split('|').map { it.trim().lowercase() }.filter { it.isNotEmpty() }
                        if (rawDomains.isEmpty()) return CategorizedLine(invalidCount = 1)
                        val cleanDomains = mutableListOf<String>()
                        for (d in rawDomains) {
                            val clean = d.removePrefix("||").trimEnd('^').trimEnd('.')
                            val normalized = normalizeDomain(clean) ?: return CategorizedLine(invalidCount = 1)
                            cleanDomains += normalized
                        }
                        denyallow = cleanDomains.joinToString("|")
                    }
                    lower.startsWith("dnstype=") || lower.startsWith("~dnstype=") -> {
                        val isNegative = lower.startsWith("~dnstype=")
                        val rawSpec = if (isNegative) token.substring(9).trim() else token.substring(8).trim()
                        if (rawSpec.isEmpty()) return CategorizedLine(unsupportedCount = 1)
                        val rawTypes = rawSpec.split('|').map { it.trim().uppercase() }.filter { it.isNotEmpty() }
                        if (rawTypes.isEmpty()) return CategorizedLine(unsupportedCount = 1)
                        val cleanTypes = mutableListOf<String>()
                        for (t in rawTypes) {
                            val actual = t.removePrefix("~")
                            if (actual !in VALID_DNS_TYPES) {
                                return CategorizedLine(unsupportedCount = 1)
                            }
                            cleanTypes += actual
                        }
                        dnsType = if (isNegative || rawTypes.any { it.startsWith("~") }) {
                            "~" + cleanTypes.joinToString("|")
                        } else {
                            cleanTypes.joinToString("|")
                        }
                    }
                    lower.startsWith("dnsrewrite=") -> {
                        val rawSpec = token.substring(11).trim()
                        if (rawSpec.isEmpty()) return CategorizedLine(invalidCount = 1)
                        val targetSpec = if (rawSpec.contains(';')) {
                            val parts = rawSpec.split(';').map { it.trim() }.filter { it.isNotEmpty() }
                            if (parts.first().uppercase() in setOf("NXDOMAIN", "REFUSED", "SERVFAIL")) {
                                "NXDOMAIN"
                            } else {
                                parts.last()
                            }
                        } else {
                            rawSpec
                        }
                        val upper = targetSpec.uppercase()
                        val lowerTarget = targetSpec.lowercase()
                        if (upper in setOf("NXDOMAIN", "REFUSED", "SERVFAIL") || lowerTarget in SINKHOLE_ADDRESSES) {
                            dnsrewriteIsBlock = true
                        } else if (looksLikeLiteralIp(targetSpec)) {
                            val addr = parseNumericAddressSafe(targetSpec)
                            if (addr != null) {
                                dnsrewriteTargetType = if (addr.address.size == 4) RewriteTargetType.IPV4 else RewriteTargetType.IPV6
                                // IPv6 保留原始写法（如 2001:db8::1），hostAddress 会展开成完整形式
                                dnsrewriteTargetValue = if (addr.address.size == 4) addr.hostAddress else targetSpec.trim()
                            } else {
                                return CategorizedLine(invalidCount = 1)
                            }
                        } else {
                            val cname = normalizeDomain(targetSpec)
                            if (cname != null) {
                                dnsrewriteTargetType = RewriteTargetType.CNAME
                                dnsrewriteTargetValue = cname
                            } else {
                                return CategorizedLine(invalidCount = 1)
                            }
                        }
                    }
                    lower == "badfilter" -> {
                        isBadfilter = true
                    }
                    isWebOnlyModifier(lower) -> {
                        // Web/browser-specific modifiers cannot safely trigger whole-domain DNS blocking.
                        return CategorizedLine(ignoredCount = 1)
                    }
                    lower == "all" || lower == "empty" -> {
                        // $all matches all content types; at DNS level, equivalent to full domain match.
                    }
                    else -> {
                        return CategorizedLine(unsupportedCount = 1)
                    }
                }
            }
        }

        val domain: String
        val isWildcard: Boolean
        if (isRegex) {
            domain = regexPattern!!
            isWildcard = false
        } else {
            value = when {
                value.startsWith("||") -> value.removePrefix("||").trimEnd('^')
                value.startsWith("|") || value.endsWith("|") -> return CategorizedLine(unsupportedCount = 1)
                else -> value.trimEnd('^')
            }

            isWildcard = value.contains('*')
            domain = (if (isWildcard) {
                normalizeWildcardDomain(value)
            } else {
                normalizeDomain(value)
            }) ?: return CategorizedLine(invalidCount = 1)
        }

        if (isBadfilter) {
            val key = when {
                dnsrewriteTargetType != null && dnsrewriteTargetValue != null ->
                    rewriteRuleKey(domain, dnsrewriteTargetType, dnsrewriteTargetValue)
                dnsrewriteIsBlock || !allow ->
                    blockRuleKey(domain, important, appScope, appInverted, denyallow, isRegex, dnsType)
                else ->
                    allowRuleKey(domain, important, appScope, appInverted, denyallow, isRegex, dnsType)
            }
            return CategorizedLine(badfilterKeys = setOf(key))
        }

        if (dnsrewriteTargetType != null && dnsrewriteTargetValue != null) {
            val rule = RewriteRule(domain, dnsrewriteTargetType, dnsrewriteTargetValue, originalLine)
            return CategorizedLine(rewriteRules = listOf(rule))
        }

        val rule = ParsedRule(domain, originalLine, important, appScope, appInverted, isWildcard, denyallow, isRegex, dnsType)
        if (dnsrewriteIsBlock) {
            return CategorizedLine(blockRules = listOf(rule))
        }

        return if (allow) {
            CategorizedLine(allowRules = listOf(rule))
        } else {
            CategorizedLine(blockRules = listOf(rule))
        }
    }

    private fun parseSingle(line: String, allowRule: Boolean): ParsedRule? {
        val trimmed = line.trim().trimStart('\uFEFF')
        if (!allowRule && trimmed.startsWith("@@")) return null
        if (allowRule && !trimmed.startsWith("@@")) {
            val cat = parseAdblockOrDomainLine(trimmed, line, allow = true)
            return cat.allowRules.firstOrNull()
        }
        val cat = parseCategorizedLine(line)
        return if (allowRule) cat.allowRules.firstOrNull() else cat.blockRules.firstOrNull()
    }

    fun looksLikeLiteralIp(value: String): Boolean {
        val trimmed = value.trim()
        if (trimmed.isEmpty() || trimmed.length > 45) return false
        if (trimmed == "0") return true
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            runCatching { InetAddresses.isNumericAddress(trimmed) }.getOrDefault(false)
        } else {
            if (trimmed.contains(':')) {
                // 含 ':' 的字符串 InetAddress.getByName 不会发起 DNS 查询，可安全当作 IPv6 字面量解析
                trimmed.matches(Regex("^[0-9a-fA-F:]+$")) && trimmed.count { it == ':' } >= 2
            } else {
                trimmed.matches(Regex("^[0-9.]+$")) && trimmed.split('.').size == 4 &&
                        trimmed.split('.').all { it.toIntOrNull()?.let { o -> o in 0..255 } == true }
            }
        }
    }

    private fun parseNumericAddressSafe(value: String): InetAddress? {
        val trimmed = value.trim()
        if (trimmed.isEmpty() || trimmed.length > 45) return null
        return runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                if (InetAddresses.isNumericAddress(trimmed)) {
                    InetAddresses.parseNumericAddress(trimmed)
                } else null
            } else {
                if (looksLikeLiteralIp(trimmed)) InetAddress.getByName(trimmed) else null
            }
        }.getOrNull()
    }

    private fun normalizeDomain(value: String): String? {
        val candidate = value.trim().trimEnd('.')
        if (candidate.isEmpty() || candidate.contains('/') || candidate.contains(':') || candidate.contains(' ')) {
            return null
        }
        val ascii = try {
            IDN.toASCII(candidate, IDN.USE_STD3_ASCII_RULES).lowercase()
        } catch (_: IllegalArgumentException) {
            return null
        }
        if (ascii.length > 253 || !ascii.contains('.') || looksLikeLiteralIp(ascii)) return null
        val labels = ascii.split('.')
        if (labels.any { it.length !in 1..63 || !DOMAIN_LABEL.matches(it) }) return null
        return ascii
    }

    fun normalizeWildcardDomain(value: String): String? {
        val candidate = value.trim().trimEnd('.')
        if (candidate.isEmpty() || candidate.contains('/') || candidate.contains(':') || candidate.contains(' ')) {
            return null
        }
        if (candidate == "*") return "*"
        val lower = candidate.lowercase()
        if (lower.length > 253) return null
        val labels = lower.split('.')
        for (label in labels) {
            if (label.isEmpty() || label.length > 63) return null
            if (!label.all { it in 'a'..'z' || it in '0'..'9' || it == '-' || it == '*' || it == '_' }) {
                return null
            }
        }
        return lower
    }

    fun normalizeDomainForRewrite(value: String): String? {
        val candidate = value.trim().trimEnd('.')
        if (candidate.isEmpty()) return null

        // Rewrite sources may be literal IPv4/IPv6 addresses as well as host names.
        // Keep the broader domain-rule validator unchanged so IPs are not accepted
        // accidentally by block/allowlist parsing.
        if (looksLikeLiteralIp(candidate)) {
            return parseNumericAddressSafe(candidate)?.hostAddress?.lowercase()
        }
        return normalizeDomain(candidate)
    }

    fun parseHostsRewriteLine(line: String): List<RewriteRule> {
        val fields = line.substringBefore('#').trim().split(Regex("\\s+")).filter { it.isNotEmpty() }
        if (fields.size < 2 || !looksLikeLiteralIp(fields.first())) return emptyList()
        val address = parseNumericAddressSafe(fields.first())
        if (address == null || fields.first().lowercase() in SINKHOLE_ADDRESSES) return emptyList()
        val targetType = if (address.address.size == 4) {
            com.haoze.diting.data.entity.RewriteTargetType.IPV4
        } else {
            com.haoze.diting.data.entity.RewriteTargetType.IPV6
        }
        val targetValue = address.hostAddress ?: return emptyList()
        return fields.drop(1).mapNotNull { host ->
            normalizeDomain(host)?.let { RewriteRule(it, targetType, targetValue, line) }
        }
    }
}
