package com.haoze.dnssr.vpn

import android.util.Log
import com.haoze.dnssr.data.entity.RuleScope
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * 负责规则增量同步防抖队列调度与规则索引缓存刷新。
 */
class DnsVpnRuleSyncManager {

    private val pendingRuleSyncs = mutableMapOf<String, MutableSet<String>>()
    private var ruleSyncJob: Job? = null

    /**
     * 调度规则单条增量同步（带有防抖机制）。
     */
    fun scheduleRuleSync(
        ruleType: String,
        pattern: String,
        scope: CoroutineScope,
        refreshMutex: Mutex,
        blockListManager: BlockListManager,
        allowListManager: AllowListManager,
        goInspectionTunnel: GoInspectionTunnel? = null,
        ruleScope: RuleScope = RuleScope.DNS
    ) {
        if (pattern.isBlank() || ruleType !in setOf(RULE_TYPE_BLOCK, RULE_TYPE_ALLOW)) return
        synchronized(pendingRuleSyncs) {
            pendingRuleSyncs
                .getOrPut(ruleType) { linkedSetOf() }
                .add(pattern)
            if (ruleSyncJob?.isActive == true) {
                return
            }
            ruleSyncJob = scope.launch {
                while (true) {
                    val pending = synchronized(pendingRuleSyncs) {
                        if (pendingRuleSyncs.isEmpty() || pendingRuleSyncs.values.all { it.isEmpty() }) {
                            ruleSyncJob = null
                            return@launch
                        }
                        pendingRuleSyncs.mapValues { it.value.toSet() }
                            .also { pendingRuleSyncs.clear() }
                    }
                    runCatching {
                        refreshMutex.withLock {
                            pending[RULE_TYPE_BLOCK].orEmpty().forEach { blockListManager.syncCachedPattern(it) }
                            pending[RULE_TYPE_ALLOW].orEmpty().forEach { allowListManager.syncCachedPattern(it) }
                            goInspectionTunnel?.pushRuleSnapshot()
                        }
                    }.onFailure { error ->
                        Log.w(TAG, "Failed to apply rule sync batch", error)
                    }
                }
            }
        }
    }

    /**
     * 刷新指定类型的规则索引缓存。
     */
    fun refreshRuleIndexes(
        refreshBlock: Boolean,
        refreshAllow: Boolean,
        refreshRewrite: Boolean,
        scope: CoroutineScope,
        refreshMutex: Mutex,
        blockListManager: BlockListManager,
        allowListManager: AllowListManager,
        rewriteRuleManager: RewriteRuleManager,
        goInspectionTunnel: GoInspectionTunnel?,
        ruleScope: RuleScope = RuleScope.DNS
    ) {
        scope.launch {
            refreshMutex.withLock {
                if (refreshBlock) runCatching { blockListManager.refreshCache(forceRebuild = true) }
                    .onFailure { Log.w(TAG, "Failed to refresh block list cache", it) }
                if (refreshAllow) runCatching {
                    allowListManager.refreshCache(forceRebuild = true)
                    goInspectionTunnel?.updatePassthroughRules()
                }.onFailure { Log.w(TAG, "Failed to refresh allow list cache", it) }
                if (refreshRewrite) runCatching { rewriteRuleManager.refreshCache(rebuildSubscriptionIndex = true) }
                    .onSuccess { goInspectionTunnel?.updateRewriteRules() }
                    .onFailure { Log.w(TAG, "Failed to refresh rewrite rule cache", it) }
                goInspectionTunnel?.pushRuleSnapshot()
            }
        }
    }

    /**
     * 同步 HTTPS 请求规则至 Go 隧道。
     */
    fun syncHttpsRequestRules(
        scope: CoroutineScope,
        refreshMutex: Mutex,
        goInspectionTunnel: GoInspectionTunnel?
    ) {
        scope.launch {
            refreshMutex.withLock {
                runCatching { goInspectionTunnel?.updateRewriteRules() }
                    .onFailure { Log.w(TAG, "Failed to refresh HTTPS request rules", it) }
            }
        }
    }

    companion object {
        private const val TAG = "DnsVpnRuleSyncManager"
        const val RULE_TYPE_BLOCK = "block"
        const val RULE_TYPE_ALLOW = "allow"
    }
}
