package com.haoze.diting.vpn

import com.haoze.diting.data.dao.BlockRuleDao
import com.haoze.diting.data.entity.RuleScope
import java.io.File

/**
 * In-memory cache of block rules, backed by an optional mmap index.
 *
 * Both index paths come from [RuleIndexLayout]; the important bucket gets its
 * own file name (`block.important.trie`) rather than being derived from the
 * regular one, so it is passed explicitly instead of being guessed here.
 */
class BlockRuleCache(
    private val indexFile: File? = null,
    private val importantIndexFile: File? = null
) {

    @Volatile
    private var state = BlockRuleCacheState()

    /**
     * Fully reloads enabled rules from the database into memory.
     */
    suspend fun reload(
        dao: BlockRuleDao,
        scope: RuleScope = RuleScope.DNS,
        forceRebuild: Boolean = false
    ) {
        val result = BlockRuleCacheLoader.loadAll(
            dao = dao,
            scope = scope,
            forceRebuild = forceRebuild,
            indexFile = indexFile,
            importantIndexFile = importantIndexFile
        )

        val oldIndex: MappedSubscriptionRuleIndex?
        val oldImportantIndex: MappedSubscriptionRuleIndex?
        synchronized(this) {
            oldIndex = state.subscriptionIndex
            oldImportantIndex = state.importantSubscriptionIndex

            state = BlockRuleCacheState(
                customRules = result.customRules,
                importantCustomRules = result.importantCustomRules,
                customWildcards = result.customWildcards,
                importantCustomWildcards = result.importantCustomWildcards,
                customAppBuckets = result.customAppBuckets,
                invertedCustomRules = result.invertedCustomRules,
                subscriptionFallback = result.subscriptionFallback,
                importantSubscriptionFallback = result.importantSubscriptionFallback,
                subscriptionWildcards = result.subscriptionWildcards,
                importantSubscriptionWildcards = result.importantSubscriptionWildcards,
                subscriptionAppBuckets = result.subscriptionAppBuckets,
                invertedSubscriptionRules = result.invertedSubscriptionRules,
                subscriptionOverrides = emptyMap(),
                subscriptionIndex = result.subscriptionIndex,
                importantSubscriptionIndex = result.importantSubscriptionIndex,
                specialRules = result.specialRules
            )
        }
        if (oldIndex !== result.subscriptionIndex) {
            oldIndex?.close()
        }
        if (oldImportantIndex !== result.importantSubscriptionIndex) {
            oldImportantIndex?.close()
        }
    }

    /**
     * Matches in O(number of domain labels).
     */
    fun findMatch(qname: String, packageName: String? = null): BlockRuleMatch? =
        BlockRuleMatcher.findMatch(state, qname, packageName)

    /**
     * Per-app $important block rule matching (priority 1).
     */
    fun findAppImportantMatch(qname: String, packageName: String): BlockRuleMatch? =
        BlockRuleMatcher.findAppImportantMatch(state, qname, packageName)

    /**
     * Global $important block rule matching (priority 2).
     */
    fun findGlobalImportantMatch(qname: String, packageName: String? = null): BlockRuleMatch? =
        BlockRuleMatcher.findGlobalImportantMatch(state, qname, packageName)

    /**
     * Per-app regular block rule matching (priority 5; includes full-domain
     * blocks declared with *$app=pkg).
     */
    fun findAppMatch(qname: String, packageName: String): BlockRuleMatch? =
        BlockRuleMatcher.findAppMatch(state, qname, packageName)

    /**
     * Global regular block rule matching (priority 6).
     */
    fun findGlobalMatch(qname: String, packageName: String? = null): BlockRuleMatch? =
        BlockRuleMatcher.findGlobalMatch(state, qname, packageName)

    fun findCustomMatch(qname: String, packageName: String? = null): BlockRuleMatch? =
        BlockRuleMatcher.findCustomMatch(state, qname, packageName)

    fun findImportantCustomMatch(qname: String, packageName: String? = null): BlockRuleMatch? =
        BlockRuleMatcher.findImportantCustomMatch(state, qname, packageName)

    fun findSubscriptionMatch(qname: String, packageName: String? = null): BlockRuleMatch? =
        BlockRuleMatcher.findSubscriptionMatch(state, qname, packageName)

    fun findImportantSubscriptionMatch(qname: String, packageName: String? = null): BlockRuleMatch? =
        BlockRuleMatcher.findImportantSubscriptionMatch(state, qname, packageName)

    fun addPattern(pattern: String, source: String) {
        synchronized(this) {
            val current = state
            if (pattern == "*" || pattern.contains('*')) {
                val wp = AdGuardRuleParser.WildcardPattern(pattern)
                val newCustomWildcards = current.customWildcards.filterNot { it.first.pattern == pattern } + (wp to source)
                state = current.copy(customWildcards = newCustomWildcards)
            } else {
                val newCustomRules = HashMap(current.customRules).apply { put(pattern, source) }
                state = current.copy(customRules = newCustomRules)
            }
        }
    }

    fun removePattern(pattern: String) {
        synchronized(this) {
            val current = state
            if (pattern == "*" || pattern.contains('*')) {
                val newCustomWildcards = current.customWildcards.filterNot { it.first.pattern == pattern }
                val newImportantCustomWildcards = current.importantCustomWildcards.filterNot { it.first.pattern == pattern }
                state = current.copy(
                    customWildcards = newCustomWildcards,
                    importantCustomWildcards = newImportantCustomWildcards
                )
            } else {
                var newCustomRules = current.customRules
                var newImportantCustomRules = current.importantCustomRules
                if (pattern in newCustomRules) {
                    newCustomRules = HashMap(newCustomRules).apply { remove(pattern) }
                }
                if (pattern in newImportantCustomRules) {
                    newImportantCustomRules = HashMap(newImportantCustomRules).apply { remove(pattern) }
                }
                state = current.copy(
                    customRules = newCustomRules,
                    importantCustomRules = newImportantCustomRules
                )
            }
        }
    }

    fun syncPattern(pattern: String, source: String?) {
        synchronized(this) {
            val current = state
            if (pattern == "*" || pattern.contains('*')) {
                val wp = AdGuardRuleParser.WildcardPattern(pattern)
                var newCustomWildcards = current.customWildcards.filterNot { it.first.pattern == pattern }
                if (source != null && !source.startsWith("sub_")) {
                    newCustomWildcards = newCustomWildcards + (wp to source)
                }
                state = current.copy(customWildcards = newCustomWildcards)
            } else {
                val newCustomRules = HashMap(current.customRules).apply {
                    remove(pattern)
                    if (source != null && !source.startsWith("sub_")) put(pattern, source)
                }
                val newSubscriptionOverrides = HashMap(current.subscriptionOverrides).apply {
                    if (source == null || source.startsWith("sub_")) put(pattern, source) else remove(pattern)
                }
                state = current.copy(
                    customRules = newCustomRules,
                    subscriptionOverrides = newSubscriptionOverrides
                )
            }
        }
    }

    suspend fun reloadCustomRules(dao: BlockRuleDao) {
        val result = BlockRuleCacheLoader.loadCustomRules(dao)
        synchronized(this) {
            val subSpecial = state.specialRules.filter { it.source.startsWith("sub_") }
            state = state.copy(
                customRules = result.customRules,
                importantCustomRules = result.importantCustomRules,
                customWildcards = result.customWildcards,
                importantCustomWildcards = result.importantCustomWildcards,
                customAppBuckets = result.customAppBuckets,
                invertedCustomRules = result.invertedCustomRules,
                specialRules = result.specialRules + subSpecial
            )
        }
    }

    fun syncCustomPattern(
        pattern: String,
        source: String?,
        importantSource: String?,
        appScope: String? = null,
        appInverted: Boolean = false,
        isWildcard: Boolean = false
    ) {
        synchronized(this) {
            val current = state
            val isWc = isWildcard || pattern.contains('*')
            val wp = if (isWc) AdGuardRuleParser.WildcardPattern(pattern) else null

            if (isWc && wp != null) {
                var newCustomWildcards = current.customWildcards.filterNot { it.first.pattern == pattern }
                var newImportantCustomWildcards = current.importantCustomWildcards.filterNot { it.first.pattern == pattern }
                var newSubscriptionWildcards = current.subscriptionWildcards.filterNot { it.first.pattern == pattern }
                var newImportantSubscriptionWildcards = current.importantSubscriptionWildcards.filterNot { it.first.pattern == pattern }

                if (source != null) {
                    if (source.startsWith("sub_")) {
                        newSubscriptionWildcards = newSubscriptionWildcards + (wp to source)
                    } else {
                        newCustomWildcards = newCustomWildcards + (wp to source)
                    }
                }
                if (importantSource != null) {
                    if (importantSource.startsWith("sub_")) {
                        newImportantSubscriptionWildcards = newImportantSubscriptionWildcards + (wp to importantSource)
                    } else {
                        newImportantCustomWildcards = newImportantCustomWildcards + (wp to importantSource)
                    }
                }
                state = current.copy(
                    customWildcards = newCustomWildcards,
                    importantCustomWildcards = newImportantCustomWildcards,
                    subscriptionWildcards = newSubscriptionWildcards,
                    importantSubscriptionWildcards = newImportantSubscriptionWildcards
                )
            } else {
                val newCustomRules = HashMap(current.customRules).apply {
                    remove(pattern)
                    if (source != null && !source.startsWith("sub_")) put(pattern, source)
                }
                val newImportantCustomRules = HashMap(current.importantCustomRules).apply {
                    remove(pattern)
                    if (importantSource != null && !importantSource.startsWith("sub_")) {
                        put(pattern, importantSource)
                    }
                }
                val newSubscriptionOverrides = HashMap(current.subscriptionOverrides).apply {
                    val effectiveSubSource = when {
                        source?.startsWith("sub_") == true -> source
                        importantSource?.startsWith("sub_") == true -> importantSource
                        else -> null
                    }
                    if (source == null && importantSource == null) {
                        put(pattern, null)
                    } else if (effectiveSubSource != null) {
                        put(pattern, effectiveSubSource)
                    } else {
                        remove(pattern)
                    }
                }
                state = current.copy(
                    customRules = newCustomRules,
                    importantCustomRules = newImportantCustomRules,
                    subscriptionOverrides = newSubscriptionOverrides
                )
            }
        }
    }

    fun clear() {
        val oldIndex: MappedSubscriptionRuleIndex?
        val oldImportantIndex: MappedSubscriptionRuleIndex?
        synchronized(this) {
            oldIndex = state.subscriptionIndex
            oldImportantIndex = state.importantSubscriptionIndex
            state = BlockRuleCacheState()
        }
        oldIndex?.close()
        oldImportantIndex?.close()
    }

    fun exportSnapshot(): ExportedBlockSnapshot {
        val current = state
        val globalBlock = LinkedHashSet<String>()
        val globalImportant = LinkedHashSet<String>()

        globalBlock.addAll(current.customRules.keys)
        current.customWildcards.forEach { globalBlock.add(it.first.pattern) }
        globalBlock.addAll(current.subscriptionFallback.keys)
        current.subscriptionWildcards.forEach { globalBlock.add(it.first.pattern) }

        globalImportant.addAll(current.importantCustomRules.keys)
        current.importantCustomWildcards.forEach { globalImportant.add(it.first.pattern) }
        globalImportant.addAll(current.importantSubscriptionFallback.keys)
        current.importantSubscriptionWildcards.forEach { globalImportant.add(it.first.pattern) }

        val appPkgs = current.customAppBuckets.keys + current.subscriptionAppBuckets.keys
        val appRulesMap = HashMap<String, ExportedAppBlockRules>()
        for (pkg in appPkgs) {
            val cBucket = current.customAppBuckets[pkg]
            val sBucket = current.subscriptionAppBuckets[pkg]
            val blk = LinkedHashSet<String>()
            val imp = LinkedHashSet<String>()

            cBucket?.let {
                blk.addAll(it.exactRules.keys)
                it.wildcardRules.forEach { w -> blk.add(w.first.pattern) }
                imp.addAll(it.importantExactRules.keys)
                it.importantWildcardRules.forEach { w -> imp.add(w.first.pattern) }
            }
            sBucket?.let {
                blk.addAll(it.exactRules.keys)
                it.wildcardRules.forEach { w -> blk.add(w.first.pattern) }
                imp.addAll(it.importantExactRules.keys)
                it.importantWildcardRules.forEach { w -> imp.add(w.first.pattern) }
            }
            if (blk.isNotEmpty() || imp.isNotEmpty()) {
                appRulesMap[pkg] = ExportedAppBlockRules(block = blk.toList(), important = imp.toList())
            }
        }

        val inverted = ArrayList<ExportedInvertedRule>()
        for (rule in current.invertedCustomRules) {
            inverted.add(ExportedInvertedRule(rule.pattern, rule.source, rule.important, rule.excludedApps))
        }
        for (rule in current.invertedSubscriptionRules) {
            inverted.add(ExportedInvertedRule(rule.pattern, rule.source, rule.important, rule.excludedApps))
        }

        val disabled = current.subscriptionOverrides.filter { it.value == null }.keys.toList()

        return ExportedBlockSnapshot(
            globalBlock = globalBlock.toList(),
            globalImportant = globalImportant.toList(),
            appRules = appRulesMap,
            invertedRules = inverted,
            disabledRules = disabled,
            specialRules = current.specialRules
        )
    }

    fun size(): Int {
        val current = state
        return current.customRules.size + current.importantCustomRules.size + current.customWildcards.size +
            current.importantCustomWildcards.size + current.subscriptionFallback.size + current.importantSubscriptionFallback.size +
            current.subscriptionWildcards.size + current.importantSubscriptionWildcards.size +
            current.customAppBuckets.values.sumOf { it.exactRules.size + it.importantExactRules.size + it.wildcardRules.size + it.importantWildcardRules.size } +
            current.subscriptionAppBuckets.values.sumOf { it.exactRules.size + it.importantExactRules.size + it.wildcardRules.size + it.importantWildcardRules.size }
    }
}
