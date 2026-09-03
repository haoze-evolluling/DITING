package com.haoze.dnssr.vpn

import android.util.Log
import com.haoze.dnssr.util.forEachKeysetPage
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
    @Volatile private var subscriptionCnameRules: Map<String, String> = emptyMap()
    @Volatile private var subscriptionIndex: MappedSubscriptionRewriteIndex? = null

    suspend fun refreshCache(rebuildSubscriptionIndex: Boolean = false) {
        manualRules = dao.enabledNonSubscriptionRules().toAnswerMap()

        val indexFile = indexDirectory?.let { File(it, indexFileName()) }
        var mapped = if (!rebuildSubscriptionIndex && indexFile?.exists() == true && indexFile.length() > 0) {
            runCatching { MappedSubscriptionRewriteIndex.load(indexFile) }
                .onFailure { Log.w(TAG, "Existing subscription rewrite index invalid, will recompile", it) }
                .getOrNull()
        } else null

        if (mapped == null && (rebuildSubscriptionIndex || subscriptionIndex == null)) {
            mapped = indexFile?.let { file ->
                runCatching {
                    MappedSubscriptionRewriteIndex.compileAndLoad(file) { consume ->
                        dao.forEachSubscriptionRulePage(consume)
                    }
                }.onFailure { e ->
                    Log.e(TAG, "Failed to compile subscription rewrite index", e)
                }.getOrNull()
            }
        }

        if (mapped != null || rebuildSubscriptionIndex) {
            val oldIndex = subscriptionIndex
            subscriptionIndex = mapped
            if (oldIndex !== mapped) {
                oldIndex?.close()
            }
        }

        subscriptionFallbackRules = if (subscriptionIndex == null) {
            dao.enabledSubscriptionRules().toAnswerMap()
        } else emptyMap()

        subscriptionCnameRules = if (subscriptionIndex != null) {
            buildMap {
                dao.enabledSubscriptionRules()
                    .filter { it.targetType == RewriteTargetType.CNAME }
                    .forEach { put(it.pattern, it.targetValue) }
            }
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
        putAll(subscriptionCnameRules)
        subscriptionFallbackRules.forEach { (pattern, answers) ->
            answers.firstOrNull { it.targetType == RewriteTargetType.CNAME }
                ?.let { put(pattern, it.targetValue) }
        }
        manualRules.forEach { (pattern, answers) ->
            answers.firstOrNull { it.targetType == RewriteTargetType.CNAME }
                ?.let { put(pattern, it.targetValue) }
        }
    }
    suspend fun addRule(domain: String, targetType: String, targetValue: String): Boolean {
        if (targetType !in setOf(RewriteTargetType.IPV4, RewriteTargetType.IPV6, RewriteTargetType.CNAME)) return false
        val normalized = AdGuardRuleParser.normalizeDomainForRewrite(domain) ?: return false
        val normalizedValue = normalizeTarget(targetType, targetValue) ?: return false
        val isCname = targetType == RewriteTargetType.CNAME
        if (isCname && dao.countOtherTypes(normalized, targetType) > 0) return false
        if (!isCname && dao.countType(normalized, RewriteTargetType.CNAME) > 0) return false
        val ok = dao.insertForSource(RewriteRuleEntity(pattern = normalized, targetType = targetType, targetValue = normalizedValue, rawLine = "$normalized -> $normalizedValue", addedAt = System.currentTimeMillis()), "useradd", true)
        if (ok) refreshCache(rebuildSubscriptionIndex = false); return ok
    }
    suspend fun addRules(
        rules: List<RewriteRule>,
        source: String,
        enabled: Boolean,
        chunkSize: Int = 500,
        refreshCache: Boolean = true,
        onProgress: ((Int) -> Unit)? = null
    ): Int {
        val validRules = rules.filter { rule ->
            rule.targetType in setOf(RewriteTargetType.IPV4, RewriteTargetType.IPV6, RewriteTargetType.CNAME)
        }
        var inserted = 0
        val now = System.currentTimeMillis()
        validRules.chunked(chunkSize).forEachIndexed { index, chunk ->
            inserted += dao.insertAllForSource(
                chunk.map { rule ->
                    RewriteRuleEntity(
                        pattern = rule.pattern,
                        targetType = rule.targetType,
                        targetValue = rule.targetValue,
                        rawLine = rule.rawLine,
                        addedAt = now
                    )
                },
                source,
                enabled
            )
            onProgress?.invoke(minOf((index + 1) * chunkSize, validRules.size))
        }
        if (refreshCache && reloadCacheAfterChanges) refreshCache(rebuildSubscriptionIndex = source.isSubscriptionSource())
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
    suspend fun count() = dao.count()
    suspend fun deleteRule(id: Long) { val rebuild = dao.hasSubscriptionSource(id); dao.deleteById(id); refreshCache(rebuild) }
    suspend fun toggleRule(id: Long, enabled: Boolean) { val rebuild = dao.hasSubscriptionSource(id); dao.setEnabled(id, enabled); if (enabled) dao.setSourceEnabledByRuleId(id, true); refreshCache(rebuild) }
    suspend fun rulesBySource(source: String) = dao.rulesBySource(source).map { RewriteRule(it.pattern, it.targetType, it.targetValue, it.rawLine) }
    suspend fun replaceRulesBySource(
        rules: List<RewriteRule>,
        source: String,
        enabled: Boolean,
        chunkSize: Int = 500,
        onProgress: ((Int) -> Unit)? = null
    ) {
        val validRules = rules.filter { rule ->
            rule.targetType in setOf(RewriteTargetType.IPV4, RewriteTargetType.IPV6, RewriteTargetType.CNAME)
        }
        dao.replaceBySource(
            source,
            validRules.map {
                RewriteRuleEntity(
                    pattern = it.pattern,
                    targetType = it.targetType,
                    targetValue = it.targetValue,
                    rawLine = it.rawLine,
                    addedAt = System.currentTimeMillis()
                )
            },
            enabled,
            chunkSize,
            onProgress
        )
        if (reloadCacheAfterChanges) refreshCache(rebuildSubscriptionIndex = source.isSubscriptionSource())
    }
    suspend fun editRule(id: Long, domain: String, targetType: String, targetValue: String): Boolean {
        if (targetType !in setOf(RewriteTargetType.IPV4, RewriteTargetType.IPV6, RewriteTargetType.CNAME)) return false
        val normalized = AdGuardRuleParser.normalizeDomainForRewrite(domain) ?: return false
        val normalizedValue = normalizeTarget(targetType, targetValue) ?: return false
        val existing = dao.ruleById(id) ?: return false
        val isCname = targetType == RewriteTargetType.CNAME
        if (isCname) {
            val otherTypes = dao.countOtherTypes(normalized, targetType)
            if (otherTypes > 0 && !(existing.pattern == normalized && existing.targetType != targetType && otherTypes == 1)) {
                return false
            }
        } else {
            val cnameCount = dao.countType(normalized, RewriteTargetType.CNAME)
            if (cnameCount > 0 && !(existing.pattern == normalized && existing.targetType == RewriteTargetType.CNAME && cnameCount == 1)) {
                return false
            }
        }
        val rawLine = "$normalized -> $normalizedValue"
        dao.updateRule(id, normalized, targetType, normalizedValue, rawLine)
        val rebuild = dao.hasSubscriptionSource(id)
        refreshCache(rebuild)
        return true
    }
    suspend fun clearUserRules() {
        dao.deleteUserRules()
        refreshCache(rebuildSubscriptionIndex = false)
    }
    suspend fun clearAll() {
        dao.clearAll()
        manualRules = emptyMap()
        subscriptionFallbackRules = emptyMap()
        subscriptionIndex?.close()
        subscriptionIndex = null
        indexDirectory?.let { directory ->
            File(directory, indexFileName()).delete()
            File(directory, LEGACY_INDEX_FILE_NAME).delete()
            File(directory, "dns-subscription-rewrite.trie").delete()
            File(directory, "https-subscription-rewrite.trie").delete()
        }
    }
    override fun close() { subscriptionIndex?.close(); subscriptionIndex = null }
    private fun normalizeTarget(type: String, value: String): String? = when (type) {
        RewriteTargetType.CNAME -> AdGuardRuleParser.normalizeDomainForRewrite(value)
        RewriteTargetType.IPV4, RewriteTargetType.IPV6 -> runCatching { InetAddress.getByName(value.trim()) }.getOrNull()?.takeIf { (type == RewriteTargetType.IPV4 && it.address.size == 4) || (type == RewriteTargetType.IPV6 && it.address.size == 16) }?.hostAddress
        else -> null
    }

    private fun indexFileName() = "subscription-rewrite.trie"

    companion object {
        private const val TAG = "RewriteRuleMgr"
        private const val LEGACY_INDEX_FILE_NAME = "subscription-rewrite.trie"
    }
}

private fun List<com.haoze.dnssr.data.dao.EnabledRewriteRule>.toAnswerMap(): Map<String, Set<RewriteAnswer>> =
    groupBy({ it.pattern }, { RewriteAnswer(it.targetType, it.targetValue) }).mapValues { it.value.toSet() }

private fun String.isSubscriptionSource(): Boolean = startsWith("sub_")

private suspend fun RewriteRuleDao.forEachSubscriptionRulePage(
    consume: (com.haoze.dnssr.data.dao.EnabledRewriteRule) -> Unit
) = forEachKeysetPage(
    REWRITE_INDEX_PAGE_SIZE,
    { lastId, limit -> enabledSubscriptionRulesPageKeyset(limit, lastId) },
    { it.id },
    { consume(it.toEnabledRewriteRule()) }
)

private const val REWRITE_INDEX_PAGE_SIZE = 2_000
