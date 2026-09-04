package com.haoze.dnssr.vpn

import android.util.Log
import com.haoze.dnssr.util.forEachKeysetPage
import com.haoze.dnssr.data.dao.BlockRuleDao
import com.haoze.dnssr.data.entity.RuleScope
import java.io.File

/**
 * 屏蔽规则内存缓存。
 *
 * 将所有已启用规则加载到 HashSet 中，实现 O(domain标签数) 的快速匹配，
 * 替代每次 DNS 查询时的 O(N) 数据库全表扫描。
 *
 * 匹配逻辑：
 * - 精确匹配：domain == pattern
 * - 子域后缀匹配：domain.endsWith(".$pattern")
 *   通过分解 domain 的所有后缀逐级查找实现
 */
data class BlockRuleMatch(
    val pattern: String,
    val source: String
)

data class InvertedBlockRule(
    val pattern: String,
    val source: String,
    val important: Boolean,
    val excludedApps: Set<String>,
    val wildcard: AdGuardRuleParser.WildcardPattern? = null
)

data class BlockAppRuleBucket(
    val exactRules: Map<String, String> = emptyMap(),
    val importantExactRules: Map<String, String> = emptyMap(),
    val wildcardRules: List<Pair<AdGuardRuleParser.WildcardPattern, String>> = emptyList(),
    val importantWildcardRules: List<Pair<AdGuardRuleParser.WildcardPattern, String>> = emptyList()
) {
    fun isEmpty(): Boolean = exactRules.isEmpty() && importantExactRules.isEmpty() &&
        wildcardRules.isEmpty() && importantWildcardRules.isEmpty()
}

class BlockRuleCache(private val indexFile: File? = null) {

    @Volatile
    private var customRules: Map<String, String> = emptyMap()
    @Volatile
    private var importantCustomRules: Map<String, String> = emptyMap()
    @Volatile
    private var customWildcards: List<Pair<AdGuardRuleParser.WildcardPattern, String>> = emptyList()
    @Volatile
    private var importantCustomWildcards: List<Pair<AdGuardRuleParser.WildcardPattern, String>> = emptyList()

    @Volatile
    private var customAppBuckets: Map<String, BlockAppRuleBucket> = emptyMap()
    @Volatile
    private var invertedCustomRules: List<InvertedBlockRule> = emptyList()

    @Volatile
    private var subscriptionFallback: Map<String, String> = emptyMap()
    @Volatile
    private var importantSubscriptionFallback: Map<String, String> = emptyMap()
    @Volatile
    private var subscriptionWildcards: List<Pair<AdGuardRuleParser.WildcardPattern, String>> = emptyList()
    @Volatile
    private var importantSubscriptionWildcards: List<Pair<AdGuardRuleParser.WildcardPattern, String>> = emptyList()

    @Volatile
    private var subscriptionAppBuckets: Map<String, BlockAppRuleBucket> = emptyMap()
    @Volatile
    private var invertedSubscriptionRules: List<InvertedBlockRule> = emptyList()

    @Volatile
    private var subscriptionOverrides: Map<String, String?> = emptyMap()
    @Volatile
    private var subscriptionIndex: MappedSubscriptionRuleIndex? = null
    @Volatile
    private var importantSubscriptionIndex: MappedSubscriptionRuleIndex? = null

