package com.haoze.diting.ui.batch

import com.haoze.diting.data.entity.RewriteTargetType
import com.haoze.diting.core.rule.AdGuardRuleParser
import java.net.InetAddress

internal object BatchRewriteParser {
    fun parseRewriteTokens(raw: String): List<Pair<String, String>> {
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

    fun parseRewriteTarget(target: String): Pair<String, String>? {
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

    fun isIpAddress(token: String): Boolean {
        return AdGuardRuleParser.looksLikeLiteralIp(token)
    }

    fun isValidUrl(url: String): Boolean {
        val trimmed = url.trim()
        return (trimmed.startsWith("http://", ignoreCase = true) || trimmed.startsWith("https://", ignoreCase = true)) &&
                trimmed.length > 8 && !trimmed.contains(" ")
    }
}
