package com.haoze.dnssr.vpn

import android.util.Log
import com.haoze.dnssr.util.forEachKeysetPage
import com.haoze.dnssr.data.dao.AllowRuleDao
import com.haoze.dnssr.data.entity.RuleScope
import java.io.File

/**
 * 白名单规则内存缓存。
 *
 * 匹配逻辑与屏蔽规则一致：精确匹配或父域后缀匹配。
 */
data class InvertedAllowRule(
    val pattern: String,
    val important: Boolean,
    val excludedApps: Set<String>,
    val wildcard: AdGuardRuleParser.WildcardPattern? = null
)

data class AllowAppRuleBucket(
    val exactRules: Set<String> = emptySet(),
    val importantExactRules: Set<String> = emptySet(),
    val wildcardRules: List<AdGuardRuleParser.WildcardPattern> = emptyList(),
    val importantWildcardRules: List<AdGuardRuleParser.WildcardPattern> = emptyList()
) {
    fun isEmpty(): Boolean = exactRules.isEmpty() && importantExactRules.isEmpty() &&
        wildcardRules.isEmpty() && importantWildcardRules.isEmpty()
}

class AllowRuleCache(private val indexFile: File? = null) {

    @Volatile
    private var customRules: Set<String> = emptySet()
    @Volatile
    private var importantCustomRules: Set<String> = emptySet()
    @Volatile
    private var customWildcards: List<AdGuardRuleParser.WildcardPattern> = emptyList()
    @Volatile
    private var importantCustomWildcards: List<AdGuardRuleParser.WildcardPattern> = emptyList()

    @Volatile
    private var customAppBuckets: Map<String, AllowAppRuleBucket> = emptyMap()
    @Volatile
    private var invertedCustomRules: List<InvertedAllowRule> = emptyList()

    @Volatile
    private var subscriptionFallback: Set<String> = emptySet()
    @Volatile
    private var importantSubscriptionFallback: Set<String> = emptySet()
    @Volatile
    private var subscriptionWildcards: List<AdGuardRuleParser.WildcardPattern> = emptyList()
    @Volatile
    private var importantSubscriptionWildcards: List<AdGuardRuleParser.WildcardPattern> = emptyList()

    @Volatile
    private var subscriptionAppBuckets: Map<String, AllowAppRuleBucket> = emptyMap()
    @Volatile
    private var invertedSubscriptionRules: List<InvertedAllowRule> = emptyList()

    @Volatile
    private var subscriptionOverrides: Map<String, String?> = emptyMap()
    @Volatile
    private var subscriptionIndex: MappedSubscriptionRuleIndex? = null
    @Volatile
    private var importantSubscriptionIndex: MappedSubscriptionRuleIndex? = null

