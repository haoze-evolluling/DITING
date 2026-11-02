package com.haoze.diting.core.rule

import android.util.Log
import java.io.File

/**
 * Loads and classifies block rules straight from the database, ported from the legacy
 * `BlockRuleCacheLoader` + `BlockRuleCache.exportSnapshot`. The mmap subscription index is only
 * validated here — the Go engine reads the trie file itself — so loaded handles close again.
 */
internal object BlockRuleLoader {
    private const val TAG = "BlockRuleLoader"

    fun load(
        dao: RuleSnapshotDao,
        indexDirectory: File?,
        triesFresh: Boolean,
    ): LoadedBlockRules {
        val custom = loadCustomRules(dao)

        val blockFile = indexDirectory?.let { RuleIndexLayout.blockIndex(it) }
        val importantFile = indexDirectory?.let { RuleIndexLayout.blockImportantIndex(it) }
        var compiledAny = false
        var compileFailure = false

        val blockOutcome = ensureIndex(blockFile, triesFresh) { consume ->
            dao.forEachSubscriptionRulePage(RuleSnapshotDao.RuleKind.BLOCK, important = false) { rule ->
                if (rule.isPlainPattern()) consume(rule)
            }
        }
        val importantOutcome = ensureIndex(importantFile, triesFresh) { consume ->
            dao.forEachSubscriptionRulePage(RuleSnapshotDao.RuleKind.BLOCK, important = true) { rule ->
                if (rule.isPlainPattern()) consume(rule)
            }
        }
        for (outcome in listOf(blockOutcome, importantOutcome)) {
            if (outcome == IndexOutcome.COMPILED || outcome == IndexOutcome.FAILED) compiledAny = true
            if (outcome == IndexOutcome.FAILED) compileFailure = true
        }
        val mapped = blockOutcome.usable
        val importantMapped = importantOutcome.usable

        val subFallback = HashMap<String, String>()
        val importantSubFallback = HashMap<String, String>()
        val subWc = mutableListOf<String>()
        val importantSubWc = mutableListOf<String>()
        val subBucketsMap = HashMap<String, BlockAppBuckets>()
        val subInvertedList = mutableListOf<ExportedInvertedRule>()
        val subSpecialRules = mutableListOf<ExportedSpecialRule>()

        fun processSubscriptionRule(entry: EnabledRule) {
            val isSpecial = entry.isRegex || !entry.denyallow.isNullOrEmpty() || !entry.dnsType.isNullOrEmpty()
            if (isSpecial) {
                subSpecialRules += entry.toSpecialRule()
                return
            }

            val isWc = entry.isWildcard || entry.pattern.contains('*')

            if (entry.appInverted && !entry.appScope.isNullOrEmpty()) {
                subInvertedList += ExportedInvertedRule(
                    entry.pattern, entry.source, entry.important, entry.excludedApps(),
                )
            } else if (!entry.appScope.isNullOrEmpty()) {
                for (pkg in entry.appScopePackages()) {
                    val bucket = subBucketsMap.getOrPut(pkg) { BlockAppBuckets() }
                    if (isWc) {
                        if (entry.important) bucket.importantWildcards += entry.pattern
                        else bucket.wildcards += entry.pattern
                    } else {
                        if (entry.important) bucket.importantExact[entry.pattern] = entry.source
                        else bucket.exact[entry.pattern] = entry.source
                    }
                }
            } else if (isWc) {
                if (entry.important) importantSubWc += entry.pattern
                else subWc += entry.pattern
            } else {
                if (entry.important) {
                    if (!importantMapped) importantSubFallback[entry.pattern] = entry.source
                } else {
                    if (!mapped) subFallback[entry.pattern] = entry.source
                }
            }
        }

        if (mapped && importantMapped) {
            dao.enabledSpecialSubscriptionRules(RuleSnapshotDao.RuleKind.BLOCK).forEach(::processSubscriptionRule)
        } else {
            dao.forEachSubscriptionRulePage(RuleSnapshotDao.RuleKind.BLOCK, important = false, ::processSubscriptionRule)
            dao.forEachSubscriptionRulePage(RuleSnapshotDao.RuleKind.BLOCK, important = true, ::processSubscriptionRule)
        }

        return LoadedBlockRules(
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
            blockIndexUsable = mapped,
            importantBlockIndexUsable = importantMapped,
            compiledAnyIndex = compiledAny,
            compileFailure = compileFailure,
        )
    }

