package com.haoze.dnssr.vpn

import com.haoze.dnssr.data.dao.RewriteRuleDao
import com.haoze.dnssr.data.entity.RewriteRuleEntity
import com.haoze.dnssr.data.entity.RewriteTargetType
import com.haoze.dnssr.data.entity.RuleScope
import java.io.File
import java.net.InetAddress

data class RewriteRule(val pattern: String, val targetType: String, val targetValue: String, val rawLine: String)
data class RewriteAnswer(val targetType: String, val targetValue: String)

class RewriteRuleManager(
    private val dao: RewriteRuleDao,
    private val indexDirectory: File? = null,
    private val scope: RuleScope = RuleScope.DNS,
    private val reloadCacheAfterChanges: Boolean = true
) : AutoCloseable {
    @Volatile private var manualRules: Map<String, Set<RewriteAnswer>> = emptyMap()
    @Volatile private var subscriptionFallbackRules: Map<String, Set<RewriteAnswer>> = emptyMap()
    @Volatile private var subscriptionIndex: MappedSubscriptionRewriteIndex? = null

    suspend fun refreshCache(rebuildSubscriptionIndex: Boolean = true) {
        manualRules = dao.enabledNonSubscriptionRules(scope.storageValue).toAnswerMap()
        if (!rebuildSubscriptionIndex) return

        subscriptionIndex?.close()
        subscriptionIndex = null
        val mapped = indexDirectory?.let { directory ->
            runCatching {
                MappedSubscriptionRewriteIndex.compileAndLoad(File(directory, indexFileName())) { consume ->
                    dao.forEachSubscriptionRulePage(scope.storageValue, consume)
                }
            }.getOrNull()
        }
        subscriptionIndex = mapped
        subscriptionFallbackRules = if (mapped == null) {
            dao.enabledSubscriptionRules(scope.storageValue).toAnswerMap()
        } else emptyMap()
    }

    fun findAnswers(qname: String): Set<RewriteAnswer> {
        val domain = qname.lowercase().trimEnd('.')
        var candidate = domain
        while (true) {
            manualRules[candidate]?.let { return it }
            subscriptionIndex?.findExact(candidate)?.let { return it }
            subscriptionFallbackRules[candidate]?.let { return it }
            val dot = candidate.indexOf('.')
            if (dot < 0) break
            candidate = candidate.substring(dot + 1)
        }
        return emptySet()
    }

    fun cnameRedirects(): Map<String, String> = buildMap {
        subscriptionFallbackRules.forEach { (pattern, answers) ->
            answers.firstOrNull()
                ?.let { put(pattern, it.targetValue) }
        }
        manualRules.forEach { (pattern, answers) ->
            answers.firstOrNull()
                ?.let { put(pattern, it.targetValue) }
        }
    }
    suspend fun addRule(domain: String, targetType: String, targetValue: String): Boolean {
        if (scope == RuleScope.DNS && targetType == RewriteTargetType.CNAME) return false
        if (scope == RuleScope.HTTPS && targetType != RewriteTargetType.CNAME) return false
        val normalized = AdGuardRuleParser.normalizeDomainForRewrite(domain) ?: return false
        val normalizedValue = normalizeTarget(targetType, targetValue) ?: return false
        val isCname = targetType == RewriteTargetType.CNAME
        if (isCname && dao.countOtherTypes(normalized, targetType) > 0) return false
        if (!isCname && dao.countType(normalized, RewriteTargetType.CNAME) > 0) return false
        val ok = dao.insertForSource(RewriteRuleEntity(pattern = normalized, targetType = targetType, targetValue = normalizedValue, rawLine = "$normalized -> $normalizedValue", addedAt = System.currentTimeMillis(), scope = scope.storageValue), "useradd", true)
        if (ok) refreshCache(rebuildSubscriptionIndex = false); return ok
    }
    suspend fun addRules(
        rules: List<RewriteRule>,
        source: String,
        enabled: Boolean,
        chunkSize: Int = 500,
        onProgress: ((Int) -> Unit)? = null
    ): Int {
        val scopedRules = rules.filter { rule ->
            if (scope == RuleScope.DNS) rule.targetType in setOf(RewriteTargetType.IPV4, RewriteTargetType.IPV6)
            else rule.targetType == RewriteTargetType.CNAME
        }
        var inserted = 0
        val now = System.currentTimeMillis()
        scopedRules.chunked(chunkSize).forEachIndexed { index, chunk ->
            inserted += dao.insertAllForSource(
                chunk.map { rule ->
                    RewriteRuleEntity(
                        pattern = rule.pattern,
                        targetType = rule.targetType,
                        targetValue = rule.targetValue,
                        rawLine = rule.rawLine,
                        addedAt = now,
                        scope = scope.storageValue
                    )
                },
                source,
                enabled
            )
            onProgress?.invoke(minOf((index + 1) * chunkSize, scopedRules.size))
        }
        if (reloadCacheAfterChanges) refreshCache(rebuildSubscriptionIndex = source.isSubscriptionSource())
        return inserted
    }
    suspend fun removeRulesBySource(source: String) { dao.deleteBySource(source); if (reloadCacheAfterChanges) refreshCache(rebuildSubscriptionIndex = source.isSubscriptionSource()) }
    suspend fun promoteRulesBySource(
        stagingSource: String,
        targetSource: String,
        refreshCache: Boolean = true
    ) {
        dao.replaceSource(stagingSource, targetSource)
        if (refreshCache && reloadCacheAfterChanges) refreshCache(rebuildSubscriptionIndex = true)
    }
    suspend fun refreshCacheAfterExternalChange() {
        if (reloadCacheAfterChanges) refreshCache(rebuildSubscriptionIndex = true)
    }
    suspend fun setRulesEnabledBySource(source: String, enabled: Boolean) { dao.setEnabledBySource(source, enabled); refreshCache(rebuildSubscriptionIndex = source.isSubscriptionSource()) }
    suspend fun count() = dao.count(scope.storageValue)
    suspend fun deleteRule(id: Long) { val rebuild = dao.hasSubscriptionSource(id); dao.deleteById(id); refreshCache(rebuild) }
    suspend fun toggleRule(id: Long, enabled: Boolean) { val rebuild = dao.hasSubscriptionSource(id); dao.setEnabled(id, enabled); refreshCache(rebuild) }
    suspend fun rulesBySource(source: String) = dao.rulesBySource(source).map { RewriteRule(it.pattern, it.targetType, it.targetValue, it.rawLine) }
    suspend fun replaceRulesBySource(
        rules: List<RewriteRule>,
        source: String,
        enabled: Boolean,
        chunkSize: Int = 500,
        onProgress: ((Int) -> Unit)? = null
    ) {
        val scopedRules = rules.filter { rule ->
            if (scope == RuleScope.DNS) rule.targetType in setOf(RewriteTargetType.IPV4, RewriteTargetType.IPV6)
            else rule.targetType == RewriteTargetType.CNAME
        }
        dao.replaceBySource(
            source,
            scopedRules.map {
                RewriteRuleEntity(
                    pattern = it.pattern,
                    targetType = it.targetType,
                    targetValue = it.targetValue,
                    rawLine = it.rawLine,
                    addedAt = System.currentTimeMillis(),
                    scope = scope.storageValue
                )
            },
            enabled,
            chunkSize,
            onProgress
        )
        if (reloadCacheAfterChanges) refreshCache(rebuildSubscriptionIndex = source.isSubscriptionSource())
    }
    suspend fun clearAll() {
        dao.clearAll(scope.storageValue)
        manualRules = emptyMap()
        subscriptionFallbackRules = emptyMap()
        subscriptionIndex?.close()
        subscriptionIndex = null
        indexDirectory?.let { directory ->
            File(directory, indexFileName()).delete()
            if (scope == RuleScope.HTTPS) File(directory, LEGACY_INDEX_FILE_NAME).delete()
        }
    }
    override fun close() { subscriptionIndex?.close(); subscriptionIndex = null }
    private fun normalizeTarget(type: String, value: String): String? = when (type) {
        RewriteTargetType.CNAME -> AdGuardRuleParser.normalizeDomainForRewrite(value)
        RewriteTargetType.IPV4, RewriteTargetType.IPV6 -> runCatching { InetAddress.getByName(value.trim()) }.getOrNull()?.takeIf { (type == RewriteTargetType.IPV4 && it.address.size == 4) || (type == RewriteTargetType.IPV6 && it.address.size == 16) }?.hostAddress
        else -> null
    }

    private fun indexFileName() = "${scope.storageValue}-subscription-rewrite.trie"

    companion object {
        private const val LEGACY_INDEX_FILE_NAME = "subscription-rewrite.trie"
    }
}

private fun List<com.haoze.dnssr.data.dao.EnabledRewriteRule>.toAnswerMap(): Map<String, Set<RewriteAnswer>> =
    groupBy({ it.pattern }, { RewriteAnswer(it.targetType, it.targetValue) }).mapValues { it.value.toSet() }

private fun String.isSubscriptionSource(): Boolean = startsWith("sub_")

private suspend fun RewriteRuleDao.forEachSubscriptionRulePage(
    scope: String,
    consume: (com.haoze.dnssr.data.dao.EnabledRewriteRule) -> Unit
) {
    var offset = 0
    while (true) {
        val page = enabledSubscriptionRulesPage(scope, REWRITE_INDEX_PAGE_SIZE, offset)
        if (page.isEmpty()) return
        page.forEach(consume)
        offset += page.size
    }
}

private const val REWRITE_INDEX_PAGE_SIZE = 2_000