    suspend fun reload(
        dao: AllowRuleDao,
        scope: RuleScope = RuleScope.DNS,
        forceRebuild: Boolean = false
    ) {
        val customRuleEntries = dao.enabledCustomRules()

        val custom = HashSet<String>()
        val importantCustom = HashSet<String>()
        val customWc = mutableListOf<AdGuardRuleParser.WildcardPattern>()
        val importantCustomWc = mutableListOf<AdGuardRuleParser.WildcardPattern>()
        val customBucketsMap = HashMap<String, MutableAllowAppBucket>()
        val customInvertedList = mutableListOf<InvertedAllowRule>()

        for (entry in customRuleEntries) {
            val isWc = entry.isWildcard || entry.pattern.contains('*')
            val wcPattern = if (isWc) AdGuardRuleParser.WildcardPattern(entry.pattern) else null

            if (entry.appInverted && !entry.appScope.isNullOrEmpty()) {
                val excluded = entry.appScope.split('|').map { it.trim().lowercase() }.filter { it.isNotEmpty() }.toSet()
                customInvertedList.add(InvertedAllowRule(entry.pattern, entry.important, excluded, wcPattern))
            } else if (!entry.appScope.isNullOrEmpty()) {
                val pkgs = entry.appScope.split('|').map { it.trim().lowercase() }.filter { it.isNotEmpty() }
                for (pkg in pkgs) {
                    val bucket = customBucketsMap.getOrPut(pkg) { MutableAllowAppBucket() }
                    if (isWc && wcPattern != null) {
                        if (entry.important) bucket.importantWildcards.add(wcPattern)
                        else bucket.wildcards.add(wcPattern)
                    } else {
                        if (entry.important) bucket.importantExact.add(entry.pattern)
                        else bucket.exact.add(entry.pattern)
                    }
                }
            } else {
                if (isWc && wcPattern != null) {
                    if (entry.important) importantCustomWc.add(wcPattern)
                    else customWc.add(wcPattern)
                } else {
                    if (entry.important) importantCustom.add(entry.pattern)
                    else custom.add(entry.pattern)
                }
            }
        }

        val targetFile = indexFile
        val importantFile = targetFile?.let { File(it.parentFile, it.name + ".important") }

        var mapped = targetFile?.let { file ->
            if (!forceRebuild && file.exists() && file.length() > 0) {
                runCatching { MappedSubscriptionRuleIndex.load(file) }
                    .onFailure { Log.w(TAG, "Existing subscription allow index invalid, will recompile", it) }
                    .getOrNull()
            } else null
        }

        var importantMapped = importantFile?.let { file ->
            if (!forceRebuild && file.exists() && file.length() > 0) {
                runCatching { MappedSubscriptionRuleIndex.load(file) }
                    .onFailure { Log.w(TAG, "Existing important subscription allow index invalid, will recompile", it) }
                    .getOrNull()
            } else null
        }

        if (mapped == null) {
            mapped = targetFile?.let { file ->
                runCatching {
                    MappedSubscriptionRuleIndex.compileAndLoad(file) { consume ->
                        dao.forEachSubscriptionRulePage { rule ->
                            if (!rule.important && !rule.isWildcard && !rule.pattern.contains('*') && rule.appScope.isNullOrEmpty() && !rule.appInverted) {
                                consume(rule)
                            }
                        }
                    }
                }.onFailure { e ->
                    Log.e(TAG, "Failed to compile subscription allow index (${file.name})", e)
                }.getOrNull()
            }
        }

        if (importantMapped == null) {
            importantMapped = importantFile?.let { file ->
                runCatching {
                    MappedSubscriptionRuleIndex.compileAndLoad(file) { consume ->
                        dao.forEachSubscriptionRulePage { rule ->
                            if (rule.important && !rule.isWildcard && !rule.pattern.contains('*') && rule.appScope.isNullOrEmpty() && !rule.appInverted) {
                                consume(rule)
                            }
                        }
                    }
                }.onFailure { e ->
                    Log.e(TAG, "Failed to compile important subscription allow index (${file.name})", e)
                }.getOrNull()
            }
        }

        val subFallback = HashSet<String>()
        val importantSubFallback = HashSet<String>()
        val subWc = mutableListOf<AdGuardRuleParser.WildcardPattern>()
        val importantSubWc = mutableListOf<AdGuardRuleParser.WildcardPattern>()
        val subBucketsMap = HashMap<String, MutableAllowAppBucket>()
        val subInvertedList = mutableListOf<InvertedAllowRule>()

        fun processSubscriptionRule(entry: com.haoze.dnssr.data.dao.EnabledBlockRule) {
            val isWc = entry.isWildcard || entry.pattern.contains('*')
            val wcPattern = if (isWc) AdGuardRuleParser.WildcardPattern(entry.pattern) else null

            if (entry.appInverted && !entry.appScope.isNullOrEmpty()) {
                val excluded = entry.appScope.split('|').map { it.trim().lowercase() }.filter { it.isNotEmpty() }.toSet()
                subInvertedList.add(InvertedAllowRule(entry.pattern, entry.important, excluded, wcPattern))
            } else if (!entry.appScope.isNullOrEmpty()) {
                val pkgs = entry.appScope.split('|').map { it.trim().lowercase() }.filter { it.isNotEmpty() }
                for (pkg in pkgs) {
                    val bucket = subBucketsMap.getOrPut(pkg) { MutableAllowAppBucket() }
                    if (isWc && wcPattern != null) {
                        if (entry.important) bucket.importantWildcards.add(wcPattern)
                        else bucket.wildcards.add(wcPattern)
                    } else {
                        if (entry.important) bucket.importantExact.add(entry.pattern)
                        else bucket.exact.add(entry.pattern)
                    }
                }
            } else if (isWc && wcPattern != null) {
                if (entry.important) importantSubWc.add(wcPattern)
                else subWc.add(wcPattern)
            } else {
                if (entry.important) {
                    if (importantMapped == null) importantSubFallback.add(entry.pattern)
                } else {
                    if (mapped == null) subFallback.add(entry.pattern)
                }
            }
        }

        if (mapped != null && importantMapped != null) {
            dao.enabledSpecialSubscriptionRules().forEach(::processSubscriptionRule)
        } else {
            dao.forEachSubscriptionRulePage(::processSubscriptionRule)
        }

        val oldIndex: MappedSubscriptionRuleIndex?
        val oldImportantIndex: MappedSubscriptionRuleIndex?
        synchronized(this) {
            customRules = custom
            importantCustomRules = importantCustom
            customWildcards = customWc
            importantCustomWildcards = importantCustomWc
            customAppBuckets = customBucketsMap.mapValues { it.value.toImmutable() }
            invertedCustomRules = customInvertedList

            subscriptionFallback = subFallback
            importantSubscriptionFallback = importantSubFallback
            subscriptionWildcards = subWc
            importantSubscriptionWildcards = importantSubWc
            subscriptionAppBuckets = subBucketsMap.mapValues { it.value.toImmutable() }
            invertedSubscriptionRules = subInvertedList

            oldIndex = subscriptionIndex
            subscriptionIndex = mapped
            oldImportantIndex = importantSubscriptionIndex
            importantSubscriptionIndex = importantMapped
            subscriptionOverrides = emptyMap()
        }
        if (oldIndex !== mapped) {
            oldIndex?.close()
        }
        if (oldImportantIndex !== importantMapped) {
            oldImportantIndex?.close()
        }
    }

