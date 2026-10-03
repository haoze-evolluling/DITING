package com.haoze.diting.vpn

/**
 * Allowlist rule with inverted app targeting (app exclusion list).
 */
data class InvertedAllowRule(
    val pattern: String,
    val important: Boolean,
    val excludedApps: Set<String>,
    val wildcard: AdGuardRuleParser.WildcardPattern? = null
)

/**
 * Per-app rule container separating exact match and wildcard match rules.
 */
data class AllowAppRuleBucket(
    val exactRules: Set<String> = emptySet(),
    val importantExactRules: Set<String> = emptySet(),
    val wildcardRules: List<AdGuardRuleParser.WildcardPattern> = emptyList(),
    val importantWildcardRules: List<AdGuardRuleParser.WildcardPattern> = emptyList()
) {
    fun isEmpty(): Boolean = exactRules.isEmpty() && importantExactRules.isEmpty() &&
        wildcardRules.isEmpty() && importantWildcardRules.isEmpty()
}

/**
 * Snapshot of all active allow rules exported for Go tunnel or serialization.
 */
data class ExportedAllowSnapshot(
    val globalAllow: List<String>,
    val appRules: Map<String, List<String>>,
    val invertedRules: List<ExportedInvertedAllowRule>,
    val specialRules: List<ExportedSpecialAllowRule> = emptyList()
)

data class ExportedInvertedAllowRule(
    val pattern: String,
    val excludedApps: Set<String>
)

data class ExportedSpecialAllowRule(
    val pattern: String,
    val important: Boolean = false,
    val appScope: String? = null,
    val appInverted: Boolean = false,
    val isWildcard: Boolean = false,
    val denyallow: String? = null,
    val isRegex: Boolean = false,
    val dnsType: String? = null
)

/**
 * Read-only view of the allow rule cache state used for matching.
 */
internal data class AllowRuleCacheState(
    val customRules: Set<String> = emptySet(),
    val importantCustomRules: Set<String> = emptySet(),
    val customWildcards: List<AdGuardRuleParser.WildcardPattern> = emptyList(),
    val importantCustomWildcards: List<AdGuardRuleParser.WildcardPattern> = emptyList(),
    val customAppBuckets: Map<String, AllowAppRuleBucket> = emptyMap(),
    val invertedCustomRules: List<InvertedAllowRule> = emptyList(),
    val subscriptionFallback: Set<String> = emptySet(),
    val importantSubscriptionFallback: Set<String> = emptySet(),
    val subscriptionWildcards: List<AdGuardRuleParser.WildcardPattern> = emptyList(),
    val importantSubscriptionWildcards: List<AdGuardRuleParser.WildcardPattern> = emptyList(),
    val subscriptionAppBuckets: Map<String, AllowAppRuleBucket> = emptyMap(),
    val invertedSubscriptionRules: List<InvertedAllowRule> = emptyList(),
    val subscriptionOverrides: Map<String, String?> = emptyMap(),
    val subscriptionIndex: MappedSubscriptionRuleIndex? = null,
    val importantSubscriptionIndex: MappedSubscriptionRuleIndex? = null,
    val specialRules: List<ExportedSpecialAllowRule> = emptyList()
)
