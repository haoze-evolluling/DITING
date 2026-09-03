package com.haoze.dnssr.vpn

import com.haoze.dnssr.data.entity.RewriteTargetType
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
        val isWildcard: Boolean = false
    )

    data class WildcardPattern(val pattern: String) {
        val isAll: Boolean = pattern == "*"
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
        val invalidCount: Int = 0,
        val unsupportedCount: Int = 0,
        val ignoredCount: Int = 0
    )

    private val SINKHOLE_ADDRESSES = setOf("0", "0.0.0.0", "127.0.0.1", "::", "::1")
    private val DOMAIN_LABEL = Regex("^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$")

    fun parseLine(line: String): ParsedRule? = parseSingle(line, allowRule = false)

    /** Manual allow entry accepts either an exception rule or a plain domain. */
    fun parseAllowLine(line: String): ParsedRule? = parseSingle(line, allowRule = true)

    fun parseAll(text: String): List<ParsedRule> = parseCategorized(text).blockRules

    fun parseAllowAll(text: String): List<ParsedRule> = text.lineSequence()
        .mapNotNull(::parseAllowLine)
        .distinctBy { "${it.pattern}:${it.important}:${it.appScope}:${it.appInverted}" }
        .toList()

    fun parseCategorized(text: String): CategorizedRules {
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
                val key = "${rule.pattern}:${rule.important}:${rule.appScope}:${rule.appInverted}"
                if (blockRules.putIfAbsent(key, rule) != null) duplicates++
            }
            for (rule in lineResult.allowRules) {
                val key = "${rule.pattern}:${rule.important}:${rule.appScope}:${rule.appInverted}"
                if (allowRules.putIfAbsent(key, rule) != null) duplicates++
            }
            for (rule in lineResult.rewriteRules) {
                val key = "${rule.pattern}:${rule.targetType}:${rule.targetValue}"
                if (rewriteRules.putIfAbsent(key, rule) != null) duplicates++
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
            val address = runCatching { InetAddress.getByName(target) }.getOrNull()
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

        val address = runCatching { InetAddress.getByName(fields.first()) }.getOrNull()
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
        if (value.startsWith("/")) {
            return CategorizedLine(unsupportedCount = 1)
        }

        var important = false
        var appScope: String? = null
        var appInverted = false
        var dnsrewriteTargetType: String? = null
        var dnsrewriteTargetValue: String? = null
        var dnsrewriteIsBlock = false

        val modifierIndex = value.indexOf('$')
        if (modifierIndex >= 0) {
            val modifiersStr = value.substring(modifierIndex + 1)
            value = value.substring(0, modifierIndex).trim()
            val modifiers = modifiersStr.split(',').map { it.trim() }.filter { it.isNotEmpty() }
            for (token in modifiers) {
                val lower = token.lowercase()
                when {
                    lower == "important" -> {
                        important = true
                    }
                    lower.startsWith("app=") -> {
                        val appValue = token.substring(4).trim()
                        if (appValue.isEmpty()) return CategorizedLine(unsupportedCount = 1)
                        val pkgs = appValue.split('|').map { it.trim() }.filter { it.isNotEmpty() }
                        if (pkgs.isEmpty()) return CategorizedLine(unsupportedCount = 1)
                        val hasInverted = pkgs.any { it.startsWith("~") }
                        val cleanPkgs = pkgs.map { it.removePrefix("~").trim().lowercase() }.filter { it.isNotEmpty() }
                        if (cleanPkgs.isEmpty()) return CategorizedLine(unsupportedCount = 1)
                        appInverted = hasInverted
                        appScope = cleanPkgs.joinToString("|")
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
                            val addr = runCatching { InetAddress.getByName(targetSpec) }.getOrNull()
                            if (addr != null) {
                                dnsrewriteTargetType = if (addr.address.size == 4) RewriteTargetType.IPV4 else RewriteTargetType.IPV6
                                dnsrewriteTargetValue = addr.hostAddress
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
                    else -> {
                        return CategorizedLine(unsupportedCount = 1)
                    }
                }
            }
        }

        value = when {
            value.startsWith("||") -> value.removePrefix("||").trimEnd('^')
            value.startsWith("|") || value.endsWith("|") -> return CategorizedLine(unsupportedCount = 1)
            else -> value.trimEnd('^')
        }

        val isWildcard = value.contains('*')
        val domain = if (isWildcard) {
            normalizeWildcardDomain(value)
        } else {
            normalizeDomain(value)
        } ?: return CategorizedLine(invalidCount = 1)

        if (dnsrewriteTargetType != null && dnsrewriteTargetValue != null) {
            val rule = RewriteRule(domain, dnsrewriteTargetType, dnsrewriteTargetValue, originalLine)
            return CategorizedLine(rewriteRules = listOf(rule))
        }

        if (dnsrewriteIsBlock) {
            val rule = ParsedRule(domain, originalLine, important, appScope, appInverted, isWildcard)
            return CategorizedLine(blockRules = listOf(rule))
        }

        val rule = ParsedRule(domain, originalLine, important, appScope, appInverted, isWildcard)
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

    private fun looksLikeLiteralIp(value: String): Boolean {
        if (value == "0") return true
        if (!value.contains(':') && !value.matches(Regex("^[0-9.]+$"))) return false
        return try {
            if (value.contains(':')) InetAddress.getByName(value).hostAddress != null
            else value.split('.').size == 4 && value.split('.').all { it.toIntOrNull()?.let { octet -> octet in 0..255 } == true }
        } catch (_: Exception) {
            false
        }
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
        // accidentally by block/allow list parsing.
        if (looksLikeLiteralIp(candidate)) {
            return runCatching { InetAddress.getByName(candidate).hostAddress?.lowercase() }.getOrNull()
        }
        return normalizeDomain(candidate)
    }

    fun parseHostsRewrite(text: String): List<RewriteRule> {
        val rules = LinkedHashMap<String, RewriteRule>()
        text.lineSequence().forEach { line -> parseHostsRewriteLine(line).forEach { rules.putIfAbsent(it.pattern, it) } }
        return rules.values.toList()
    }

    fun parseHostsRewriteLine(line: String): List<RewriteRule> {
        val fields = line.substringBefore('#').trim().split(Regex("\\s+")).filter { it.isNotEmpty() }
        if (fields.size < 2 || !looksLikeLiteralIp(fields.first())) return emptyList()
        val address = runCatching { InetAddress.getByName(fields.first()) }.getOrNull()
        if (address == null || fields.first().lowercase() in SINKHOLE_ADDRESSES) return emptyList()
        val targetType = if (address.address.size == 4) {
            com.haoze.dnssr.data.entity.RewriteTargetType.IPV4
        } else {
            com.haoze.dnssr.data.entity.RewriteTargetType.IPV6
        }
        val targetValue = address.hostAddress ?: return emptyList()
        return fields.drop(1).mapNotNull { host ->
            normalizeDomain(host)?.let { RewriteRule(it, targetType, targetValue, line) }
        }
    }
}
