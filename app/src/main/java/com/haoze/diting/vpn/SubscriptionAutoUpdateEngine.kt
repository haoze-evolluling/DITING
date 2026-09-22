package com.haoze.diting.vpn

import android.content.Context
import android.util.Log
import androidx.work.Data
import androidx.work.workDataOf
import com.haoze.diting.data.AppDatabase
import com.haoze.diting.data.dao.SubscriptionAutoUpdateDao
import com.haoze.diting.data.entity.RuleScope
import com.haoze.diting.data.entity.SubscriptionAutoUpdateItemEntity
import com.haoze.diting.data.entity.SubscriptionAutoUpdateItemStatus
import com.haoze.diting.ui.RuntimeDnsSettingsRefresher
import java.util.UUID

/**
 * Backend engine responsible for executing rule subscription automatic updates.
 *
 * Designed to execute cleanly in pure background mode without converting into a Foreground Service,
 * completely avoiding Android 12+ (API 31+) ForegroundServiceStartNotAllowedException.
 * Supports both ungrouped subscriptions and group-governed subscriptions, enforces cache rebuilding
 * upon rule modifications, and coordinates smoothly with user-initiated manual operations.
 */
object SubscriptionAutoUpdateEngine {

    private const val TAG = "SubAutoUpdateEngine"
    const val MAX_RETRY_ATTEMPTS = 3

    sealed class ExecutionResult {
        data class Completed(val hasPendingRetry: Boolean, val hasChanges: Boolean) : ExecutionResult()
        data object BlockedByManualOperation : ExecutionResult()
        data object CancelledOrAborted : ExecutionResult()
        data class Failed(val throwable: Throwable) : ExecutionResult()
    }

    /**
     * Executes a full periodic auto-update cycle for all eligible subscriptions.
     */
    suspend fun executePeriodic(
        context: Context,
        onProgress: suspend (Data) -> Unit
    ): ExecutionResult {
        val appContext = context.applicationContext
        if (!SubscriptionAutoUpdateSettings.isEnabled(appContext)) {
            Log.i(TAG, "Automatic update is disabled in settings; skipping periodic execution")
            return ExecutionResult.Completed(hasPendingRetry = false, hasChanges = false)
        }

        val database = AppDatabase.getInstance(appContext)
        val batchDao = database.subscriptionAutoUpdateDao()
        val subscriptions = database.subscriptionDao().allAutoUpdatableRemote()

        if (subscriptions.isEmpty()) {
            Log.i(TAG, "No auto-updatable remote subscriptions found")
            return ExecutionResult.Completed(hasPendingRetry = false, hasChanges = false)
        }

        val batchId = UUID.randomUUID().toString()
        var changed = false
        var aborted = false

        val managers = createManagers(appContext, database)

        val ran = SubscriptionUpdateCoordinator.runAutomatic { shouldStop ->
            SubscriptionImportRecovery.recoverInterruptedImports(database)

            for ((index, subscription) in subscriptions.withIndex()) {
                if (shouldStop()) {
                    aborted = true
                    break
                }

                val currentStep = index + 1
                onProgress(createProgressData(subscription.id, currentStep, subscriptions.size))

                managers.subscriptionManager.progressReporter = { current, total ->
                    onProgress(createProgressData(subscription.id, current, total))
                }

                val outcome = managers.subscriptionManager.updateSubscription(subscription.id)
                changed = recordOutcome(batchDao, batchId, subscription.id, outcome) || changed
            }

            if (shouldStop()) {
                aborted = true
            }
        }

        if (!ran) {
            Log.w(TAG, "Periodic update skipped because a manual update is currently running")
            batchDao.deleteBatch(batchId)
            return ExecutionResult.BlockedByManualOperation
        }

        if (aborted) {
            Log.i(TAG, "Periodic update was aborted due to incoming manual operation")
            batchDao.deleteBatch(batchId)
            return ExecutionResult.CancelledOrAborted
        }

        if (changed) {
            rebuildCachesAndNotifyRuntime(appContext, managers)
        }

        val pendingRetries = batchDao.byStatus(batchId, SubscriptionAutoUpdateItemStatus.PENDING_RETRY)
        return if (pendingRetries.isNotEmpty()) {
            Log.i(TAG, "Batch $batchId has ${pendingRetries.size} items pending retry; scheduling retry worker")
            SubscriptionAutoUpdateScheduler.scheduleRetry(appContext, batchId)
            ExecutionResult.Completed(hasPendingRetry = true, hasChanges = changed)
        } else {
            finishBatch(appContext, batchDao, batchId)
            ExecutionResult.Completed(hasPendingRetry = false, hasChanges = changed)
        }
    }