    fun isAllowed(qname: String, packageName: String? = null): Boolean {
        return findMatch(qname, packageName) != null
    }

    fun findMatch(qname: String, packageName: String? = null): String? {
        return findImportantCustomMatch(qname, packageName)
            ?: findImportantSubscriptionMatch(qname, packageName)
            ?: findCustomMatch(qname, packageName)
            ?: findSubscriptionMatch(qname, packageName)
    }

    /**
     * App 专用白名单规则匹配（优先级 3，包含重要与常规白名单规则）
     */
    fun findAppMatch(qname: String, packageName: String): String? {
        val domain = qname.lowercase().trimEnd('.')
        if (domain.isEmpty() || packageName.isEmpty()) return null

        findInAppBucket(customAppBuckets, packageName, domain, important = true)?.let { return it }
        findInAppBucket(customAppBuckets, packageName, domain, important = false)?.let { return it }
        findInAppBucket(subscriptionAppBuckets, packageName, domain, important = true)?.let { return it }
        findInAppBucket(subscriptionAppBuckets, packageName, domain, important = false)?.let { return it }

        return null
    }

    /**
     * 全局白名单规则匹配（优先级 4）
     */
    fun findGlobalMatch(qname: String, packageName: String? = null): String? {
        val domain = qname.lowercase().trimEnd('.')
        if (domain.isEmpty()) return null

        findInInvertedRules(invertedCustomRules, domain, important = null, packageName)?.let { return it }

        findInSet(domain, importantCustomRules)?.let { return it }
        findInWildcards(domain, importantCustomWildcards)?.let { return it }
        findInSet(domain, customRules)?.let { return it }
        findInWildcards(domain, customWildcards)?.let { return it }

        findInInvertedRules(invertedSubscriptionRules, domain, important = null, packageName)?.let { return it }

        return findSubscriptionTail(domain, important = true)
            ?: findSubscriptionTail(domain, important = false)
    }

    fun findCustomMatch(qname: String, packageName: String? = null): String? {
        val domain = qname.lowercase().trimEnd('.')
        if (domain.isEmpty()) return null

        findInAppBucket(customAppBuckets, packageName, domain, important = false)?.let { return it }

        findInInvertedRules(invertedCustomRules, domain, important = false, packageName)?.let { return it }

        return findInSet(domain, customRules) ?: findInWildcards(domain, customWildcards)
    }

