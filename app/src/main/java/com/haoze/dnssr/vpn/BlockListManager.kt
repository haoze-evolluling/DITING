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

    /**
     * 从数据库全量重载缓存。VPN 启动时或大批量操作后调用。
     */
    suspend fun refreshCache() {
        cache.reload(dao, scope)
    }

    private suspend fun refreshCacheAfterChange() {
        if (reloadCacheAfterChanges) cache.reload(dao, scope)
    }

    suspend fun refreshCacheAfterExternalChange() {
        refreshCacheAfterChange()
    }

    /**
     * O(domain标签数) 的屏蔽匹配。使用内存缓存，不查数据库。
     */
    fun isBlocked(qname: String): Boolean {
        return cache.findMatch(qname) != null
    }

    fun findMatch(qname: String): BlockRuleMatch? {
        return cache.findMatch(qname)
    }

    fun findCustomMatch(qname: String): BlockRuleMatch? = cache.findCustomMatch(qname)
    fun findSubscriptionMatch(qname: String): BlockRuleMatch? = cache.findSubscriptionMatch(qname)
    fun findImportantCustomMatch(qname: String): BlockRuleMatch? = cache.findImportantCustomMatch(qname)
    fun findImportantSubscriptionMatch(qname: String): BlockRuleMatch? = cache.findImportantSubscriptionMatch(qname)

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
                scope = scope.storageValue
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
                    scope = scope.storageValue
                )
            }
            inserted += dao.insertAllForSource(entities, source, enabled)
            imported += chunk.size
            onProgress?.invoke(imported)
        }
        // 批量导入后全量刷新缓存
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
            BlockRuleEntity(pattern = rule.pattern, rawLine = rule.rawLine, addedAt = now, important = rule.important, scope = scope.storageValue)
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
        syncCachedPattern(pattern)
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
            dao.enabledRuleByPattern(normalized, important = false, scope = scope.storageValue)?.source,
            dao.enabledRuleByPattern(normalized, important = true, scope = scope.storageValue)?.source
        )
    }

    suspend fun parsedRulesBySource(source: String): List<AdGuardRuleParser.ParsedRule> =
        dao.bySource(source).map { AdGuardRuleParser.ParsedRule(it.pattern, it.rawLine, it.important) }
}
