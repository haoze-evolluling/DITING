package com.haoze.dnssr.vpn

/**
 * allow/block 两个规则缓存共享的纯匹配原语（后缀遍历、通配符遍历、父域后缀判定）。
 * 均为无状态纯函数，供热路径内联使用。
 */

/**
 * 依次尝试 [domain] 自身与其全部父域后缀，[match] 首次返回非空值时返回该值。
 * 与逐级 indexOf('.') 的后缀遍历语义一致。
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

/** 按列表顺序找到首个命中 [domain] 的通配符条目，返回该条目。 */
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

/** 精确匹配或父域后缀匹配。 */
internal fun matchesDomainOrSuffix(domain: String, pattern: String): Boolean {
    if (domain == pattern) return true
    return domain.endsWith(".$pattern")
}