    /**
     * 从数据库全量重载已启用规则到内存。
     */
    suspend fun reload(
        dao: BlockRuleDao,
        scope: RuleScope = RuleScope.DNS,
        forceRebuild: Boolean = false
    ) {
        val customRuleEntries = dao.enabledCustomRules()

        val custom = HashMap<String, String>()
        val importantCustom = HashMap<String, String>()
        val customWc = mutableListOf<Pair<AdGuardRuleParser.WildcardPattern, String>>()
        val importantCustomWc = mutableListOf<Pair<AdGuardRuleParser.WildcardPattern, String>>()
        val customBucketsMap = HashMap<String, MutableAppBucket>()
        val customInvertedList = mutableListOf<InvertedBlockRule>()

        for (entry in customRuleEntries) {
            val isWc = entry.isWildcard || entry.pattern.contains('*')
            val wcPattern = if (isWc) AdGuardRuleParser.WildcardPattern(entry.pattern) else null

            if (entry.appInverted && !entry.appScope.isNullOrEmpty()) {
                val excluded = entry.appScope.split('|').map { it.trim().lowercase() }.filter { it.isNotEmpty() }.toSet()
                customInvertedList.add(InvertedBlockRule(entry.pattern, entry.source, entry.important, excluded, wcPattern))
            } else if (!entry.appScope.isNullOrEmpty()) {
                val pkgs = entry.appScope.split('|').map { it.trim().lowercase() }.filter { it.isNotEmpty() }
                for (pkg in pkgs) {
                    val bucket = customBucketsMap.getOrPut(pkg) { MutableAppBucket() }
                    if (isWc && wcPattern != null) {
                        if (entry.important) bucket.importantWildcards.add(wcPattern to entry.source)
                        else bucket.wildcards.add(wcPattern to entry.source)
                    } else {
                        if (entry.important) bucket.importantExact[entry.pattern] = entry.source
                        else bucket.exact[entry.pattern] = entry.source
                    }
                }
            } else {
                if (isWc && wcPattern != null) {
                    if (entry.important) importantCustomWc.add(wcPattern to entry.source)
                    else customWc.add(wcPattern to entry.source)
                } else {
                    if (entry.important) importantCustom[entry.pattern] = entry.source
                    else custom[entry.pattern] = entry.source
                }
            }
        }

        val targetFile = indexFile
        val importantFile = targetFile?.let { File(it.parentFile, it.name + ".important") }

        var mapped = targetFile?.let { file ->
            if (!forceRebuild && file.exists() && file.length() > 0) {
                runCatching { MappedSubscriptionRuleIndex.load(file) }
                    .onFailure { Log.w(TAG, "Existing subscription block index invalid, will recompile", it) }
                    .getOrNull()
            } else null
        }

        var importantMapped = importantFile?.let { file ->
            if (!forceRebuild && file.exists() && file.length() > 0) {
                runCatching { MappedSubscriptionRuleIndex.load(file) }
                    .onFailure { Log.w(TAG, "Existing important subscription block index invalid, will recompile", it) }
                    .getOrNull()
            } else null
        }

        if (mapped == null) {
            mapped = targetFile?.let { file ->
                runCatching {
                    MappedSubscriptionRuleIndex.compileAndLoad(file) { consume ->
                        dao.forEachSubscriptionRulePage(important = false) { rule ->
                            if (!rule.isWildcard && !rule.pattern.contains('*') && rule.appScope.isNullOrEmpty() && !rule.appInverted) {
                                consume(rule)
                            }
                        }
                    }
                }.onFailure { e ->
                    Log.e(TAG, "Failed to compile subscription block index (${file.name})", e)
                }.getOrNull()
            }
        }

        if (importantMapped == null) {
            importantMapped = importantFile?.let { file ->
                runCatching {
                    MappedSubscriptionRuleIndex.compileAndLoad(file) { consume ->
                        dao.forEachSubscriptionRulePage(important = true) { rule ->
                            if (!rule.isWildcard && !rule.pattern.contains('*') && rule.appScope.isNullOrEmpty() && !rule.appInverted) {
                                consume(rule)
                            }
                        }
                    }
                }.onFailure { e ->
                    Log.e(TAG, "Failed to compile important subscription block index (${file.name})", e)
                }.getOrNull()
            }
        }

        val subFallback = HashMap<String, String>()
        val importantSubFallback = HashMap<String, String>()
        val subWc = mutableListOf<Pair<AdGuardRuleParser.WildcardPattern, String>>()
        val importantSubWc = mutableListOf<Pair<AdGuardRuleParser.WildcardPattern, String>>()
        val subBucketsMap = HashMap<String, MutableAppBucket>()
        val subInvertedList = mutableListOf<InvertedBlockRule>()

        fun processSubscriptionRule(entry: com.haoze.dnssr.data.dao.EnabledRule) {
            val isWc = entry.isWildcard || entry.pattern.contains('*')
            val wcPattern = if (isWc) AdGuardRuleParser.WildcardPattern(entry.pattern) else null

            if (entry.appInverted && !entry.appScope.isNullOrEmpty()) {
                val excluded = entry.appScope.split('|').map { it.trim().lowercase() }.filter { it.isNotEmpty() }.toSet()
                subInvertedList.add(InvertedBlockRule(entry.pattern, entry.source, entry.important, excluded, wcPattern))
            } else if (!entry.appScope.isNullOrEmpty()) {
                val pkgs = entry.appScope.split('|').map { it.trim().lowercase() }.filter { it.isNotEmpty() }
                for (pkg in pkgs) {
                    val bucket = subBucketsMap.getOrPut(pkg) { MutableAppBucket() }
                    if (isWc && wcPattern != null) {
                        if (entry.important) bucket.importantWildcards.add(wcPattern to entry.source)
                        else bucket.wildcards.add(wcPattern to entry.source)
                    } else {
                        if (entry.important) bucket.importantExact[entry.pattern] = entry.source
                        else bucket.exact[entry.pattern] = entry.source
                    }
                }
            } else if (isWc && wcPattern != null) {
                if (entry.important) importantSubWc.add(wcPattern to entry.source)
                else subWc.add(wcPattern to entry.source)
            } else {
                if (entry.important) {
                    if (importantMapped == null) importantSubFallback[entry.pattern] = entry.source
                } else {
                    if (mapped == null) subFallback[entry.pattern] = entry.source
                }
            }
        }

        if (mapped != null && importantMapped != null) {
            dao.enabledSpecialSubscriptionRules().forEach(::processSubscriptionRule)
        } else {
            dao.forEachSubscriptionRulePage(important = false, ::processSubscriptionRule)
            dao.forEachSubscriptionRulePage(important = true, ::processSubscriptionRule)
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

    /**
     * O(domain标签数) 匹配。
     */
    fun findMatch(qname: String, packageName: String? = null): BlockRuleMatch? {
        return findImportantCustomMatch(qname, packageName)
            ?: findImportantSubscriptionMatch(qname, packageName)
            ?: findCustomMatch(qname, packageName)
            ?: findSubscriptionMatch(qname, packageName)
    }

    /**
     * App 专用 $important 屏蔽规则匹配（优先级 1）
     */
    fun findAppImportantMatch(qname: String, packageName: String): BlockRuleMatch? {
        val domain = qname.lowercase().trimEnd('.')
        if (domain.isEmpty() || packageName.isEmpty()) return null

        findInAppBucket(customAppBuckets, packageName, domain, important = true)?.let { return it }
        findInAppBucket(subscriptionAppBuckets, packageName, domain, important = true)?.let { return it }

        return null
    }

    /**
     * 全局 $important 屏蔽规则匹配（优先级 2）
     */
    fun findGlobalImportantMatch(qname: String, packageName: String? = null): BlockRuleMatch? {
        val domain = qname.lowercase().trimEnd('.')
        if (domain.isEmpty()) return null

        findInInvertedRules(invertedCustomRules, domain, important = true, packageName)?.let { return it }

        findInMap(domain, importantCustomRules)?.let { return it }
        findInWildcards(domain, importantCustomWildcards)?.let { return it }

        findInInvertedRules(invertedSubscriptionRules, domain, important = true, packageName)?.let { return it }

        return findSubscriptionTail(domain, important = true)
    }

    /**
     * App 专用常规屏蔽规则匹配（优先级 5，包含 *$app=pkg 全阻断）
     */
    fun findAppMatch(qname: String, packageName: String): BlockRuleMatch? {
        val domain = qname.lowercase().trimEnd('.')
        if (domain.isEmpty() || packageName.isEmpty()) return null

        findInAppBucket(customAppBuckets, packageName, domain, important = false)?.let { return it }
        findInAppBucket(subscriptionAppBuckets, packageName, domain, important = false)?.let { return it }

        return null
    }

    /**
     * 全局常规屏蔽规则匹配（优先级 6）
     */
    fun findGlobalMatch(qname: String, packageName: String? = null): BlockRuleMatch? {
        val domain = qname.lowercase().trimEnd('.')
        if (domain.isEmpty()) return null

        findInInvertedRules(invertedCustomRules, domain, important = false, packageName)?.let { return it }

        findInMap(domain, customRules)?.let { return it }
        findInWildcards(domain, customWildcards)?.let { return it }

        findInInvertedRules(invertedSubscriptionRules, domain, important = false, packageName)?.let { return it }

        return findSubscriptionTail(domain, important = false)
    }

    fun findCustomMatch(qname: String, packageName: String? = null): BlockRuleMatch? {
        val domain = qname.lowercase().trimEnd('.')
        if (domain.isEmpty()) return null

        findInAppBucket(customAppBuckets, packageName, domain, important = false)?.let { return it }

        findInInvertedRules(invertedCustomRules, domain, important = false, packageName)?.let { return it }

        return findInMap(domain, customRules) ?: findInWildcards(domain, customWildcards)
    }

    fun findImportantCustomMatch(qname: String, packageName: String? = null): BlockRuleMatch? {
        val domain = qname.lowercase().trimEnd('.')
        if (domain.isEmpty()) return null

        findInAppBucket(customAppBuckets, packageName, domain, important = true)?.let { return it }

        findInInvertedRules(invertedCustomRules, domain, important = true, packageName)?.let { return it }

        return findInMap(domain, importantCustomRules) ?: findInWildcards(domain, importantCustomWildcards)
    }

    fun findSubscriptionMatch(qname: String, packageName: String? = null): BlockRuleMatch? {
        val domain = qname.lowercase().trimEnd('.')
        if (domain.isEmpty()) return null

        findInAppBucket(subscriptionAppBuckets, packageName, domain, important = false)?.let { return it }

        findInInvertedRules(invertedSubscriptionRules, domain, important = false, packageName)?.let { return it }

        return findSubscriptionTail(domain, important = false)
    }

    fun findImportantSubscriptionMatch(qname: String, packageName: String? = null): BlockRuleMatch? {
        val domain = qname.lowercase().trimEnd('.')
        if (domain.isEmpty()) return null

        findInAppBucket(subscriptionAppBuckets, packageName, domain, important = true)?.let { return it }

        findInInvertedRules(invertedSubscriptionRules, domain, important = true, packageName)?.let { return it }

        return findSubscriptionTail(domain, important = true)
    }

    /** 在指定应用的规则桶内按 精确→通配符 顺序匹配。 */
    private fun findInAppBucket(
        buckets: Map<String, BlockAppRuleBucket>,
        packageName: String?,
        domain: String,
        important: Boolean
    ): BlockRuleMatch? {
        val bucket = packageName?.let { buckets[it] } ?: return null
        val exact = if (important) bucket.importantExactRules else bucket.exactRules
        val wildcards = if (important) bucket.importantWildcardRules else bucket.wildcardRules
        return findInMap(domain, exact) ?: findInWildcards(domain, wildcards)
    }

    /** 匹配倒排规则（排除应用名单），可按重要/常规过滤。 */
    private fun findInInvertedRules(
        rules: List<InvertedBlockRule>,
        domain: String,
        important: Boolean,
        packageName: String?
    ): BlockRuleMatch? {
        for (rule in rules) {
            if (rule.important == important && (packageName == null || packageName !in rule.excludedApps)) {
                if (rule.wildcard != null && rule.wildcard.matches(domain)) {
                    return BlockRuleMatch(rule.pattern, rule.source)
                } else if (rule.wildcard == null && matchesDomainOrSuffix(domain, rule.pattern)) {
                    return BlockRuleMatch(rule.pattern, rule.source)
                }
            }
        }
        return null
    }

    /** 订阅 mmap 索引优先、内存 fallback 兜底的精确匹配 + 通配符兜底。 */
    private fun findSubscriptionTail(domain: String, important: Boolean): BlockRuleMatch? {
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
        subscriptions: Map<String, String>
    ): BlockRuleMatch? {
        index?.find(domain, subscriptionOverrides)?.let { source -> return BlockRuleMatch(domain, source) }
        fun sourceFor(pattern: String): String? = if (subscriptionOverrides.containsKey(pattern)) {
            subscriptionOverrides[pattern]
        } else {
            subscriptions[pattern]
        }
        return firstDomainSuffixHit(domain) { suffix ->
            sourceFor(suffix)?.let { source -> BlockRuleMatch(suffix, source) }
        }
    }

    private fun findInMap(domain: String, rules: Map<String, String>): BlockRuleMatch? =
        firstDomainSuffixHit(domain) { suffix ->
            rules[suffix]?.let { source -> BlockRuleMatch(pattern = suffix, source = source) }
        }

    private fun findInWildcards(
        domain: String,
        wildcards: List<Pair<AdGuardRuleParser.WildcardPattern, String>>
    ): BlockRuleMatch? =
        findWildcardHit(domain, wildcards) { it.first }?.let { (wp, source) -> BlockRuleMatch(wp.pattern, source) }

    fun addPattern(pattern: String, source: String) {
        synchronized(this) {
            if (pattern == "*" || pattern.contains('*')) {
                val wp = AdGuardRuleParser.WildcardPattern(pattern)
                customWildcards = customWildcards.filterNot { it.first.pattern == pattern } + (wp to source)
            } else {
                customRules = HashMap(customRules).apply { put(pattern, source) }
            }
        }
    }

    fun removePattern(pattern: String) {
        synchronized(this) {
            if (pattern == "*" || pattern.contains('*')) {
                customWildcards = customWildcards.filterNot { it.first.pattern == pattern }
                importantCustomWildcards = importantCustomWildcards.filterNot { it.first.pattern == pattern }
            } else {
                if (pattern in customRules) {
                    customRules = HashMap(customRules).apply { remove(pattern) }
                }
                if (pattern in importantCustomRules) {
                    importantCustomRules = HashMap(importantCustomRules).apply { remove(pattern) }
                }
            }
        }
    }

    fun syncPattern(pattern: String, source: String?) {
        synchronized(this) {
            if (pattern == "*" || pattern.contains('*')) {
                val wp = AdGuardRuleParser.WildcardPattern(pattern)
                customWildcards = customWildcards.filterNot { it.first.pattern == pattern }
                if (source != null && !source.startsWith("sub_")) {
                    customWildcards = customWildcards + (wp to source)
                }
            } else {
                customRules = HashMap(customRules).apply {
                    remove(pattern)
                    if (source != null && !source.startsWith("sub_")) put(pattern, source)
                }
                subscriptionOverrides = HashMap(subscriptionOverrides).apply {
                    if (source == null || source.startsWith("sub_")) put(pattern, source) else remove(pattern)
                }
            }
        }
    }

    suspend fun reloadCustomRules(dao: BlockRuleDao) {
        val customRuleEntries = dao.enabledCustomRules()

        val custom = HashMap<String, String>()
        val importantCustom = HashMap<String, String>()
        val customWc = mutableListOf<Pair<AdGuardRuleParser.WildcardPattern, String>>()
        val importantCustomWc = mutableListOf<Pair<AdGuardRuleParser.WildcardPattern, String>>()
        val customBucketsMap = HashMap<String, MutableAppBucket>()
        val customInvertedList = mutableListOf<InvertedBlockRule>()

        for (entry in customRuleEntries) {
            val isWc = entry.isWildcard || entry.pattern.contains('*')
            val wcPattern = if (isWc) AdGuardRuleParser.WildcardPattern(entry.pattern) else null

            if (entry.appInverted && !entry.appScope.isNullOrEmpty()) {
                val excluded = entry.appScope.split('|').map { it.trim().lowercase() }.filter { it.isNotEmpty() }.toSet()
                customInvertedList.add(InvertedBlockRule(entry.pattern, entry.source, entry.important, excluded, wcPattern))
            } else if (!entry.appScope.isNullOrEmpty()) {
                val pkgs = entry.appScope.split('|').map { it.trim().lowercase() }.filter { it.isNotEmpty() }
                for (pkg in pkgs) {
                    val bucket = customBucketsMap.getOrPut(pkg) { MutableAppBucket() }
                    if (isWc && wcPattern != null) {
                        if (entry.important) bucket.importantWildcards.add(wcPattern to entry.source)
                        else bucket.wildcards.add(wcPattern to entry.source)
                    } else {
                        if (entry.important) bucket.importantExact[entry.pattern] = entry.source
                        else bucket.exact[entry.pattern] = entry.source
                    }
                }
            } else {
                if (isWc && wcPattern != null) {
                    if (entry.important) importantCustomWc.add(wcPattern to entry.source)
                    else customWc.add(wcPattern to entry.source)
                } else {
                    if (entry.important) importantCustom[entry.pattern] = entry.source
                    else custom[entry.pattern] = entry.source
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

    fun syncCustomPattern(
        pattern: String,
        source: String?,
        importantSource: String?,
        appScope: String? = null,
        appInverted: Boolean = false,
        isWildcard: Boolean = false
    ) {
        synchronized(this) {
            val isWc = isWildcard || pattern.contains('*')
            val wp = if (isWc) AdGuardRuleParser.WildcardPattern(pattern) else null

            if (isWc && wp != null) {
                customWildcards = customWildcards.filterNot { it.first.pattern == pattern }
                importantCustomWildcards = importantCustomWildcards.filterNot { it.first.pattern == pattern }
                subscriptionWildcards = subscriptionWildcards.filterNot { it.first.pattern == pattern }
                importantSubscriptionWildcards = importantSubscriptionWildcards.filterNot { it.first.pattern == pattern }

                if (source != null) {
                    if (source.startsWith("sub_")) {
                        subscriptionWildcards = subscriptionWildcards + (wp to source)
                    } else {
                        customWildcards = customWildcards + (wp to source)
                    }
                }
                if (importantSource != null) {
                    if (importantSource.startsWith("sub_")) {
                        importantSubscriptionWildcards = importantSubscriptionWildcards + (wp to importantSource)
                    } else {
                        importantCustomWildcards = importantCustomWildcards + (wp to importantSource)
                    }
                }
            } else {
                customRules = HashMap(customRules).apply {
                    remove(pattern)
                    if (source != null && !source.startsWith("sub_")) put(pattern, source)
                }
                importantCustomRules = HashMap(importantCustomRules).apply {
                    remove(pattern)
                    if (importantSource != null && !importantSource.startsWith("sub_")) {
                        put(pattern, importantSource)
                    }
                }
                subscriptionOverrides = HashMap(subscriptionOverrides).apply {
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
            }
        }
    }

    fun clear() {
        synchronized(this) {
            customRules = emptyMap()
            importantCustomRules = emptyMap()
            customWildcards = emptyList()
            importantCustomWildcards = emptyList()
            customAppBuckets = emptyMap()
            invertedCustomRules = emptyList()

            subscriptionFallback = emptyMap()
            importantSubscriptionFallback = emptyMap()
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

    fun exportSnapshot(): ExportedBlockSnapshot {
        val globalBlock = LinkedHashSet<String>()
        val globalImportant = LinkedHashSet<String>()

        globalBlock.addAll(customRules.keys)
        customWildcards.forEach { globalBlock.add(it.first.pattern) }
        globalBlock.addAll(subscriptionFallback.keys)
        subscriptionWildcards.forEach { globalBlock.add(it.first.pattern) }

        globalImportant.addAll(importantCustomRules.keys)
        importantCustomWildcards.forEach { globalImportant.add(it.first.pattern) }
        globalImportant.addAll(importantSubscriptionFallback.keys)
        importantSubscriptionWildcards.forEach { globalImportant.add(it.first.pattern) }

        val appPkgs = customAppBuckets.keys + subscriptionAppBuckets.keys
        val appRulesMap = HashMap<String, ExportedAppBlockRules>()
        for (pkg in appPkgs) {
            val cBucket = customAppBuckets[pkg]
            val sBucket = subscriptionAppBuckets[pkg]
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
        for (rule in invertedCustomRules) {
            inverted.add(ExportedInvertedRule(rule.pattern, rule.source, rule.important, rule.excludedApps))
        }
        for (rule in invertedSubscriptionRules) {
            inverted.add(ExportedInvertedRule(rule.pattern, rule.source, rule.important, rule.excludedApps))
        }

        return ExportedBlockSnapshot(
            globalBlock = globalBlock.toList(),
            globalImportant = globalImportant.toList(),
            appRules = appRulesMap,
            invertedRules = inverted
        )
    }

    fun size(): Int = customRules.size + importantCustomRules.size + customWildcards.size +
        importantCustomWildcards.size + subscriptionFallback.size + importantSubscriptionFallback.size +
        subscriptionWildcards.size + importantSubscriptionWildcards.size +
        customAppBuckets.values.sumOf { it.exactRules.size + it.importantExactRules.size + it.wildcardRules.size + it.importantWildcardRules.size } +
        subscriptionAppBuckets.values.sumOf { it.exactRules.size + it.importantExactRules.size + it.wildcardRules.size + it.importantWildcardRules.size }
}

data class ExportedBlockSnapshot(
    val globalBlock: List<String>,
    val globalImportant: List<String>,
    val appRules: Map<String, ExportedAppBlockRules>,
    val invertedRules: List<ExportedInvertedRule>
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

private class MutableAppBucket {
    val exact = HashMap<String, String>()
    val importantExact = HashMap<String, String>()
    val wildcards = mutableListOf<Pair<AdGuardRuleParser.WildcardPattern, String>>()
    val importantWildcards = mutableListOf<Pair<AdGuardRuleParser.WildcardPattern, String>>()

    fun toImmutable(): BlockAppRuleBucket = BlockAppRuleBucket(
        exactRules = exact,
        importantExactRules = importantExact,
        wildcardRules = wildcards,
        importantWildcardRules = importantWildcards
    )
}

private suspend fun BlockRuleDao.forEachSubscriptionRulePage(
    important: Boolean,
    consume: (com.haoze.dnssr.data.dao.EnabledRule) -> Unit
) = forEachKeysetPage(
    INDEX_PAGE_SIZE,
    { lastId, limit -> enabledSubscriptionRulesPageKeyset(important, limit, lastId) },
    { it.id },
    { consume(it.toEnabledRule()) }
)

private const val TAG = "BlockRuleCache"
private const val INDEX_PAGE_SIZE = 2_000
