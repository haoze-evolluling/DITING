package com.haoze.diting.vpn

/**
 * Result of matching a domain against block rules.
 */
data class BlockRuleMatch(
    val pattern: String,
    val source: String
)

/**
 * Block rule with inverted app targeting (app exclusion list).
 */
data class InvertedBlockRule(
    val pattern: String,
    val source: String,
    val important: Boolean,
    val excludedApps: Set<String>,
    val wildcard: AdGuardRuleParser.WildcardPattern? = null
)

/**
 * Per-app rule container separating exact match and wildcard match rules.
 */
data class BlockAppRuleBucket(
    val exactRules: Map<String, String> = emptyMap(),
    val importantExactRules: Map<String, String> = emptyMap(),
    val wildcardRules: List<Pair<AdGuardRuleParser.WildcardPattern, String>> = emptyList(),
    val importantWildcardRules: List<Pair<AdGuardRuleParser.WildcardPattern, String>> = emptyList()
) {
    fun isEmpty(): Boolean = exactRules.isEmpty() && importantExactRules.isEmpty() &&
        wildcardRules.isEmpty() && importantWildcardRules.isEmpty()
}

/**
 * Snapshot of all active block rules exported for Go tunnel or serialization.
 */
data class ExportedBlockSnapshot(
    val globalBlock: List<String>,
    val globalImportant: List<String>,
    val appRules: Map<String, ExportedAppBlockRules>,
    val invertedRules: List<ExportedInvertedRule>,
    val disabledRules: List<String> = emptyList(),
    val specialRules: List<ExportedSpecialBlockRule> = emptyList()
)

data class ExportedAppBlockRules(
    val block: List<String>,
    val important: List<String>
)

data class ExportedInvertedRule(
    val pattern: String,
    val source: String,
    val important: Boolean,
    val excludedApps: Set<String>
)

data class ExportedSpecialBlockRule(
    val pattern: String,
    val source: String,
    val important: Boolean,
    val appScope: String? = null,
    val appInverted: Boolean = false,
    val isWildcard: Boolean = false,
    val denyallow: String? = null,
    val isRegex: Boolean = false,
    val dnsType: String? = null
)

/**
 * Read-only view of the block rule cache state used for matching.
 */
internal data class BlockRuleCacheState(
    val customRules: Map<String, String> = emptyMap(),
    val importantCustomRules: Map<String, String> = emptyMap(),
    val customWildcards: List<Pair<AdGuardRuleParser.WildcardPattern, String>> = emptyList(),
    val importantCustomWildcards: List<Pair<AdGuardRuleParser.WildcardPattern, String>> = emptyList(),
    val customAppBuckets: Map<String, BlockAppRuleBucket> = emptyMap(),
    val invertedCustomRules: List<InvertedBlockRule> = emptyList(),
    val subscriptionFallback: Map<String, String> = emptyMap(),
    val importantSubscriptionFallback: Map<String, String> = emptyMap(),
    val subscriptionWildcards: List<Pair<AdGuardRuleParser.WildcardPattern, String>> = emptyList(),
    val importantSubscriptionWildcards: List<Pair<AdGuardRuleParser.WildcardPattern, String>> = emptyList(),
    val subscriptionAppBuckets: Map<String, BlockAppRuleBucket> = emptyMap(),
    val invertedSubscriptionRules: List<InvertedBlockRule> = emptyList(),
    val subscriptionOverrides: Map<String, String?> = emptyMap(),
    val subscriptionIndex: MappedSubscriptionRuleIndex? = null,
    val importantSubscriptionIndex: MappedSubscriptionRuleIndex? = null,
    val specialRules: List<ExportedSpecialBlockRule> = emptyList()
)
