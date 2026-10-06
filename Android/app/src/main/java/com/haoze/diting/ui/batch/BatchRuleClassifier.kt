package com.haoze.diting.ui.batch

import com.haoze.diting.data.RuleDataset
import com.haoze.diting.data.entity.RewriteTargetType
import com.haoze.diting.core.rule.AdGuardDomainUtils
import com.haoze.diting.core.rule.AdGuardRuleParser
import com.haoze.diting.core.rule.HostsAndDnsmasqParser

internal sealed class ClassifiedLine {
    object Ignored : ClassifiedLine()

    data class Invalid(val reason: String) : ClassifiedLine()

    data class Domain(
        val pattern: String,
        val isAllow: Boolean,
        val rawLine: String,
        val appScope: String? = null,
        val important: Boolean = false,
        val isWildcard: Boolean = false,
        val denyallow: String? = null,
        val isRegex: Boolean = false,
        val dnsType: String? = null
    ) : ClassifiedLine()

    data class Url(
        val urlPattern: String,
        val isAllow: Boolean,
        val rawLine: String
    ) : ClassifiedLine()

    data class Cosmetic(
        val domain: String,
        val selector: String,
        val isException: Boolean,
        val rawLine: String
    ) : ClassifiedLine()

    data class Rewrite(
        val domain: String,
        val targetType: String,
        val targetValue: String,
        val rawLine: String
    ) : ClassifiedLine()
}

internal object BatchRuleClassifier {

