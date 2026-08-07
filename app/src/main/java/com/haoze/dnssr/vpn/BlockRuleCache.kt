package com.haoze.dnssr.vpn

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

class BlockRuleCache(private val indexFile: File? = null) {

    @Volatile
    private var customRules: Map<String, String> = emptyMap()
    @Volatile
    private var importantCustomRules: Map<String, String> = emptyMap()
    @Volatile
    private var subscriptionFallback: Map<String, String> = emptyMap()
    @Volatile
    private var importantSubscriptionFallback: Map<String, String> = emptyMap()
    @Volatile
    private var subscriptionOverrides: Map<String, String?> = emptyMap()
    @Volatile
    private var subscriptionIndex: MappedSubscriptionRuleIndex? = null
    @Volatile
    private var importantSubscriptionIndex: MappedSubscriptionRuleIndex? = null

    /**
     * 从数据库全量重载已启用规则到内存。
     */
    suspend fun reload(dao: BlockRuleDao, scope: RuleScope) {
        val customRuleEntries = dao.enabledCustomRules(scope.storageValue)
        val custom = customRuleEntries.filterNot { it.important }.associate { it.pattern to it.source }
        val importantCustom = customRuleEntries.filter { it.important }.associate { it.pattern to it.source }
        val mapped = indexFile?.let { file ->
            runCatching {
                MappedSubscriptionRuleIndex.compileAndLoad(file) { consume ->
                    dao.forEachSubscriptionRulePage(scope.storageValue, important = false, consume)
                }
            }.getOrNull()
        }
        val importantMapped = indexFile?.let { file ->
            runCatching {
                MappedSubscriptionRuleIndex.compileAndLoad(File(file.parentFile, file.name + ".important")) { consume ->
                    dao.forEachSubscriptionRulePage(scope.storageValue, important = true, consume)
                }
            }.getOrNull()
        }
        val fallback = if (mapped == null) dao.enabledSubscriptionRules(scope.storageValue)
            .filterNot { it.important }.associate { it.pattern to it.source } else emptyMap()
        val importantFallback = if (importantMapped == null) dao.enabledSubscriptionRules(scope.storageValue)
            .filter { it.important }.associate { it.pattern to it.source } else emptyMap()
        synchronized(this) {
            subscriptionIndex?.close()
            importantSubscriptionIndex?.close()
            customRules = custom
            importantCustomRules = importantCustom
            subscriptionFallback = fallback
            importantSubscriptionFallback = importantFallback
            subscriptionIndex = mapped
            importantSubscriptionIndex = importantMapped
            subscriptionOverrides = emptyMap()
        }
    }

    /**
     * O(domain标签数) 匹配。
     * 例如 "ad.example.com" 依次检查：
     * "ad.example.com" → "example.com" → "com"
     */
    fun findMatch(qname: String): BlockRuleMatch? {
        return findCustomMatch(qname) ?: findSubscriptionMatch(qname)
    }

    fun findCustomMatch(qname: String): BlockRuleMatch? {
        return findInMap(qname, customRules)
    }

    fun findImportantCustomMatch(qname: String): BlockRuleMatch? = findInMap(qname, importantCustomRules)

    private fun findInMap(qname: String, rules: Map<String, String>): BlockRuleMatch? {
        val domain = qname.lowercase().trimEnd('.')
        rules[domain]?.let { source ->
            return BlockRuleMatch(pattern = domain, source = source)
        }
        var pos = domain.indexOf('.')
        while (pos >= 0 && pos < domain.length - 1) {
            val suffix = domain.substring(pos + 1)
            rules[suffix]?.let { source ->
                return BlockRuleMatch(pattern = suffix, source = source)
            }
            pos = domain.indexOf('.', pos + 1)
        }
        return null
    }

    fun findSubscriptionMatch(qname: String): BlockRuleMatch? {
        return findSubscriptionMatch(qname, subscriptionIndex, subscriptionFallback)
    }

    fun findImportantSubscriptionMatch(qname: String): BlockRuleMatch? =
        findSubscriptionMatch(qname, importantSubscriptionIndex, importantSubscriptionFallback)

    private fun findSubscriptionMatch(
        qname: String,
        index: MappedSubscriptionRuleIndex?,
        subscriptions: Map<String, String>
    ): BlockRuleMatch? {
        val domain = qname.lowercase().trimEnd('.')
        index?.find(domain)?.let { source -> return BlockRuleMatch(domain, source) }
        fun sourceFor(pattern: String): String? = if (subscriptionOverrides.containsKey(pattern)) {
            subscriptionOverrides[pattern]
        } else {
            subscriptions[pattern]
        }
        sourceFor(domain)?.let { source -> return BlockRuleMatch(domain, source) }
        var subscriptionPos = domain.indexOf('.')
        while (subscriptionPos >= 0 && subscriptionPos < domain.length - 1) {
            val suffix = domain.substring(subscriptionPos + 1)
            sourceFor(suffix)?.let { source -> return BlockRuleMatch(suffix, source) }
            subscriptionPos = domain.indexOf('.', subscriptionPos + 1)
        }
        return null
    }

    fun addPattern(pattern: String, source: String) {
        synchronized(this) {
            customRules = HashMap(customRules).apply { put(pattern, source) }
        }
    }

    fun removePattern(pattern: String) {
        synchronized(this) {
            if (pattern !in customRules) return
            customRules = HashMap(customRules).apply { remove(pattern) }
        }
    }

    fun syncPattern(pattern: String, source: String?) {
        synchronized(this) {
            customRules = HashMap(customRules).apply {
                remove(pattern)
                if (source != null && !source.startsWith("sub_")) put(pattern, source)
            }
            subscriptionOverrides = HashMap(subscriptionOverrides).apply {
                if (source == null || source.startsWith("sub_")) put(pattern, source) else remove(pattern)
            }
        }
    }

    fun syncCustomPattern(pattern: String, source: String?, importantSource: String?) {
        synchronized(this) {
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
        }
    }

    fun clear() {
        synchronized(this) {
            customRules = emptyMap()
            importantCustomRules = emptyMap()
            subscriptionFallback = emptyMap()
            importantSubscriptionFallback = emptyMap()
            subscriptionOverrides = emptyMap()
            subscriptionIndex?.close()
            importantSubscriptionIndex?.close()
            subscriptionIndex = null
            importantSubscriptionIndex = null
        }
    }

    fun size(): Int = customRules.size + importantCustomRules.size + subscriptionFallback.size + importantSubscriptionFallback.size
}

private suspend fun BlockRuleDao.forEachSubscriptionRulePage(
    scope: String,
    important: Boolean,
    consume: (com.haoze.dnssr.data.dao.EnabledBlockRule) -> Unit
) {
    var offset = 0
    while (true) {
        val page = enabledSubscriptionRulesPage(scope, important, INDEX_PAGE_SIZE, offset)
        if (page.isEmpty()) return
        page.forEach(consume)
        offset += page.size
    }
}

private const val INDEX_PAGE_SIZE = 2_000