    /**
     * Executes a retry pass for a previously failed batch.
     */
    suspend fun executeRetry(
        context: Context,
        batchId: String,
        runAttemptCount: Int,
        onProgress: suspend (Data) -> Unit
    ): ExecutionResult {
        val appContext = context.applicationContext
        val database = AppDatabase.getInstance(appContext)
        val batchDao = database.subscriptionAutoUpdateDao()
        val pendingItems = batchDao.byStatus(batchId, SubscriptionAutoUpdateItemStatus.PENDING_RETRY)

        if (pendingItems.isEmpty()) {
            Log.i(TAG, "No pending retry items found for batch $batchId")
            batchDao.deleteBatch(batchId)
            return ExecutionResult.Completed(hasPendingRetry = false, hasChanges = false)
        }

        var changed = false
        var aborted = false
        val managers = createManagers(appContext, database)

        val ran = SubscriptionUpdateCoordinator.runAutomatic { shouldStop ->
            SubscriptionImportRecovery.recoverInterruptedImports(database)

            for ((index, item) in pendingItems.withIndex()) {
                if (shouldStop()) {
                    aborted = true
                    break
                }

                val subscription = database.subscriptionDao().byId(item.subscriptionId)
                // If subscription was deleted, disabled, or belongs to a group with auto-update disabled, drop it.
                if (subscription == null || !subscription.enabled) {
                    batchDao.deleteItem(batchId, item.subscriptionId)
                    continue
                }
                if (subscription.groupId != null &&
                    database.subscriptionGroupDao().byId(subscription.groupId)?.autoUpdateEnabled != true
                ) {
                    batchDao.deleteItem(batchId, item.subscriptionId)
                    continue
                }

                val currentStep = index + 1
                onProgress(createProgressData(item.subscriptionId, currentStep, pendingItems.size))

                managers.subscriptionManager.progressReporter = { current, total ->
                    onProgress(createProgressData(item.subscriptionId, current, total))
                }

                val outcome = managers.subscriptionManager.updateSubscription(item.subscriptionId)
                val finalOutcome = if (
                    outcome is SubscriptionUpdateOutcome.Failed &&
                    outcome.retryable &&
                    runAttemptCount >= MAX_RETRY_ATTEMPTS - 1
                ) {
                    outcome.copy(retryable = false)
                } else {
                    outcome
                }

                changed = recordOutcome(batchDao, batchId, item.subscriptionId, finalOutcome) || changed
            }

            if (shouldStop()) {
                aborted = true
            }
        }

        if (!ran) {
            Log.w(TAG, "Retry update skipped because a manual update is currently running")
            return ExecutionResult.BlockedByManualOperation
        }

        if (aborted) {
            Log.i(TAG, "Retry update was aborted due to incoming manual operation")
            return ExecutionResult.CancelledOrAborted
        }

        if (changed) {
            rebuildCachesAndNotifyRuntime(appContext, managers)
        }

        val remainingRetries = batchDao.byStatus(batchId, SubscriptionAutoUpdateItemStatus.PENDING_RETRY)
        return if (remainingRetries.isNotEmpty()) {
            ExecutionResult.Completed(hasPendingRetry = true, hasChanges = changed)
        } else {
            finishBatch(appContext, batchDao, batchId)
            ExecutionResult.Completed(hasPendingRetry = false, hasChanges = changed)
        }
    }

    fun createProgressData(subscriptionId: Long, current: Int, total: Int): Data = workDataOf(
        RuleOperationScheduler.KEY_TYPE to RuleOperationType.UPDATE_SUBSCRIPTION.name,
        RuleOperationScheduler.KEY_SUBSCRIPTION_ID to subscriptionId,
        RuleOperationScheduler.KEY_CURRENT to current,
        RuleOperationScheduler.KEY_TOTAL to total
    )

