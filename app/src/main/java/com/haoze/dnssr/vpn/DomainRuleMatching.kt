package com.haoze.dnssr.vpn

/**
 * Pure matching primitives shared by the allow/block rule caches (suffix
 * walking, wildcard walking, parent-domain suffix checks). All are stateless
 * pure functions intended for inlined use on the hot path.
 */

/**
 * Tries [domain] itself followed by all of its parent-domain suffixes and
 * returns the first non-null value produced by [match]. Semantically the same
 * as a per-label suffix walk via indexOf('.').
 */
internal inline fun <T> firstDomainSuffixHit(domain: String, match: (String) -> T?): T? {
    match(domain)?.let { return it }
    var pos = domain.indexOf('.')
    while (pos >= 0 && pos < domain.length - 1) {
        val suffix = domain.substring(pos + 1)
        match(suffix)?.let { return it }
        pos = domain.indexOf('.', pos + 1)
    }
    return null
}

/** Returns the first wildcard entry in list order that matches [domain]. */
internal inline fun <T> findWildcardHit(
    domain: String,
    wildcards: List<T>,
    patternOf: (T) -> AdGuardRuleParser.WildcardPattern
): T? {
    for (entry in wildcards) {
        if (patternOf(entry).matches(domain)) return entry
    }
    return null
}

/** Exact match or parent-domain suffix match. */
internal fun matchesDomainOrSuffix(domain: String, pattern: String): Boolean {
    if (domain == pattern) return true
    return domain.endsWith(".$pattern")
}
