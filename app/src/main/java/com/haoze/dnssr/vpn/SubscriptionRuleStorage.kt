package com.haoze.dnssr.vpn

import androidx.room.withTransaction
import com.haoze.dnssr.data.AppDatabase
import com.haoze.dnssr.data.dao.SubscriptionDao
import com.haoze.dnssr.data.entity.SubscriptionEntity
import com.haoze.dnssr.data.entity.SubscriptionImportState
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext

internal class SubscriptionRuleStorage(
    private val database: AppDatabase,
    private val subscriptionDao: SubscriptionDao,
    private val blockListManager: BlockListManager,
    private val allowListManager: AllowListManager,
    private val rewriteRuleManager: RewriteRuleManager
) {
    fun sourceTag(subscriptionId: Long): String = "sub_$subscriptionId"

    fun stagingSourceTag(subscriptionId: Long): String = "staging_sub_$subscriptionId"

    suspend fun removeRulesBySource(source: String) {
        blockListManager.removeRulesBySource(source)
        allowListManager.removeRulesBySource(source)
        rewriteRuleManager.removeRulesBySource(source)
    }

    suspend fun removeStagingRules(subscriptionId: Long) {
        removeRulesBySource(stagingSourceTag(subscriptionId))
    }

    suspend fun removeSubscriptionRules(subscriptionId: Long) {
        removeRulesBySource(sourceTag(subscriptionId))
    }

    suspend fun publishStagedRules(
        subscriptionId: Long,
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
        blockListManager.refreshCacheAfterExternalChange()
        allowListManager.refreshCacheAfterExternalChange()
        rewriteRuleManager.refreshCacheAfterExternalChange()
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

    suspend fun setSubscriptionRulesEnabled(subscriptionId: Long, enabled: Boolean) {
        val source = sourceTag(subscriptionId)
        blockListManager.setRulesEnabledBySource(source, enabled)
        allowListManager.setRulesEnabledBySource(source, enabled)
        rewriteRuleManager.setRulesEnabledBySource(source, enabled)
    }
}
