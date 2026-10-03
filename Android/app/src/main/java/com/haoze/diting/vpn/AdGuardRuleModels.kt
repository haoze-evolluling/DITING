package com.haoze.diting.vpn

import com.haoze.diting.data.entity.RewriteTargetType

/** Parsed domain block/allow rule. */
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

/** Parsed URL / path interception rule evaluated at HTTP(S) request level. */
data class ParsedUrlRule(
    val pattern: String,
    val rawLine: String,
    val isAllow: Boolean = false,
    val appScope: String? = null,
    val important: Boolean = false
)

/** Parsed element-hiding CSS cosmetic rule. */
data class ParsedCosmeticRule(
    val domain: String,
    val selector: String,
    val rawLine: String,
    val isException: Boolean = false
) {
    /** Generates standard CSS rule for cosmetic injection */
    fun toCss(): String = "$selector { display: none !important; }"
}

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
    val urlBlockRules: List<ParsedUrlRule> = emptyList(),
    val urlAllowRules: List<ParsedUrlRule> = emptyList(),
    val cosmeticRules: List<ParsedCosmeticRule> = emptyList(),
    val duplicateCount: Int = 0,
    val invalidCount: Int = 0,
    val unsupportedCount: Int = 0,
    val ignoredCount: Int = 0,
    val badfilteredCount: Int = 0,
    val totalLines: Int = 0
) {
    val size: Int
        get() = blockRules.size + allowRules.size + rewriteRules.size +
            urlBlockRules.size + urlAllowRules.size + cosmeticRules.size

    val skippedCount: Int get() = invalidCount + unsupportedCount

    fun isEmpty(): Boolean =
        blockRules.isEmpty() && allowRules.isEmpty() && rewriteRules.isEmpty() &&
            urlBlockRules.isEmpty() && urlAllowRules.isEmpty() && cosmeticRules.isEmpty()
}

data class CategorizedLine(
    val blockRules: List<ParsedRule> = emptyList(),
    val allowRules: List<ParsedRule> = emptyList(),
    val rewriteRules: List<RewriteRule> = emptyList(),
    val urlBlockRules: List<ParsedUrlRule> = emptyList(),
    val urlAllowRules: List<ParsedUrlRule> = emptyList(),
    val cosmeticRules: List<ParsedCosmeticRule> = emptyList(),
    val badfilterKeys: Set<String> = emptySet(),
    val invalidCount: Int = 0,
    val unsupportedCount: Int = 0,
    val ignoredCount: Int = 0
)
