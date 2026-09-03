package com.haoze.dnssr.vpn

import com.haoze.dnssr.data.dao.BlockRuleDao
import com.haoze.dnssr.data.entity.BlockRuleEntity
import com.haoze.dnssr.data.entity.RuleScope
import java.io.File

/**
 * AdGuard 风格屏蔽规则管理器。
 *
 * 支持添加的格式（通过 AdGuardRuleParser 解析）：
 * - ||example.com^ 或 ||example.com
 * - example.com
 * - 0.0.0.0 example.com / 127.0.0.1 example.com
 *
 * 性能优化：
 * - 使用 BlockRuleCache 内存 HashSet 缓存，isBlocked() 从 O(N) 降至 O(domain标签数)
 * - VPN 启动时全量加载缓存，规则变更时增量更新
 */
class BlockListManager(
    private val dao: BlockRuleDao,
    indexDirectory: File? = null,
    private val scope: RuleScope = RuleScope.DNS,
    private val reloadCacheAfterChanges: Boolean = true
) {

    private val cache = BlockRuleCache(indexDirectory?.let { File(it, "subscription-block.trie") })
    var onCacheChanged: (() -> Unit)? = null

    /**
     * 从数据库全量重载缓存。VPN 启动时或大批量操作后调用。
     */
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

    /**
     * O(domain标签数) 的屏蔽匹配。使用内存缓存，不查数据库。
     */
    fun isBlocked(qname: String, packageName: String? = null): Boolean {
        return cache.findMatch(qname, packageName) != null
    }

    fun findMatch(qname: String, packageName: String? = null): BlockRuleMatch? {
        return cache.findMatch(qname, packageName)
    }

    fun findCustomMatch(qname: String, packageName: String? = null): BlockRuleMatch? = cache.findCustomMatch(qname, packageName)
    fun findSubscriptionMatch(qname: String, packageName: String? = null): BlockRuleMatch? = cache.findSubscriptionMatch(qname, packageName)
    fun findImportantCustomMatch(qname: String, packageName: String? = null): BlockRuleMatch? = cache.findImportantCustomMatch(qname, packageName)
    fun findImportantSubscriptionMatch(qname: String, packageName: String? = null): BlockRuleMatch? = cache.findImportantSubscriptionMatch(qname, packageName)

    fun findAppImportantMatch(qname: String, packageName: String): BlockRuleMatch? = cache.findAppImportantMatch(qname, packageName)
    fun findGlobalImportantMatch(qname: String, packageName: String? = null): BlockRuleMatch? = cache.findGlobalImportantMatch(qname, packageName)
    fun findAppMatch(qname: String, packageName: String): BlockRuleMatch? = cache.findAppMatch(qname, packageName)
    fun findGlobalMatch(qname: String, packageName: String? = null): BlockRuleMatch? = cache.findGlobalMatch(qname, packageName)

    fun exportSnapshot(): ExportedBlockSnapshot = cache.exportSnapshot()

    suspend fun allRules(): List<BlockRuleEntity> = dao.all()

    /**
     * 添加单条规则（支持 AdGuard 格式自动解析）。
     */
    suspend fun addRule(pattern: String): Boolean {
        val parsed = AdGuardRuleParser.parseLine(pattern) ?: return false
        val inserted = dao.insertForSource(
            BlockRuleEntity(
                pattern = parsed.pattern,
                rawLine = parsed.rawLine,
                addedAt = System.currentTimeMillis(),
                enabled = true,
                groupName = null,
                important = parsed.important,
                appScope = parsed.appScope,
                appInverted = parsed.appInverted,
                isWildcard = parsed.isWildcard
            ),
            source = "useradd",
            sourceEnabled = true
        )
        if (!inserted) return false
        syncCachedPattern(parsed.pattern)
        return true
    }

    /**
     * 批量导入规则（用于订阅导入）。
     * @param rules 已解析的规则列表
     * @param source 来源标识（如 "sub_1"）
     * @param chunkSize 分块大小
     * @param onProgress 进度回调 (已导入数)
     */
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
                BlockRuleEntity(
                    pattern = rule.pattern,
                    rawLine = rule.rawLine,
                    addedAt = now,
                    enabled = true,
                    groupName = null,
                    important = rule.important,
                    appScope = rule.appScope,
                    appInverted = rule.appInverted,
                    isWildcard = rule.isWildcard
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
            BlockRuleEntity(
                pattern = rule.pattern,
                rawLine = rule.rawLine,
                addedAt = now,
                important = rule.important,
                appScope = rule.appScope,
                appInverted = rule.appInverted,
                isWildcard = rule.isWildcard
            )
        }, enabled, onProgress = onProgress)
        refreshCacheAfterChange()
    }

    suspend fun userRules(): List<BlockRuleEntity> = dao.all()

    suspend fun deleteRule(id: Long): String? {
        val pattern = dao.patternById(id) ?: return null
        dao.deleteById(id)
        syncCachedPattern(pattern)
        return pattern
    }

    suspend fun toggleRule(id: Long, enabled: Boolean): String? {
        val pattern = dao.patternById(id) ?: return null
        dao.setEnabled(id, enabled)
        if (enabled) {
            dao.setSourceEnabledByRuleId(id, true)
        }
        syncCachedPattern(pattern)
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

    /**
     * 按 source 删除规则（用于删除订阅的所有规则）。
     */
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
        cache.syncCustomPattern(
            normalized,
            dao.enabledRuleByPattern(normalized, important = false)?.source,
            dao.enabledRuleByPattern(normalized, important = true)?.source
        )
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