    fun classify(
        raw: String,
        mode: BatchRecognitionMode,
        dataset: RuleDataset
    ): List<ClassifiedLine> {
        val trimmed = raw.trim().trimStart('\uFEFF')
        if (trimmed.isEmpty() || trimmed.startsWith("#") || trimmed.startsWith("!") ||
            (trimmed.startsWith("[") && trimmed.endsWith("]"))
        ) {
            return listOf(ClassifiedLine.Ignored)
        }

        // 1. Cosmetic rules (##, #@#, #?#, #$#)
        if (trimmed.contains("##") || trimmed.contains("#@#") ||
            trimmed.contains("#?#") || trimmed.contains("#$#")
        ) {
            if (dataset == RuleDataset.DNS_MODE) {
                return listOf(ClassifiedLine.Invalid("元素隐藏规则仅普通模式支持"))
            }
            val cat = AdGuardRuleParser.parseCategorizedLine(trimmed)
            if (cat.cosmeticRules.isNotEmpty()) {
                return cat.cosmeticRules.map {
                    ClassifiedLine.Cosmetic(
                        domain = it.domain,
                        selector = it.selector,
                        isException = it.isException,
                        rawLine = raw
                    )
                }
            }
            return listOf(ClassifiedLine.Invalid("元素隐藏规则格式无效"))
        }

        // 2. Explicit URL rules (http://, https://, @@http://, @@https://)
        val isExplicitUrlAllow = trimmed.startsWith("@@http://", ignoreCase = true) ||
                trimmed.startsWith("@@https://", ignoreCase = true)
        val isExplicitUrlBlock = trimmed.startsWith("http://", ignoreCase = true) ||
                trimmed.startsWith("https://", ignoreCase = true)

        if (isExplicitUrlAllow || isExplicitUrlBlock) {
            if (dataset == RuleDataset.DNS_MODE) {
                return listOf(ClassifiedLine.Invalid("URL 规则仅普通模式支持"))
            }
            val cleaned = if (isExplicitUrlAllow) trimmed.removePrefix("@@").trim() else trimmed
            if (!BatchRewriteParser.isValidUrl(cleaned)) {
                return listOf(ClassifiedLine.Invalid("URL 格式无效"))
            }
            val isAllow = isExplicitUrlAllow || (mode == BatchRecognitionMode.WHITELIST_FIRST)
            return listOf(ClassifiedLine.Url(urlPattern = cleaned, isAllow = isAllow, rawLine = raw))
        }

        // 2b. AdGuard / ABP URL and path interception rules (e.g. ||domain.com/path^, ||*/api/ad^)
        val catAdblock = AdGuardRuleParser.parseCategorizedLine(trimmed)
        if (catAdblock.urlBlockRules.isNotEmpty()) {
            if (dataset == RuleDataset.DNS_MODE) {
                return listOf(ClassifiedLine.Invalid("URL 规则仅普通模式支持"))
            }
            val isAllow = mode == BatchRecognitionMode.WHITELIST_FIRST && !trimmed.startsWith("||")
            return catAdblock.urlBlockRules.map {
                ClassifiedLine.Url(urlPattern = it.pattern, isAllow = isAllow, rawLine = raw)
            }
        }
        if (catAdblock.urlAllowRules.isNotEmpty()) {
            if (dataset == RuleDataset.DNS_MODE) {
                return listOf(ClassifiedLine.Invalid("URL 规则仅普通模式支持"))
            }
            return catAdblock.urlAllowRules.map {
                ClassifiedLine.Url(urlPattern = it.pattern, isAllow = true, rawLine = raw)
            }
        }


        // 3. AdGuard dnsrewrite syntax ($dnsrewrite=)
        if (trimmed.contains("\$dnsrewrite=")) {
            val cat = AdGuardRuleParser.parseCategorizedLine(trimmed)
            if (cat.rewriteRules.isNotEmpty()) {
                val r = cat.rewriteRules.first()
                return listOf(
                    ClassifiedLine.Rewrite(
                        domain = r.pattern,
                        targetType = r.targetType,
                        targetValue = r.targetValue,
                        rawLine = raw
                    )
                )
            }
            if (cat.blockRules.isNotEmpty()) {
                val b = cat.blockRules.first()
                return listOf(
                    ClassifiedLine.Domain(
                        pattern = b.pattern,
                        isAllow = false,
                        rawLine = raw,
                        appScope = b.appScope,
                        important = b.important,
                        isWildcard = b.isWildcard,
                        denyallow = b.denyallow,
                        isRegex = b.isRegex,
                        dnsType = b.dnsType
                    )
                )
            }
        }

        // 4. dnsmasq format (address=/domain/target or server=/domain/target)
        if (trimmed.startsWith("address=/") || trimmed.startsWith("server=/")) {
            val dnsmasq = HostsAndDnsmasqParser.parseDnsmasqLine(trimmed, raw)
            if (dnsmasq.blockRules.isNotEmpty()) {
                return dnsmasq.blockRules.map {
                    ClassifiedLine.Domain(
                        pattern = it.pattern,
                        isAllow = false,
                        rawLine = raw,
                        appScope = it.appScope,
                        important = it.important,
                        isWildcard = it.isWildcard,
                        denyallow = it.denyallow,
                        isRegex = it.isRegex,
                        dnsType = it.dnsType
                    )
                }
            }
            if (dnsmasq.rewriteRules.isNotEmpty()) {
                return dnsmasq.rewriteRules.map {
                    ClassifiedLine.Rewrite(
                        domain = it.pattern,
                        targetType = it.targetType,
                        targetValue = it.targetValue,
                        rawLine = raw
                    )
                }

            }
            if (dnsmasq.invalidCount > 0) {
                return listOf(ClassifiedLine.Invalid("dnsmasq 规则格式无效"))
            }
        }

        // 5. Explicit mapping arrows (->, =>, =)
        val hasArrow = trimmed.contains("->") || trimmed.contains("=>") || trimmed.contains("=")
        if (hasArrow && !trimmed.startsWith("@@") && !trimmed.startsWith("||")) {
            val rewritePairs = BatchRewriteParser.parseRewriteTokens(trimmed)
            if (rewritePairs.isNotEmpty()) {
                val results = mutableListOf<ClassifiedLine>()
                for ((rawDomain, rawTarget) in rewritePairs) {
                    val normalizedDomain = AdGuardRuleParser.normalizeDomainForRewrite(rawDomain)
                    if (normalizedDomain == null) {
                        results += ClassifiedLine.Invalid("域名格式无效: $rawDomain")
                        continue
                    }
                    val targetInfo = BatchRewriteParser.parseRewriteTarget(rawTarget)
                    if (targetInfo == null) {
                        results += ClassifiedLine.Invalid("目标地址格式无效 (须为 IPv4/IPv6 或 CNAME 域名): $rawTarget")
                        continue
                    }
                    results += ClassifiedLine.Rewrite(
                        domain = normalizedDomain,
                        targetType = targetInfo.first,
                        targetValue = targetInfo.second,
                        rawLine = "$normalizedDomain -> ${targetInfo.second}"
                    )
                }
                return results
            }
        }

        // 6. Multi-token lines: check for hosts IP mapping vs sinkhole blocking
        val contentNoComment = trimmed.substringBefore('#').trim()
        val tokens = contentNoComment.split(Regex("\\s+")).filter { it.isNotEmpty() }
        if (tokens.size >= 2) {
            val first = tokens[0]
            val second = tokens[1]

            // Case A: first is IP (standard hosts format: "1.2.3.4 example.com" or "0.0.0.0 example.com")
            if (BatchRewriteParser.isIpAddress(first)) {
                val isSinkhole = first.lowercase() in AdGuardDomainUtils.SINKHOLE_ADDRESSES
                val domains = tokens.drop(1)
                val results = mutableListOf<ClassifiedLine>()
                for (host in domains) {
                    val norm = AdGuardDomainUtils.normalizeDomain(host)
                    if (norm == null) {
                        results += ClassifiedLine.Invalid("域名格式无效: $host")
                        continue
                    }
                    if (isSinkhole) {
                        results += ClassifiedLine.Domain(
                            pattern = norm,
                            isAllow = false,
                            rawLine = "$first $norm"
                        )
                    } else {
                        val targetInfo = BatchRewriteParser.parseRewriteTarget(first)
                        if (targetInfo != null) {
                            results += ClassifiedLine.Rewrite(
                                domain = norm,
                                targetType = targetInfo.first,
                                targetValue = targetInfo.second,
                                rawLine = "$norm -> ${targetInfo.second}"
                            )
                        } else {
                            results += ClassifiedLine.Invalid("IP 地址格式无效: $first")
                        }
                    }
                }
                return results
            }

            // Case B: second is IP (reversed hosts format: "example.com 1.2.3.4" or "example.com 0.0.0.0")
            if (BatchRewriteParser.isIpAddress(second)) {
                val norm = AdGuardDomainUtils.normalizeDomain(first)
                if (norm == null) {
                    return listOf(ClassifiedLine.Invalid("域名格式无效: $first"))
                }
                val isSinkhole = second.lowercase() in AdGuardDomainUtils.SINKHOLE_ADDRESSES
                return if (isSinkhole) {
                    listOf(ClassifiedLine.Domain(pattern = norm, isAllow = false, rawLine = "$norm $second"))
                } else {
                    val targetInfo = BatchRewriteParser.parseRewriteTarget(second)
                    if (targetInfo != null) {
                        listOf(
                            ClassifiedLine.Rewrite(
                                domain = norm,
                                targetType = targetInfo.first,
                                targetValue = targetInfo.second,
                                rawLine = "$norm -> ${targetInfo.second}"
                            )
                        )
                    } else {
                        listOf(ClassifiedLine.Invalid("IP 地址格式无效: $second"))
                    }
                }
            }
        }

        // 7. Explicit whitelist prefix (@@)
        if (trimmed.startsWith("@@")) {
            val normalized = if (trimmed.startsWith("@@||")) trimmed else "@@||${trimmed.removePrefix("@@")}^"
            val parsed = AdGuardRuleParser.parseAllowLine(normalized)
                ?: AdGuardRuleParser.parseAllowLine(trimmed)

            if (parsed == null || parsed.pattern.isBlank()) {
                return listOf(ClassifiedLine.Invalid("白名单域名规则格式无效"))
            }

            return listOf(
                ClassifiedLine.Domain(
                    pattern = parsed.pattern,
                    isAllow = true,
                    rawLine = raw,
                    appScope = parsed.appScope,
                    important = parsed.important,
                    isWildcard = parsed.isWildcard,
                    denyallow = parsed.denyallow,
                    isRegex = parsed.isRegex,
                    dnsType = parsed.dnsType
                )
            )
        }

        // 8. Explicit blacklist prefix (||)
        if (trimmed.startsWith("||")) {
            val normalized = if (trimmed.endsWith("^")) trimmed else "$trimmed^"
            val parsed = AdGuardRuleParser.parseLine(normalized)
                ?: AdGuardRuleParser.parseLine(trimmed)

            if (parsed == null || parsed.pattern.isBlank()) {
                return listOf(ClassifiedLine.Invalid("黑名单域名规则格式无效"))
            }

            return listOf(
                ClassifiedLine.Domain(
                    pattern = parsed.pattern,
                    isAllow = false,
                    rawLine = raw,
                    appScope = parsed.appScope,
                    important = parsed.important,
                    isWildcard = parsed.isWildcard,
                    denyallow = parsed.denyallow,
                    isRegex = parsed.isRegex,
                    dnsType = parsed.dnsType
                )
            )
        }

        // 9. Plain domain, wildcard domain, or regex pattern (mode disambiguation)
        val isWhitelistMode = mode == BatchRecognitionMode.WHITELIST_FIRST

        if (isWhitelistMode) {
            val normalized = "@@||$trimmed^"
            val parsed = AdGuardRuleParser.parseAllowLine(normalized)
                ?: AdGuardRuleParser.parseAllowLine("@@$trimmed")

            if (parsed == null || parsed.pattern.isBlank()) {
                return listOf(ClassifiedLine.Invalid("域名规则格式无效"))
            }

            return listOf(
                ClassifiedLine.Domain(
                    pattern = parsed.pattern,
                    isAllow = true,
                    rawLine = raw,
                    appScope = parsed.appScope,
                    important = parsed.important,
                    isWildcard = parsed.isWildcard,
                    denyallow = parsed.denyallow,
                    isRegex = parsed.isRegex,
                    dnsType = parsed.dnsType
                )
            )
        } else {
            val normalized = "||$trimmed^"
            val parsed = AdGuardRuleParser.parseLine(normalized)
                ?: AdGuardRuleParser.parseLine(trimmed)

            if (parsed == null || parsed.pattern.isBlank()) {
                return listOf(ClassifiedLine.Invalid("域名规则格式无效"))
            }

            return listOf(
                ClassifiedLine.Domain(
                    pattern = parsed.pattern,
                    isAllow = false,
                    rawLine = raw,
                    appScope = parsed.appScope,
                    important = parsed.important,
                    isWildcard = parsed.isWildcard,
                    denyallow = parsed.denyallow,
                    isRegex = parsed.isRegex,
                    dnsType = parsed.dnsType
                )
            )
        }
    }
}