    private suspend fun rebuildCachesAndNotifyRuntime(context: Context, managers: AutoUpdateManagers) {
        runCatching { managers.blockManager.refreshCache(forceRebuild = true) }
            .onFailure { Log.w(TAG, "Failed to force rebuild block cache", it) }
        runCatching { managers.allowManager.refreshCache(forceRebuild = true) }
            .onFailure { Log.w(TAG, "Failed to force rebuild allow cache", it) }
        runCatching { managers.rewriteManager.refreshCache(rebuildSubscriptionIndex = true) }
            .onFailure { Log.w(TAG, "Failed to force rebuild rewrite cache", it) }

        RuntimeDnsSettingsRefresher.refreshRuleIndexesIfRunning(
            context,
            refreshBlock = true,
            refreshAllow = true,
            refreshRewrite = true,
            scope = RuleScope.DNS
        )
        RuntimeDnsSettingsRefresher.syncHttpsRequestRulesIfRunning(context)
    }

    suspend fun recordOutcome(
        dao: SubscriptionAutoUpdateDao,
        batchId: String,
        subscriptionId: Long,
        outcome: SubscriptionUpdateOutcome
    ): Boolean {
        val item = when (outcome) {
            is SubscriptionUpdateOutcome.Updated -> SubscriptionAutoUpdateItemEntity(
                batchId = batchId,
                subscriptionId = subscriptionId,
                status = SubscriptionAutoUpdateItemStatus.SUCCESS,
                changed = true,
                ruleCount = outcome.ruleCount
            )
            is SubscriptionUpdateOutcome.NotModified -> SubscriptionAutoUpdateItemEntity(
                batchId = batchId,
                subscriptionId = subscriptionId,
                status = SubscriptionAutoUpdateItemStatus.SUCCESS,
                changed = false,
                ruleCount = outcome.ruleCount
            )
            is SubscriptionUpdateOutcome.Failed -> SubscriptionAutoUpdateItemEntity(
                batchId = batchId,
                subscriptionId = subscriptionId,
                status = if (outcome.retryable) {
                    SubscriptionAutoUpdateItemStatus.PENDING_RETRY
                } else {
                    SubscriptionAutoUpdateItemStatus.FAILED
                }
            )
        }
        dao.upsert(item)
        return outcome is SubscriptionUpdateOutcome.Updated
    }

    suspend fun finishBatch(
        context: Context,
        dao: SubscriptionAutoUpdateDao,
        batchId: String
    ) {
        val items = dao.byBatch(batchId)
        if (items.isNotEmpty()) {
            SubscriptionAutoUpdateNotifier.showSummary(context, items)
        }
        dao.deleteBatch(batchId)
    }

    private data class AutoUpdateManagers(
        val blockManager: BlockListManager,
        val allowManager: AllowListManager,
        val rewriteManager: RewriteRuleManager,
        val subscriptionManager: SubscriptionManager
    )

    private fun createManagers(
        context: Context,
        database: AppDatabase,
        scope: RuleScope = RuleScope.DNS
    ): AutoUpdateManagers {
        val ruleIndexDirectory = RuleIndexLayout.scopeDirectory(context.filesDir, scope)
        val blockManager = BlockListManager(database.blockRuleDao(), ruleIndexDirectory, scope, reloadCacheAfterChanges = false)
        val allowManager = AllowListManager(database.allowRuleDao(), ruleIndexDirectory, scope, reloadCacheAfterChanges = false)
        val rewriteManager = RewriteRuleManager(database.rewriteRuleDao(), ruleIndexDirectory, scope, reloadCacheAfterChanges = false)
        val subscriptionManager = SubscriptionManager(
            database,
            database.subscriptionDao(),
            blockManager,
            allowManager,
            rewriteManager,
            scope,
            context.cacheDir
        )
        return AutoUpdateManagers(blockManager, allowManager, rewriteManager, subscriptionManager)
    }
}