    fun findImportantCustomMatch(qname: String, packageName: String? = null): String? {
        val domain = qname.lowercase().trimEnd('.')
        if (domain.isEmpty()) return null

        findInAppBucket(customAppBuckets, packageName, domain, important = true)?.let { return it }

        findInInvertedRules(invertedCustomRules, domain, important = true, packageName)?.let { return it }

        return findInSet(domain, importantCustomRules) ?: findInWildcards(domain, importantCustomWildcards)
    }

    fun findSubscriptionMatch(qname: String, packageName: String? = null): String? {
        val domain = qname.lowercase().trimEnd('.')
        if (domain.isEmpty()) return null

        findInAppBucket(subscriptionAppBuckets, packageName, domain, important = false)?.let { return it }

        findInInvertedRules(invertedSubscriptionRules, domain, important = false, packageName)?.let { return it }

        return findSubscriptionTail(domain, important = false)
    }

    fun findImportantSubscriptionMatch(qname: String, packageName: String? = null): String? {
        val domain = qname.lowercase().trimEnd('.')
        if (domain.isEmpty()) return null

        findInAppBucket(subscriptionAppBuckets, packageName, domain, important = true)?.let { return it }

        findInInvertedRules(invertedSubscriptionRules, domain, important = true, packageName)?.let { return it }

        return findSubscriptionTail(domain, important = true)
    }

    /** 在指定应用的规则桶内按 精确→通配符 顺序匹配。 */
    private fun findInAppBucket(
        buckets: Map<String, AllowAppRuleBucket>,
        packageName: String?,
        domain: String,
        important: Boolean
    ): String? {
        val bucket = packageName?.let { buckets[it] } ?: return null
        val exact = if (important) bucket.importantExactRules else bucket.exactRules
        val wildcards = if (important) bucket.importantWildcardRules else bucket.wildcardRules
        return findInSet(domain, exact) ?: findInWildcards(domain, wildcards)
    }

    /** 匹配倒排规则（排除应用名单）；[important] 为 null 时不区分重要/常规。 */
    private fun findInInvertedRules(
        rules: List<InvertedAllowRule>,
        domain: String,
        important: Boolean?,
        packageName: String?
    ): String? {
        for (rule in rules) {
            if ((important == null || rule.important == important) &&
                (packageName == null || packageName !in rule.excludedApps)
            ) {
                if (rule.wildcard != null && rule.wildcard.matches(domain)) {
                    return rule.pattern
                } else if (rule.wildcard == null && matchesDomainOrSuffix(domain, rule.pattern)) {
                    return rule.pattern
                }
            }
        }
        return null
    }

    /** 订阅 mmap 索引优先、内存 fallback 兜底的精确匹配 + 通配符兜底。 */
    private fun findSubscriptionTail(domain: String, important: Boolean): String? {
        return if (important) {
            findSubscriptionExactMatch(domain, importantSubscriptionIndex, importantSubscriptionFallback)
                ?: findInWildcards(domain, importantSubscriptionWildcards)
        } else {
            findSubscriptionExactMatch(domain, subscriptionIndex, subscriptionFallback)
                ?: findInWildcards(domain, subscriptionWildcards)
        }
    }

    private fun findSubscriptionExactMatch(
        domain: String,
        index: MappedSubscriptionRuleIndex?,
        subscriptions: Set<String>
    ): String? {
        index?.find(domain, subscriptionOverrides)?.let { return it }
        fun isEnabled(pattern: String): Boolean = if (subscriptionOverrides.containsKey(pattern)) {
            subscriptionOverrides[pattern] != null
        } else {
            subscriptions.contains(pattern)
        }
        if (isEnabled(domain)) return domain
        var subscriptionPos = domain.indexOf('.')
        while (subscriptionPos >= 0 && subscriptionPos < domain.length - 1) {
            val suffix = domain.substring(subscriptionPos + 1)
            if (isEnabled(suffix)) return suffix
            subscriptionPos = domain.indexOf('.', subscriptionPos + 1)
        }
        return null
    }

    private fun findInSet(domain: String, rules: Set<String>): String? {
        if (rules.contains(domain)) return domain
        var pos = domain.indexOf('.')
        while (pos >= 0 && pos < domain.length - 1) {
            val suffix = domain.substring(pos + 1)
            if (rules.contains(suffix)) return suffix
            pos = domain.indexOf('.', pos + 1)
        }
        return null
    }

