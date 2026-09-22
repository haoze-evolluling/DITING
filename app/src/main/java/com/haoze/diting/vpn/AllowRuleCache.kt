package com.haoze.diting.vpn

import com.haoze.diting.data.dao.AllowRuleDao
import com.haoze.diting.data.entity.RuleScope
import java.io.File

/**
 * In-memory cache of allowlist rules, backed by an optional mmap index.
 *
 * Matching semantics are identical to the block rules: exact match or parent
 * domain suffix match.
 */
class AllowRuleCache(
    private val indexFile: File? = null,
    private val importantIndexFile: File? = null
) {

    @Volatile
    private var state = AllowRuleCacheState()

    suspend fun reload(
        dao: AllowRuleDao,
        scope: RuleScope = RuleScope.DNS,
        forceRebuild: Boolean = false
    ) {
        val result = AllowRuleCacheLoader.loadAll(
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

            state = AllowRuleCacheState(
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

    fun isAllowed(qname: String, packageName: String? = null): Boolean =
        AllowRuleMatcher.isAllowed(state, qname, packageName)

    fun findMatch(qname: String, packageName: String? = null): String? =
        AllowRuleMatcher.findMatch(state, qname, packageName)

    /**
     * Per-app allowlist rule matching (priority 3; covers both important and
     * regular allowlist rules).
     */
    fun findAppMatch(qname: String, packageName: String): String? =
        AllowRuleMatcher.findAppMatch(state, qname, packageName)

    /**
     * Global allowlist rule matching (priority 4).
     */
    fun findGlobalMatch(qname: String, packageName: String? = null): String? =
        AllowRuleMatcher.findGlobalMatch(state, qname, packageName)

    fun findCustomMatch(qname: String, packageName: String? = null): String? =
        AllowRuleMatcher.findCustomMatch(state, qname, packageName)

    fun findImportantCustomMatch(qname: String, packageName: String? = null): String? =
        AllowRuleMatcher.findImportantCustomMatch(state, qname, packageName)

    fun findSubscriptionMatch(qname: String, packageName: String? = null): String? =
        AllowRuleMatcher.findSubscriptionMatch(state, qname, packageName)

    fun findImportantSubscriptionMatch(qname: String, packageName: String? = null): String? =
        AllowRuleMatcher.findImportantSubscriptionMatch(state, qname, packageName)

    fun addPattern(pattern: String) {
        synchronized(this) {
            val current = state
            if (pattern == "*" || pattern.contains('*')) {
                val wp = AdGuardRuleParser.WildcardPattern(pattern)
                val newCustomWildcards = current.customWildcards.filterNot { it.pattern == pattern } + wp
                state = current.copy(customWildcards = newCustomWildcards)
            } else {
                val newCustomRules = HashSet(current.customRules).apply { add(pattern) }
                state = current.copy(customRules = newCustomRules)
            }
        }
    }

    fun removePattern(pattern: String) {
        synchronized(this) {
            val current = state
            if (pattern == "*" || pattern.contains('*')) {
                val newCustomWildcards = current.customWildcards.filterNot { it.pattern == pattern }
                val newImportantCustomWildcards = current.importantCustomWildcards.filterNot { it.pattern == pattern }
                state = current.copy(
                    customWildcards = newCustomWildcards,
                    importantCustomWildcards = newImportantCustomWildcards
                )
            } else {
                var newCustomRules = current.customRules
                var newImportantCustomRules = current.importantCustomRules
                if (pattern in newCustomRules) {
                    newCustomRules = HashSet(newCustomRules).apply { remove(pattern) }
                }
                if (pattern in newImportantCustomRules) {
                    newImportantCustomRules = HashSet(newImportantCustomRules).apply { remove(pattern) }
                }
                state = current.copy(
                    customRules = newCustomRules,
                    importantCustomRules = newImportantCustomRules
                )
            }
        }
    }

    suspend fun reloadCustomRules(dao: AllowRuleDao) {
        val result = AllowRuleCacheLoader.loadCustomRules(dao)
        synchronized(this) {
            val subSpecial = state.specialRules.filter { sub -> !result.specialRules.any { it.pattern == sub.pattern } }
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

    fun syncPattern(pattern: String, source: String?) {
        synchronized(this) {
            val current = state
            if (pattern == "*" || pattern.contains('*')) {
                val wp = AdGuardRuleParser.WildcardPattern(pattern)
                var newCustomWildcards = current.customWildcards.filterNot { it.pattern == pattern }
                var newSubscriptionWildcards = current.subscriptionWildcards.filterNot { it.pattern == pattern }
                var newImportantSubscriptionWildcards = current.importantSubscriptionWildcards.filterNot { it.pattern == pattern }
                if (source != null) {
                    if (source.startsWith("sub_")) {
                        newSubscriptionWildcards = newSubscriptionWildcards + wp
                    } else {
                        newCustomWildcards = newCustomWildcards + wp
                    }
                }
                state = current.copy(
                    customWildcards = newCustomWildcards,
                    subscriptionWildcards = newSubscriptionWildcards,
                    importantSubscriptionWildcards = newImportantSubscriptionWildcards
                )
            } else {
                val newCustomRules = HashSet(current.customRules).apply {
                    remove(pattern)
                    if (source != null && !source.startsWith("sub_")) add(pattern)
                }
                val newSubscriptionOverrides = HashMap(current.subscriptionOverrides).apply {
                    if (source == null) put(pattern, null)
                    else if (source.startsWith("sub_")) put(pattern, pattern)
                    else remove(pattern)
                }
                state = current.copy(
                    customRules = newCustomRules,
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
            state = AllowRuleCacheState()
        }
        oldIndex?.close()
        oldImportantIndex?.close()
    }

    fun exportSnapshot(): ExportedAllowSnapshot {
        val current = state
        val globalAllow = LinkedHashSet<String>()

        globalAllow.addAll(current.customRules)
        current.customWildcards.forEach { globalAllow.add(it.pattern) }
        globalAllow.addAll(current.importantCustomRules)
        current.importantCustomWildcards.forEach { globalAllow.add(it.pattern) }
        globalAllow.addAll(current.subscriptionFallback)
        current.subscriptionWildcards.forEach { globalAllow.add(it.pattern) }
        globalAllow.addAll(current.importantSubscriptionFallback)
        current.importantSubscriptionWildcards.forEach { globalAllow.add(it.pattern) }

        val appPkgs = current.customAppBuckets.keys + current.subscriptionAppBuckets.keys
        val appRulesMap = HashMap<String, List<String>>()
        for (pkg in appPkgs) {
            val cBucket = current.customAppBuckets[pkg]
            val sBucket = current.subscriptionAppBuckets[pkg]
            val all = LinkedHashSet<String>()

            cBucket?.let {
                all.addAll(it.exactRules)
                all.addAll(it.importantExactRules)
                it.wildcardRules.forEach { w -> all.add(w.pattern) }
                it.importantWildcardRules.forEach { w -> all.add(w.pattern) }
            }
            sBucket?.let {
                all.addAll(it.exactRules)
                all.addAll(it.importantExactRules)
                it.wildcardRules.forEach { w -> all.add(w.pattern) }
                it.importantWildcardRules.forEach { w -> all.add(w.pattern) }
            }
            if (all.isNotEmpty()) {
                appRulesMap[pkg] = all.toList()
            }
        }

        val inverted = ArrayList<ExportedInvertedAllowRule>()
        for (rule in current.invertedCustomRules) {
            inverted.add(ExportedInvertedAllowRule(rule.pattern, rule.excludedApps))
        }
        for (rule in current.invertedSubscriptionRules) {
            inverted.add(ExportedInvertedAllowRule(rule.pattern, rule.excludedApps))
        }

        return ExportedAllowSnapshot(
            globalAllow = globalAllow.toList(),
            appRules = appRulesMap,
            invertedRules = inverted,
            specialRules = current.specialRules
        )
    }
}
