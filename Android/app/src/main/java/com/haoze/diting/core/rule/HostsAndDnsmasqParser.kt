package com.haoze.diting.core.rule

import com.haoze.diting.data.entity.RewriteTargetType

internal object HostsAndDnsmasqParser {

    fun parseDnsmasqLine(line: String, originalLine: String): CategorizedLine {
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

        val isSinkhole = target.isEmpty() || target == "#" || target.lowercase() in AdGuardDomainUtils.SINKHOLE_ADDRESSES

        if (isSinkhole) {
            val blockList = mutableListOf<ParsedRule>()
            var invalidCount = 0
            for (d in domainParts) {
                val isWildcard = d.contains('*')
                val normalized = if (isWildcard) AdGuardDomainUtils.normalizeWildcardDomain(d) else AdGuardDomainUtils.normalizeDomain(d)
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

        if (AdGuardDomainUtils.looksLikeLiteralIp(target)) {
            val address = AdGuardDomainUtils.parseNumericAddressSafe(target)
            if (address != null) {
                val targetType = if (address.address.size == 4) RewriteTargetType.IPV4 else RewriteTargetType.IPV6
                val targetValue = address.hostAddress ?: return CategorizedLine(invalidCount = 1)
                val rewriteList = mutableListOf<RewriteRule>()
                var invalidCount = 0
                for (d in domainParts) {
                    val normalized = AdGuardDomainUtils.normalizeDomain(d)
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

        val targetDomain = AdGuardDomainUtils.normalizeDomain(target)
        if (targetDomain != null) {
            val rewriteList = mutableListOf<RewriteRule>()
            var invalidCount = 0
            for (d in domainParts) {
                val normalized = AdGuardDomainUtils.normalizeDomain(d)
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

    fun parseHostsLineDetailed(line: String, originalLine: String): CategorizedLine? {
        val content = line.substringBefore('#').trim()
        val fields = content.split(Regex("\\s+")).filter(String::isNotEmpty)
        if (fields.size < 2 || !AdGuardDomainUtils.looksLikeLiteralIp(fields.first())) return null

        val ipStr = fields.first().lowercase()
        val hosts = fields.drop(1)
        var invalidCount = 0

        if (ipStr in AdGuardDomainUtils.SINKHOLE_ADDRESSES) {
            val rules = mutableListOf<ParsedRule>()
            for (host in hosts) {
                val normalized = AdGuardDomainUtils.normalizeDomain(host)
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

        val address = AdGuardDomainUtils.parseNumericAddressSafe(fields.first())
            ?: return CategorizedLine(invalidCount = 1)
        val targetType = if (address.address.size == 4) RewriteTargetType.IPV4 else RewriteTargetType.IPV6
        val targetValue = address.hostAddress ?: return CategorizedLine(invalidCount = 1)

        val rewriteRules = mutableListOf<RewriteRule>()
        for (host in hosts) {
            val normalized = AdGuardDomainUtils.normalizeDomain(host)
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

    fun parseHostsRewriteLine(line: String): List<RewriteRule> {
        val fields = line.substringBefore('#').trim().split(Regex("\\s+")).filter { it.isNotEmpty() }
        if (fields.size < 2 || !AdGuardDomainUtils.looksLikeLiteralIp(fields.first())) return emptyList()
        val address = AdGuardDomainUtils.parseNumericAddressSafe(fields.first())
        if (address == null || fields.first().lowercase() in AdGuardDomainUtils.SINKHOLE_ADDRESSES) return emptyList()
        val targetType = if (address.address.size == 4) {
            RewriteTargetType.IPV4
        } else {
            RewriteTargetType.IPV6
        }
        val targetValue = address.hostAddress ?: return emptyList()
        return fields.drop(1).mapNotNull { host ->
            AdGuardDomainUtils.normalizeDomain(host)?.let { RewriteRule(it, targetType, targetValue, line) }
        }
    }
}
