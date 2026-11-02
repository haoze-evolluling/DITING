package com.haoze.diting.core.rule

import android.util.Log
import java.io.File

/**
 * Loads and classifies allow rules straight from the database, ported from the legacy
 * `AllowRuleCacheLoader` + `AllowRuleCache.exportSnapshot`. Important allow rules of subscriptions
 * live only in the important trie, so the exported fallback list drops them once that index exists.
 */
internal object AllowRuleLoader {
    private const val TAG = "AllowRuleLoader"

    fun load(
        dao: RuleSnapshotDao,
        indexDirectory: File?,
        triesFresh: Boolean,
    ): LoadedAllowRules {
        val custom = loadCustomRules(dao)

        val allowFile = indexDirectory?.let { RuleIndexLayout.allowIndex(it) }
        val importantFile = indexDirectory?.let { RuleIndexLayout.allowImportantIndex(it) }
        var compiledAny = false
        var compileFailure = false

        val allowOutcome = ensureIndex(allowFile, triesFresh) { consume ->
            dao.forEachSubscriptionRulePage(RuleSnapshotDao.RuleKind.ALLOW) { rule ->
                if (rule.isPlainPattern() && !rule.important) consume(rule)
            }
        }
        val importantOutcome = ensureIndex(importantFile, triesFresh) { consume ->
            dao.forEachSubscriptionRulePage(RuleSnapshotDao.RuleKind.ALLOW) { rule ->
                if (rule.isPlainPattern() && rule.important) consume(rule)
            }
        }
        for (outcome in listOf(allowOutcome, importantOutcome)) {
            if (outcome == IndexOutcome.COMPILED || outcome == IndexOutcome.FAILED) compiledAny = true
            if (outcome == IndexOutcome.FAILED) compileFailure = true
        }
        val mapped = allowOutcome.usable
        val importantMapped = importantOutcome.usable

        val subFallback = HashSet<String>()
        val importantSubFallback = HashSet<String>()
        val subWc = mutableListOf<String>()
        val importantSubWc = mutableListOf<String>()
        val subBucketsMap = HashMap<String, AllowAppBuckets>()
        val subInvertedList = mutableListOf<ExportedInvertedAllowRule>()
        val subSpecialRules = mutableListOf<ExportedSpecialRule>()

        fun processSubscriptionRule(entry: EnabledRule) {
            val isSpecial = entry.isRegex || !entry.denyallow.isNullOrEmpty() || !entry.dnsType.isNullOrEmpty()
            if (isSpecial) {
                subSpecialRules += entry.toSpecialRule()
                return
            }

            val isWc = entry.isWildcard || entry.pattern.contains('*')

            if (entry.appInverted && !entry.appScope.isNullOrEmpty()) {
                subInvertedList += ExportedInvertedAllowRule(entry.pattern, entry.excludedApps())
            } else if (!entry.appScope.isNullOrEmpty()) {
                for (pkg in entry.appScopePackages()) {
                    val bucket = subBucketsMap.getOrPut(pkg) { AllowAppBuckets() }
                    if (isWc) {
                        if (entry.important) bucket.importantWildcards += entry.pattern
                        else bucket.wildcards += entry.pattern
                    } else {
                        if (entry.important) bucket.importantExact += entry.pattern
                        else bucket.exact += entry.pattern
                    }
                }
            } else if (isWc) {
                if (entry.important) importantSubWc += entry.pattern
                else subWc += entry.pattern
            } else {
                if (entry.important) {
                    if (!importantMapped) importantSubFallback += entry.pattern
                } else {
                    if (!mapped) subFallback += entry.pattern
                }
            }
        }

        if (mapped && importantMapped) {
            dao.enabledSpecialSubscriptionRules(RuleSnapshotDao.RuleKind.ALLOW).forEach(::processSubscriptionRule)
        } else {
            dao.forEachSubscriptionRulePage(RuleSnapshotDao.RuleKind.ALLOW, action = ::processSubscriptionRule)
        }

        return LoadedAllowRules(
            customRules = custom.customRules,
            importantCustomRules = custom.importantCustomRules,
            customWildcards = custom.customWildcards,
            importantCustomWildcards = custom.importantCustomWildcards,
            customAppBuckets = custom.customAppBuckets,
            invertedCustomRules = custom.invertedCustomRules,
            subscriptionFallback = subFallback,
            importantSubscriptionFallback = importantSubFallback,
            subscriptionWildcards = subWc,
            importantSubscriptionWildcards = importantSubWc,
            subscriptionAppBuckets = subBucketsMap,
            invertedSubscriptionRules = subInvertedList,
            specialRules = custom.specialRules + subSpecialRules,
            allowIndexUsable = mapped,
            importantAllowIndexUsable = importantMapped,
            compiledAnyIndex = compiledAny,
            compileFailure = compileFailure,
        )
    }