    /** Exports exactly what `BlockRuleCache.exportSnapshot` produced. */
    fun export(loaded: LoadedBlockRules): ExportedBlockSnapshot {
        val globalBlock = LinkedHashSet<String>()
        val globalImportant = LinkedHashSet<String>()

        globalBlock.addAll(loaded.customRules.keys)
        globalBlock.addAll(loaded.customWildcards)
        globalBlock.addAll(loaded.subscriptionFallback.keys)
        globalBlock.addAll(loaded.subscriptionWildcards)

        globalImportant.addAll(loaded.importantCustomRules.keys)
        globalImportant.addAll(loaded.importantCustomWildcards)
        globalImportant.addAll(loaded.importantSubscriptionFallback.keys)
        globalImportant.addAll(loaded.importantSubscriptionWildcards)

        val appRulesMap = LinkedHashMap<String, ExportedAppBlockRules>()
        for (pkg in loaded.customAppBuckets.keys + loaded.subscriptionAppBuckets.keys) {
            val blk = LinkedHashSet<String>()
            val imp = LinkedHashSet<String>()
            for (bucket in listOfNotNull(loaded.customAppBuckets[pkg], loaded.subscriptionAppBuckets[pkg])) {
                blk.addAll(bucket.exact.keys)
                blk.addAll(bucket.wildcards)
                imp.addAll(bucket.importantExact.keys)
                imp.addAll(bucket.importantWildcards)
            }
            if (blk.isNotEmpty() || imp.isNotEmpty()) {
                appRulesMap[pkg] = ExportedAppBlockRules(block = blk.toList(), important = imp.toList())
            }
        }

        return ExportedBlockSnapshot(
            globalBlock = globalBlock.toList(),
            globalImportant = globalImportant.toList(),
            appRules = appRulesMap,
            invertedRules = loaded.invertedCustomRules + loaded.invertedSubscriptionRules,
            disabledRules = emptyList(),
            specialRules = loaded.specialRules,
        )
    }

    /** Loads (validating) an existing trie or compiles a fresh one; `FAILED` means the compile
     *  ran but produced nothing usable, so callers must not refresh the stamp. */
    private fun ensureIndex(file: File?, triesFresh: Boolean, compile: ((EnabledRule) -> Unit) -> Unit): IndexOutcome {
        if (file == null) return IndexOutcome.NOT_INDEXED
        if (triesFresh && file.exists() && file.length() > 0) {
            val loaded = runCatching { MappedSubscriptionRuleIndex.load(file) }
                .onFailure { Log.w(TAG, "Existing subscription block index invalid, will recompile", it) }
                .getOrNull()
            if (loaded != null) {
                loaded.close()
                return IndexOutcome.LOADED
            }
        }
        val compiled = runCatching { MappedSubscriptionRuleIndex.compileAndLoad(file, compile) }
            .onFailure { e -> Log.e(TAG, "Failed to compile subscription block index (${file.name})", e) }
            .getOrNull()
        compiled?.close()
        return if (compiled != null) IndexOutcome.COMPILED else IndexOutcome.FAILED
    }

    private data class CustomBlockRules(
        val customRules: Map<String, String>,
        val importantCustomRules: Map<String, String>,
        val customWildcards: List<String>,
        val importantCustomWildcards: List<String>,
        val customAppBuckets: Map<String, BlockAppBuckets>,
        val invertedCustomRules: List<ExportedInvertedRule>,
        val specialRules: List<ExportedSpecialRule>,
    )

    private fun loadCustomRules(dao: RuleSnapshotDao): CustomBlockRules {
        val custom = HashMap<String, String>()
        val importantCustom = HashMap<String, String>()
        val customWc = mutableListOf<String>()
        val importantCustomWc = mutableListOf<String>()
        val customBucketsMap = HashMap<String, BlockAppBuckets>()
        val customInvertedList = mutableListOf<ExportedInvertedRule>()
        val customSpecialRules = mutableListOf<ExportedSpecialRule>()

        for (entry in dao.enabledCustomRules(RuleSnapshotDao.RuleKind.BLOCK)) {
            val isSpecial = entry.isRegex || !entry.denyallow.isNullOrEmpty() || !entry.dnsType.isNullOrEmpty()
            if (isSpecial) {
                customSpecialRules += entry.toSpecialRule()
                continue
            }

            val isWc = entry.isWildcard || entry.pattern.contains('*')

            if (entry.appInverted && !entry.appScope.isNullOrEmpty()) {
                customInvertedList += ExportedInvertedRule(
                    entry.pattern, entry.source, entry.important, entry.excludedApps(),
                )
            } else if (!entry.appScope.isNullOrEmpty()) {
                for (pkg in entry.appScopePackages()) {
                    val bucket = customBucketsMap.getOrPut(pkg) { BlockAppBuckets() }
                    if (isWc) {
                        if (entry.important) bucket.importantWildcards += entry.pattern
                        else bucket.wildcards += entry.pattern
                    } else {
                        if (entry.important) bucket.importantExact[entry.pattern] = entry.source
                        else bucket.exact[entry.pattern] = entry.source
                    }
                }
            } else {
                if (isWc) {
                    if (entry.important) importantCustomWc += entry.pattern
                    else customWc += entry.pattern
                } else {
                    if (entry.important) importantCustom[entry.pattern] = entry.source
                    else custom[entry.pattern] = entry.source
                }
            }
        }

        return CustomBlockRules(
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
