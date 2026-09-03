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
    var onCacheChanged: (() -> Unit)? = null

    suspend fun refreshCache(forceRebuild: Boolean = false) {
        cache.reload(dao, scope, forceRebuild)
        onCacheChanged?.invoke()
    }

    private suspend fun refreshCacheAfterChange() {
        if (reloadCacheAfterChanges) cache.reload(dao, scope, forceRebuild = true)
    }

    suspend fun refreshCacheAfterExternalChange() {
        refreshCacheAfterChange()
    }

    fun isAllowed(qname: String, packageName: String? = null): Boolean {
        return cache.isAllowed(qname, packageName)
    }

    fun findMatch(qname: String, packageName: String? = null): String? = cache.findMatch(qname, packageName)
    fun findCustomMatch(qname: String, packageName: String? = null): String? = cache.findCustomMatch(qname, packageName)
    fun findSubscriptionMatch(qname: String, packageName: String? = null): String? = cache.findSubscriptionMatch(qname, packageName)
    fun findImportantCustomMatch(qname: String, packageName: String? = null): String? = cache.findImportantCustomMatch(qname, packageName)
    fun findImportantSubscriptionMatch(qname: String, packageName: String? = null): String? = cache.findImportantSubscriptionMatch(qname, packageName)

    fun findAppMatch(qname: String, packageName: String): String? = cache.findAppMatch(qname, packageName)
    fun findGlobalMatch(qname: String, packageName: String? = null): String? = cache.findGlobalMatch(qname, packageName)

    fun exportSnapshot(): ExportedAllowSnapshot = cache.exportSnapshot()

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
                appScope = parsed.appScope,
                appInverted = parsed.appInverted,
                isWildcard = parsed.isWildcard,
                important = parsed.important
            ),
            source = "useradd",
            sourceEnabled = true
        )
        if (!inserted) return false
        cache.syncPattern(parsed.pattern, dao.enabledRuleByPattern(parsed.pattern)?.source)
        return true
    }

    suspend fun addRulesBatch(
        rules: List<AdGuardRuleParser.ParsedRule>,
        source: String,
        chunkSize: Int = 500,
        enabled: Boolean = true,
        refreshCache: Boolean = true,
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
                    appScope = rule.appScope,
                    appInverted = rule.appInverted,
                    isWildcard = rule.isWildcard,
                    important = rule.important
                )
            }
            inserted += dao.insertAllForSource(entities, source, enabled)
            imported += chunk.size
            onProgress?.invoke(imported)
        }
        if (refreshCache) {
            refreshCacheAfterChange()
        }
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
            AllowRuleEntity(
                pattern = rule.pattern,
                rawLine = rule.rawLine,
                addedAt = now,
                appScope = rule.appScope,
                appInverted = rule.appInverted,
                isWildcard = rule.isWildcard,
                important = rule.important
            )
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
        if (enabled) {
            dao.setSourceEnabledByRuleId(id, true)
        }
        cache.syncPattern(pattern, dao.enabledRuleByPattern(pattern)?.source)
        return pattern
    }

    suspend fun setRulesEnabledBySource(source: String, enabled: Boolean) {
        dao.setEnabledBySource(source, enabled)
        refreshCacheAfterChange()
    }

    suspend fun count(): Int = dao.count()

    suspend fun clearAll() {
        dao.clearAll()
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
    suspend fun enabledCountBySource(source: String): Int = dao.enabledCountBySource(source)
    suspend fun enabledPatternsCount(): Int = dao.enabledPatternsCount()
    suspend fun enabledPatterns(): List<String> = dao.enabledPatterns()

    suspend fun syncCachedPattern(pattern: String) {
        val normalized = pattern.lowercase().trimEnd('.')
        cache.syncPattern(normalized, dao.enabledRuleByPattern(normalized)?.source)
        onCacheChanged?.invoke()
    }

    suspend fun parsedRulesBySource(source: String): List<AdGuardRuleParser.ParsedRule> =
        dao.bySource(source).map {
            AdGuardRuleParser.ParsedRule(
                pattern = it.pattern,
                rawLine = it.rawLine,
                important = it.important,
                appScope = it.appScope,
                appInverted = it.appInverted,
                isWildcard = it.isWildcard
            )
        }
}
