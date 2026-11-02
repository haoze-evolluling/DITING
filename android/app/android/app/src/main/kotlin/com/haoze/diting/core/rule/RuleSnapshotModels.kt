package com.haoze.diting.core.rule

/**
 * Exported snapshot models, ported from the legacy `BlockRuleModels`/`AllowRuleModels` projected
 * shapes that `DomainPolicyEngine.buildRuleSnapshotJson` serialized for the Go engine.
 */
data class ExportedSpecialRule(
    val pattern: String,
    val source: String,
    val important: Boolean,
    val appScope: String?,
    val appInverted: Boolean,
    val isWildcard: Boolean,
    val denyallow: String?,
    val isRegex: Boolean,
    val dnsType: String?,
)

data class ExportedInvertedRule(
    val pattern: String,
    val source: String,
    val important: Boolean,
    val excludedApps: Set<String>,
)

data class ExportedInvertedAllowRule(
    val pattern: String,
    val excludedApps: Set<String>,
)

data class ExportedAppBlockRules(
    val block: List<String>,
    val important: List<String>,
)

data class ExportedBlockSnapshot(
    val globalBlock: List<String>,
    val globalImportant: List<String>,
    val appRules: Map<String, ExportedAppBlockRules>,
    val invertedRules: List<ExportedInvertedRule>,
    val disabledRules: List<String> = emptyList(),
    val specialRules: List<ExportedSpecialRule> = emptyList(),
)

data class ExportedAllowSnapshot(
    val globalAllow: List<String>,
    val appRules: Map<String, List<String>>,
    val invertedRules: List<ExportedInvertedAllowRule>,
    val specialRules: List<ExportedSpecialRule> = emptyList(),
)

/** Per-package bucket used while classifying rules; patterns only — matching lives in Go. */
internal class BlockAppBuckets {
    val exact = LinkedHashMap<String, String>()
    val importantExact = LinkedHashMap<String, String>()
    val wildcards = mutableListOf<String>()
    val importantWildcards = mutableListOf<String>()

    fun isEmpty() = exact.isEmpty() && importantExact.isEmpty() && wildcards.isEmpty() && importantWildcards.isEmpty()
}

internal class AllowAppBuckets {
    val exact = LinkedHashSet<String>()
    val importantExact = LinkedHashSet<String>()
    val wildcards = mutableListOf<String>()
    val importantWildcards = mutableListOf<String>()

    fun isEmpty() = exact.isEmpty() && importantExact.isEmpty() && wildcards.isEmpty() && importantWildcards.isEmpty()
}

/** Everything one full block-rule load learned, ported from `BlockRuleReloadResult`. */
internal class LoadedBlockRules(
    val customRules: Map<String, String>,
    val importantCustomRules: Map<String, String>,
    val customWildcards: List<String>,
    val importantCustomWildcards: List<String>,
    val customAppBuckets: Map<String, BlockAppBuckets>,
    val invertedCustomRules: List<ExportedInvertedRule>,
    val subscriptionFallback: Map<String, String>,
    val importantSubscriptionFallback: Map<String, String>,
    val subscriptionWildcards: List<String>,
    val importantSubscriptionWildcards: List<String>,
    val subscriptionAppBuckets: Map<String, BlockAppBuckets>,
    val invertedSubscriptionRules: List<ExportedInvertedRule>,
    val specialRules: List<ExportedSpecialRule>,
    /** True when the plain subscription index is on disk and parseable for the Go engine. */
    val blockIndexUsable: Boolean,
    val importantBlockIndexUsable: Boolean,
    /** True when this load wrote at least one trie file (the stamp must be refreshed). */
    val compiledAnyIndex: Boolean,
    /** True when a trie compile was attempted but failed; the stamp must stay untouched so the
     *  next start retries instead of trusting whatever trie file is left on disk. */
    val compileFailure: Boolean,
)

internal class LoadedAllowRules(
    val customRules: Set<String>,
    val importantCustomRules: Set<String>,
    val customWildcards: List<String>,
    val importantCustomWildcards: List<String>,
    val customAppBuckets: Map<String, AllowAppBuckets>,
    val invertedCustomRules: List<ExportedInvertedAllowRule>,
    val subscriptionFallback: Set<String>,
    val importantSubscriptionFallback: Set<String>,
    val subscriptionWildcards: List<String>,
    val importantSubscriptionWildcards: List<String>,
    val subscriptionAppBuckets: Map<String, AllowAppBuckets>,
    val invertedSubscriptionRules: List<ExportedInvertedAllowRule>,
    val specialRules: List<ExportedSpecialRule>,
    val allowIndexUsable: Boolean,
    val importantAllowIndexUsable: Boolean,
    val compiledAnyIndex: Boolean,
    val compileFailure: Boolean,
)

/** Outcome of loading/compiling one trie file; [usable] rows can be mmap'd by the Go engine. */
internal enum class IndexOutcome {
    NOT_INDEXED, LOADED, COMPILED, FAILED;

    val usable: Boolean get() = this == LOADED || this == COMPILED
}
