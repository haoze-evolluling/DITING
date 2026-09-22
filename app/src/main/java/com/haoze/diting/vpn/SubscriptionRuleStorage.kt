package com.haoze.diting.vpn

import androidx.room.withTransaction
import com.haoze.diting.data.AppDatabase
import com.haoze.diting.data.dao.SubscriptionDao
import com.haoze.diting.data.entity.SubscriptionEntity
import com.haoze.diting.data.entity.SubscriptionImportState
import com.haoze.diting.data.entity.SubscriptionKind
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext

/**
 * Owns the mapping between a subscription and the rules it contributed.
 *
 * A subscription carries exactly one rule type, so every operation that moves
 * or toggles its rules is scoped to that type's tables: `domain` touches
 * `block_rule` / `allow_rule`, `hosts` touches `rewrite_rule`.
 *
 * Staging rows are the exception — they are transient scratch data produced by
 * an in-flight update, so they are always cleared across all tables.
 */
internal class SubscriptionRuleStorage(
    private val database: AppDatabase,
    private val subscriptionDao: SubscriptionDao,
    private val blockListManager: BlockListManager,
    private val allowListManager: AllowListManager,
    private val rewriteRuleManager: RewriteRuleManager
) {
    fun sourceTag(subscriptionId: Long): String = "sub_$subscriptionId"

    fun stagingSourceTag(subscriptionId: Long): String = "staging_sub_$subscriptionId"

    /** Clears every rule tag of [source], regardless of type. */
    suspend fun removeRulesBySource(source: String) {
        blockListManager.removeRulesBySource(source)
        allowListManager.removeRulesBySource(source)
        rewriteRuleManager.removeRulesBySource(source)
    }

    suspend fun removeStagingRules(subscriptionId: Long) {
        removeRulesBySource(stagingSourceTag(subscriptionId))
    }

    /**
     * Deletes every rule a subscription owns. Deliberately type-agnostic: a
     * deleted subscription must leave nothing behind, even if its stored type
     * ever disagreed with the tables holding its rules.
     */
    suspend fun removeSubscriptionRules(subscriptionId: Long) {
        removeRulesBySource(sourceTag(subscriptionId))
    }

    /**
     * Promotes staged rules into the live source tag and stores the refreshed
     * subscription record in a single transaction. Only the tables matching the
     * subscription's type are touched, so updating a domain subscription can
     * never disturb its hosts rules (and vice versa).
     */
    suspend fun publishStagedRules(
        subscriptionId: Long,
        kind: String,
        completedSubscription: SubscriptionEntity
    ) {
        val source = sourceTag(subscriptionId)
        val stagingSource = stagingSourceTag(subscriptionId)
        database.withTransaction {
            blockListManager.promoteRulesBySource(stagingSource, source, refreshCache = false)
            allowListManager.promoteRulesBySource(stagingSource, source, refreshCache = false)
            rewriteRuleManager.promoteRulesBySource(stagingSource, source, refreshCache = false)
            subscriptionDao.update(completedSubscription)
        }
        refreshAllCaches()
    }

    suspend fun refreshAllCaches() {
        blockListManager.refreshCacheAfterExternalChange()
        allowListManager.refreshCacheAfterExternalChange()
        rewriteRuleManager.refreshCacheAfterExternalChange()
    }

    suspend fun markUpdateCancelled(subscriptionId: Long) {
        withContext(NonCancellable) {
            removeStagingRules(subscriptionId)
            subscriptionDao.setImportState(
                subscriptionId,
                SubscriptionImportState.FAILED,
                "更新已取消，已保留原有规则"
            )
        }
    }

    suspend fun setSubscriptionRulesEnabled(subscriptionId: Long, kind: String, enabled: Boolean) {
        val source = sourceTag(subscriptionId)
        blockListManager.setRulesEnabledBySource(source, enabled)
        allowListManager.setRulesEnabledBySource(source, enabled)
        rewriteRuleManager.setRulesEnabledBySource(source, enabled)
    }
}
