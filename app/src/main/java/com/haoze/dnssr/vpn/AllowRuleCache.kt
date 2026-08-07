package com.haoze.dnssr.vpn

import com.haoze.dnssr.data.dao.AllowRuleDao
import com.haoze.dnssr.data.entity.RuleScope
import java.io.File

/**
 * 白名单规则内存缓存。
 *
 * 匹配逻辑与屏蔽规则一致：精确匹配或父域后缀匹配。
 */
class AllowRuleCache(private val indexFile: File? = null) {

    @Volatile
    private var customRules: Set<String> = emptySet()
    @Volatile
    private var subscriptionFallback: Set<String> = emptySet()
    @Volatile
    private var subscriptionOverrides: Map<String, String?> = emptyMap()
    @Volatile
    private var subscriptionIndex: MappedSubscriptionRuleIndex? = null

    suspend fun reload(dao: AllowRuleDao, scope: RuleScope) {
        val custom = dao.enabledCustomRules(scope.storageValue).mapTo(HashSet()) { it.pattern }
        val mapped = indexFile?.let { file ->
            runCatching {
                MappedSubscriptionRuleIndex.compileAndLoad(file) { consume ->
                    dao.forEachSubscriptionRulePage(scope.storageValue, consume)
                }
            }.getOrNull()
        }
        val fallback = if (mapped == null) dao.enabledSubscriptionRules(scope.storageValue)
            .mapTo(HashSet()) { it.pattern } else emptySet()
        synchronized(this) {
            subscriptionIndex?.close()
            customRules = custom
            subscriptionFallback = fallback
            subscriptionIndex = mapped
            subscriptionOverrides = emptyMap()
        }
    }

    fun isAllowed(qname: String): Boolean {
        return findMatch(qname) != null
    }

    fun findMatch(qname: String): String? {
        return findCustomMatch(qname) ?: findSubscriptionMatch(qname)
    }

    fun findCustomMatch(qname: String): String? {
        val domain = qname.lowercase().trimEnd('.')
        val rules = customRules
        if (rules.contains(domain)) return domain
        var pos = domain.indexOf('.')
        while (pos >= 0 && pos < domain.length - 1) {
            val suffix = domain.substring(pos + 1)
            if (rules.contains(suffix)) return suffix
            pos = domain.indexOf('.', pos + 1)
        }
        return null
    }

    fun findSubscriptionMatch(qname: String): String? {
        val domain = qname.lowercase().trimEnd('.')
        subscriptionIndex?.find(domain, subscriptionOverrides)?.let { return it }
        val subscriptions = subscriptionFallback
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

    fun addPattern(pattern: String) {
        synchronized(this) {
            customRules = HashSet(customRules).apply { add(pattern) }
        }
    }

    fun removePattern(pattern: String) {
        synchronized(this) {
            if (pattern !in customRules) return
            customRules = HashSet(customRules).apply { remove(pattern) }
        }
    }

    fun syncPattern(pattern: String, source: String?) {
        synchronized(this) {
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

    fun clear() {
        synchronized(this) {
            customRules = emptySet()
            subscriptionFallback = emptySet()
            subscriptionOverrides = emptyMap()
            subscriptionIndex?.close()
            subscriptionIndex = null
        }
    }
}

private suspend fun AllowRuleDao.forEachSubscriptionRulePage(
    scope: String,
    consume: (com.haoze.dnssr.data.dao.EnabledBlockRule) -> Unit
) {
    var offset = 0
    while (true) {
        val page = enabledSubscriptionRulesPage(scope, ALLOW_INDEX_PAGE_SIZE, offset)
        if (page.isEmpty()) return
        page.forEach(consume)
        offset += page.size
    }
}

private const val ALLOW_INDEX_PAGE_SIZE = 2_000