    /** Exports exactly what `AllowRuleCache.exportSnapshot` produced. */
    fun export(loaded: LoadedAllowRules): ExportedAllowSnapshot {
        val globalAllow = LinkedHashSet<String>()

        globalAllow.addAll(loaded.customRules)
        globalAllow.addAll(loaded.customWildcards)
        globalAllow.addAll(loaded.importantCustomRules)
        globalAllow.addAll(loaded.importantCustomWildcards)
        globalAllow.addAll(loaded.subscriptionFallback)
        globalAllow.addAll(loaded.subscriptionWildcards)
        globalAllow.addAll(loaded.importantSubscriptionFallback)
        globalAllow.addAll(loaded.importantSubscriptionWildcards)

        val appRulesMap = LinkedHashMap<String, List<String>>()
        for (pkg in loaded.customAppBuckets.keys + loaded.subscriptionAppBuckets.keys) {
            val all = LinkedHashSet<String>()
            for (bucket in listOfNotNull(loaded.customAppBuckets[pkg], loaded.subscriptionAppBuckets[pkg])) {
                all.addAll(bucket.exact)
                all.addAll(bucket.importantExact)
                all.addAll(bucket.wildcards)
                all.addAll(bucket.importantWildcards)
            }
            if (all.isNotEmpty()) {
                appRulesMap[pkg] = all.toList()
            }
        }

        return ExportedAllowSnapshot(
            globalAllow = globalAllow.toList(),
            appRules = appRulesMap,
            invertedRules = loaded.invertedCustomRules + loaded.invertedSubscriptionRules,
            specialRules = loaded.specialRules,
        )
    }

    /** Loads (validating) an existing trie or compiles a fresh one; `FAILED` means the compile
     *  ran but produced nothing usable, so callers must not refresh the stamp. */
    private fun ensureIndex(file: File?, triesFresh: Boolean, compile: ((EnabledRule) -> Unit) -> Unit): IndexOutcome {
        if (file == null) return IndexOutcome.NOT_INDEXED
        if (triesFresh && file.exists() && file.length() > 0) {
            val loaded = runCatching { MappedSubscriptionRuleIndex.load(file) }
                .onFailure { Log.w(TAG, "Existing subscription allow index invalid, will recompile", it) }
                .getOrNull()
            if (loaded != null) {
                loaded.close()
                return IndexOutcome.LOADED
            }
        }
        val compiled = runCatching { MappedSubscriptionRuleIndex.compileAndLoad(file, compile) }
            .onFailure { e -> Log.e(TAG, "Failed to compile subscription allow index (${file.name})", e) }
            .getOrNull()
        compiled?.close()
        return if (compiled != null) IndexOutcome.COMPILED else IndexOutcome.FAILED
    }

    private data class CustomAllowRules(
        val customRules: Set<String>,
        val importantCustomRules: Set<String>,
        val customWildcards: List<String>,
        val importantCustomWildcards: List<String>,
        val customAppBuckets: Map<String, AllowAppBuckets>,
        val invertedCustomRules: List<ExportedInvertedAllowRule>,
        val specialRules: List<ExportedSpecialRule>,
    )

    private fun loadCustomRules(dao: RuleSnapshotDao): CustomAllowRules {
        val custom = HashSet<String>()
        val importantCustom = HashSet<String>()
        val customWc = mutableListOf<String>()
        val importantCustomWc = mutableListOf<String>()
        val customBucketsMap = HashMap<String, AllowAppBuckets>()
        val customInvertedList = mutableListOf<ExportedInvertedAllowRule>()
        val customSpecialRules = mutableListOf<ExportedSpecialRule>()

        for (entry in dao.enabledCustomRules(RuleSnapshotDao.RuleKind.ALLOW)) {
            val isSpecial = entry.isRegex || !entry.denyallow.isNullOrEmpty() || !entry.dnsType.isNullOrEmpty()
            if (isSpecial) {
                customSpecialRules += entry.toSpecialRule()
                continue
            }

            val isWc = entry.isWildcard || entry.pattern.contains('*')

            if (entry.appInverted && !entry.appScope.isNullOrEmpty()) {
                customInvertedList += ExportedInvertedAllowRule(entry.pattern, entry.excludedApps())
            } else if (!entry.appScope.isNullOrEmpty()) {
                for (pkg in entry.appScopePackages()) {
                    val bucket = customBucketsMap.getOrPut(pkg) { AllowAppBuckets() }
                    if (isWc) {
                        if (entry.important) bucket.importantWildcards += entry.pattern
                        else bucket.wildcards += entry.pattern
                    } else {
                        if (entry.important) bucket.importantExact += entry.pattern
                        else bucket.exact += entry.pattern
                    }
                }
            } else {
                if (isWc) {
                    if (entry.important) importantCustomWc += entry.pattern
                    else customWc += entry.pattern
                } else {
                    if (entry.important) importantCustom += entry.pattern
                    else custom += entry.pattern
                }
            }
        }

        return CustomAllowRules(
            customRules = custom,
            importantCustomRules = importantCustom,
            customWildcards = customWc,
            importantCustomWildcards = importantCustomWc,
            customAppBuckets = customBucketsMap,
            invertedCustomRules = customInvertedList,
            specialRules = customSpecialRules,
        )
    }

    private fun EnabledRule.isPlainPattern(): Boolean =
        !isWildcard && !pattern.contains('*') && appScope.isNullOrEmpty() && !appInverted &&
            !isRegex && denyallow.isNullOrEmpty() && dnsType.isNullOrEmpty()

    private fun EnabledRule.toSpecialRule() = ExportedSpecialRule(
        pattern = pattern,
        source = source,
        important = important,
        appScope = appScope,
        appInverted = appInverted,
        isWildcard = isWildcard || pattern.contains('*'),
        denyallow = denyallow,
        isRegex = isRegex,
        dnsType = dnsType,
    )

    private fun EnabledRule.excludedApps(): Set<String> =
        appScope.orEmpty().split('|').map { it.trim().lowercase() }.filter { it.isNotEmpty() }.toSet()

    private fun EnabledRule.appScopePackages(): List<String> =
        appScope.orEmpty().split('|').map { it.trim().lowercase() }.filter { it.isNotEmpty() }
}
