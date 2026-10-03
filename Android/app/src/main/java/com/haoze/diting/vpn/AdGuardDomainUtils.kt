package com.haoze.diting.vpn

import android.net.InetAddresses
import android.os.Build
import java.net.IDN
import java.net.InetAddress

internal object AdGuardDomainUtils {

    val SINKHOLE_ADDRESSES = setOf("0", "0.0.0.0", "127.0.0.1", "::", "::1")
    private val DOMAIN_LABEL = Regex("^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$")
    val VALID_DNS_TYPES = setOf(
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

    fun isWebOnlyModifier(lower: String): Boolean {
        if (lower in WEB_ONLY_MODIFIER_TOKENS) return true
        return WEB_ONLY_MODIFIER_PREFIXES.any { lower.startsWith(it) }
    }

    fun looksLikeLiteralIp(value: String): Boolean {
        val trimmed = value.trim()
        if (trimmed.isEmpty() || trimmed.length > 45) return false
        if (trimmed == "0") return true
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            runCatching { InetAddresses.isNumericAddress(trimmed) }.getOrDefault(false)
        } else {
            if (trimmed.contains(':')) {
                trimmed.matches(Regex("^[0-9a-fA-F:]+$")) && trimmed.count { it == ':' } >= 2
            } else {
                trimmed.matches(Regex("^[0-9.]+$")) && trimmed.split('.').size == 4 &&
                    trimmed.split('.').all { it.toIntOrNull()?.let { o -> o in 0..255 } == true }
            }
        }
    }

    fun parseNumericAddressSafe(value: String): InetAddress? {
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

    fun normalizeDomain(value: String): String? {
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

        if (looksLikeLiteralIp(candidate)) {
            return parseNumericAddressSafe(candidate)?.hostAddress?.lowercase()
        }
        return normalizeDomain(candidate)
    }
}
