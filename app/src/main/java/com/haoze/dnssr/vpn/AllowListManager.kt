package com.haoze.dnssr.vpn

import com.haoze.dnssr.data.dao.AllowRuleDao
import com.haoze.dnssr.data.entity.AllowRuleEntity
import com.haoze.dnssr.data.entity.RuleScope
import java.io.File

/**
 * DNS 白名单规则管理器。
 *
 * 白名单命中时会绕过本应用的屏蔽规则，但仍继续走所选加密 DNS 上游解析。
 */
class AllowListManager(
    private val dao: AllowRuleDao,
    indexDirectory: File? = null,
    private val scope: RuleScope = RuleScope.DNS,
    private val reloadCacheAfterChanges: Boolean = true
) {

    private val cache = AllowRuleCache(indexDirectory?.let { File(it, "subscription-allow.trie") })

    suspend fun refreshCache() {
        cache.reload(dao, scope)
    }

    private suspend fun refreshCacheAfterChange() {
        if (reloadCacheAfterChanges) cache.reload(dao, scope)
    }

    suspend fun refreshCacheAfterExternalChange() {
        refreshCacheAfterChange()
    }

    fun isAllowed(qname: String): Boolean {
        return cache.isAllowed(qname)
    }

    fun findMatch(qname: String): String? = cache.findMatch(qname)
    fun findCustomMatch(qname: String): String? = cache.findCustomMatch(qname)
    fun findSubscriptionMatch(qname: String): String? = cache.findSubscriptionMatch(qname)

    suspend fun allRules(): List<AllowRuleEntity> = dao.all()

    suspend fun addRule(pattern: String): Boolean {
        val parsed = AdGuardRuleParser.parseAllowLine(pattern) ?: return false
        val inserted = dao.insertForSource(
            AllowRuleEntity(
                pattern = parsed.pattern,
                rawLine = parsed.rawLine,
                addedAt = System.currentTimeMillis(),
                enabled = true,
                groupName = null,
                scope = scope.storageValue
            ),
            source = "useradd",
            sourceEnabled = true
        )
        if (!inserted) return false
        cache.syncPattern(parsed.pattern, dao.enabledRuleByPattern(parsed.pattern, scope.storageValue)?.source)
        return true
    }

    suspend fun addRulesBatch(
        rules: List<AdGuardRuleParser.ParsedRule>,
        source: String,
        chunkSize: Int = 500,
        enabled: Boolean = true,
        onProgress: ((Int) -> Unit)? = null
    ): Int {
        val now = System.currentTimeMillis()
        var imported = 0
        var inserted = 0
        rules.chunked(chunkSize).forEach { chunk ->
            val entities = chunk.map { rule ->
                AllowRuleEntity(
                    pattern = rule.pattern,
                    rawLine = rule.rawLine,
                    addedAt = now,
                    enabled = true,
                    groupName = null,
                    scope = scope.storageValue
                )
            }
            inserted += dao.insertAllForSource(entities, source, enabled)
            imported += chunk.size
            onProgress?.invoke(imported)
        }
        refreshCacheAfterChange()
        return inserted
    }

    suspend fun replaceRulesBySource(
        rules: List<AdGuardRuleParser.ParsedRule>,
        source: String,
        enabled: Boolean,
        onProgress: ((Int) -> Unit)? = null
    ) {
        val now = System.currentTimeMillis()
        dao.replaceBySource(source, rules.map { rule ->
            AllowRuleEntity(pattern = rule.pattern, rawLine = rule.rawLine, addedAt = now, scope = scope.storageValue)
        }, enabled, onProgress = onProgress)
        refreshCacheAfterChange()
    }

    suspend fun deleteRule(id: Long): String? {
        val pattern = dao.patternById(id) ?: return null
        dao.deleteById(id)
        cache.syncPattern(pattern, null)
        return pattern
    }

    suspend fun toggleRule(id: Long, enabled: Boolean): String? {
        val pattern = dao.patternById(id) ?: return null
        dao.setEnabled(id, enabled)
        cache.syncPattern(pattern, dao.enabledRuleByPattern(pattern, scope.storageValue)?.source)
        return pattern
    }

    suspend fun setRulesEnabledBySource(source: String, enabled: Boolean) {
        dao.setEnabledBySource(source, enabled)
        refreshCacheAfterChange()
    }

    suspend fun count(): Int = dao.count(scope.storageValue)

    suspend fun clearAll() {
        dao.clearAll(scope.storageValue)
        cache.clear()
    }

    suspend fun removeRulesBySource(source: String) {
        dao.deleteBySource(source)
        refreshCacheAfterChange()
    }

    suspend fun promoteRulesBySource(
        stagingSource: String,
        targetSource: String,
        refreshCache: Boolean = true
    ) {
        dao.replaceSource(stagingSource, targetSource)
        if (refreshCache) refreshCacheAfterChange()
    }

    suspend fun countBySource(source: String): Int = dao.countBySource(source)

    suspend fun syncCachedPattern(pattern: String) {
        val normalized = pattern.lowercase().trimEnd('.')
        cache.syncPattern(normalized, dao.enabledRuleByPattern(normalized, scope.storageValue)?.source)
    }

    suspend fun parsedRulesBySource(source: String): List<AdGuardRuleParser.ParsedRule> =
        dao.bySource(source).map { AdGuardRuleParser.ParsedRule(it.pattern, it.rawLine) }
}