    private fun findInWildcards(domain: String, wildcards: List<AdGuardRuleParser.WildcardPattern>): String? {
        for (wp in wildcards) {
            if (wp.matches(domain)) {
                return wp.pattern
            }
        }
        return null
    }

    private fun matchesDomainOrSuffix(domain: String, pattern: String): Boolean {
        if (domain == pattern) return true
        return domain.endsWith(".$pattern")
    }

    fun addPattern(pattern: String) {
        synchronized(this) {
            if (pattern == "*" || pattern.contains('*')) {
                val wp = AdGuardRuleParser.WildcardPattern(pattern)
                customWildcards = customWildcards.filterNot { it.pattern == pattern } + wp
            } else {
                customRules = HashSet(customRules).apply { add(pattern) }
            }
        }
    }

    fun removePattern(pattern: String) {
        synchronized(this) {
            if (pattern == "*" || pattern.contains('*')) {
                customWildcards = customWildcards.filterNot { it.pattern == pattern }
                importantCustomWildcards = importantCustomWildcards.filterNot { it.pattern == pattern }
            } else {
                if (pattern in customRules) {
                    customRules = HashSet(customRules).apply { remove(pattern) }
                }
                if (pattern in importantCustomRules) {
                    importantCustomRules = HashSet(importantCustomRules).apply { remove(pattern) }
                }
            }
        }
    }

    suspend fun reloadCustomRules(dao: AllowRuleDao) {
        val customRuleEntries = dao.enabledCustomRules()

        val custom = HashSet<String>()
        val importantCustom = HashSet<String>()
        val customWc = mutableListOf<AdGuardRuleParser.WildcardPattern>()
        val importantCustomWc = mutableListOf<AdGuardRuleParser.WildcardPattern>()
        val customBucketsMap = HashMap<String, MutableAllowAppBucket>()
        val customInvertedList = mutableListOf<InvertedAllowRule>()

        for (entry in customRuleEntries) {
            val isWc = entry.isWildcard || entry.pattern.contains('*')
            val wcPattern = if (isWc) AdGuardRuleParser.WildcardPattern(entry.pattern) else null

            if (entry.appInverted && !entry.appScope.isNullOrEmpty()) {
                val excluded = entry.appScope.split('|').map { it.trim().lowercase() }.filter { it.isNotEmpty() }.toSet()
                customInvertedList.add(InvertedAllowRule(entry.pattern, entry.important, excluded, wcPattern))
            } else if (!entry.appScope.isNullOrEmpty()) {
                val pkgs = entry.appScope.split('|').map { it.trim().lowercase() }.filter { it.isNotEmpty() }
                for (pkg in pkgs) {
                    val bucket = customBucketsMap.getOrPut(pkg) { MutableAllowAppBucket() }
                    if (isWc && wcPattern != null) {
                        if (entry.important) bucket.importantWildcards.add(wcPattern)
                        else bucket.wildcards.add(wcPattern)
                    } else {
                        if (entry.important) bucket.importantExact.add(entry.pattern)
                        else bucket.exact.add(entry.pattern)
                    }
                }
            } else {
                if (isWc && wcPattern != null) {
                    if (entry.important) importantCustomWc.add(wcPattern)
                    else customWc.add(wcPattern)
                } else {
                    if (entry.important) importantCustom.add(entry.pattern)
                    else custom.add(entry.pattern)
                }
            }
        }

        synchronized(this) {
            customRules = custom
            importantCustomRules = importantCustom
            customWildcards = customWc
            importantCustomWildcards = importantCustomWc
            customAppBuckets = customBucketsMap.mapValues { it.value.toImmutable() }
            invertedCustomRules = customInvertedList
        }
    }

    fun syncPattern(pattern: String, source: String?) {
        synchronized(this) {
            if (pattern == "*" || pattern.contains('*')) {
                val wp = AdGuardRuleParser.WildcardPattern(pattern)
                customWildcards = customWildcards.filterNot { it.pattern == pattern }
                subscriptionWildcards = subscriptionWildcards.filterNot { it.pattern == pattern }
                importantSubscriptionWildcards = importantSubscriptionWildcards.filterNot { it.pattern == pattern }
                if (source != null) {
                    if (source.startsWith("sub_")) {
                        subscriptionWildcards = subscriptionWildcards + wp
                    } else {
                        customWildcards = customWildcards + wp
                    }
                }
            } else {
                customRules = HashSet(customRules).apply {
                    remove(pattern)
                    if (source != null && !source.startsWith("sub_")) add(pattern)
                }
                subscriptionOverrides = HashMap(subscriptionOverrides).apply {
                    if (source == null) put(pattern, null)
                    else if (source.startsWith("sub_")) put(pattern, pattern)
                    else remove(pattern)
                }
            }
        }
    }

    fun clear() {
        synchronized(this) {
            customRules = emptySet()
            importantCustomRules = emptySet()
            customWildcards = emptyList()
            importantCustomWildcards = emptyList()
            customAppBuckets = emptyMap()
            invertedCustomRules = emptyList()

            subscriptionFallback = emptySet()
            importantSubscriptionFallback = emptySet()
            subscriptionWildcards = emptyList()
            importantSubscriptionWildcards = emptyList()
            subscriptionAppBuckets = emptyMap()
            invertedSubscriptionRules = emptyList()

            subscriptionOverrides = emptyMap()
            subscriptionIndex?.close()
            importantSubscriptionIndex?.close()
            subscriptionIndex = null
            importantSubscriptionIndex = null
        }
    }

    fun exportSnapshot(): ExportedAllowSnapshot {
        val globalAllow = LinkedHashSet<String>()

        globalAllow.addAll(customRules)
        customWildcards.forEach { globalAllow.add(it.pattern) }
        globalAllow.addAll(importantCustomRules)
        importantCustomWildcards.forEach { globalAllow.add(it.pattern) }
        globalAllow.addAll(subscriptionFallback)
        subscriptionWildcards.forEach { globalAllow.add(it.pattern) }
        globalAllow.addAll(importantSubscriptionFallback)
        importantSubscriptionWildcards.forEach { globalAllow.add(it.pattern) }

        val appPkgs = customAppBuckets.keys + subscriptionAppBuckets.keys
        val appRulesMap = HashMap<String, List<String>>()
        for (pkg in appPkgs) {
            val cBucket = customAppBuckets[pkg]
            val sBucket = subscriptionAppBuckets[pkg]
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
        for (rule in invertedCustomRules) {
            inverted.add(ExportedInvertedAllowRule(rule.pattern, rule.excludedApps))
        }
        for (rule in invertedSubscriptionRules) {
            inverted.add(ExportedInvertedAllowRule(rule.pattern, rule.excludedApps))
        }

        return ExportedAllowSnapshot(
            globalAllow = globalAllow.toList(),
            appRules = appRulesMap,
            invertedRules = inverted
        )
    }
}

data class ExportedAllowSnapshot(
    val globalAllow: List<String>,
    val appRules: Map<String, List<String>>,
    val invertedRules: List<ExportedInvertedAllowRule>
)

data class ExportedInvertedAllowRule(
    val pattern: String,
    val excludedApps: Set<String>
)

private class MutableAllowAppBucket {
    val exact = HashSet<String>()
    val importantExact = HashSet<String>()
    val wildcards = mutableListOf<AdGuardRuleParser.WildcardPattern>()
    val importantWildcards = mutableListOf<AdGuardRuleParser.WildcardPattern>()

    fun toImmutable(): AllowAppRuleBucket = AllowAppRuleBucket(
        exactRules = exact,
        importantExactRules = importantExact,
        wildcardRules = wildcards,
        importantWildcardRules = importantWildcards
    )
}

private suspend fun AllowRuleDao.forEachSubscriptionRulePage(
    consume: (com.haoze.dnssr.data.dao.EnabledBlockRule) -> Unit
) = forEachKeysetPage(
    ALLOW_INDEX_PAGE_SIZE,
    { lastId, limit -> enabledSubscriptionRulesPageKeyset(limit, lastId) },
    { it.id },
    { consume(it.toEnabledBlockRule()) }
)

private const val TAG = "AllowRuleCache"
private const val ALLOW_INDEX_PAGE_SIZE = 2_000
