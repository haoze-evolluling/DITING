package com.haoze.dnssr.vpn

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import com.haoze.dnssr.data.AppDatabase
import com.haoze.dnssr.MainActivity
import com.haoze.dnssr.R
import com.haoze.dnssr.data.entity.SubscriptionAutoUpdateItemEntity
import com.haoze.dnssr.data.entity.SubscriptionAutoUpdateItemStatus
import com.haoze.dnssr.data.entity.RuleScope
import com.haoze.dnssr.ui.RuntimeDnsSettingsRefresher
import com.haoze.dnssr.ui.localizedText
import java.util.UUID
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.coroutineScope

object SubscriptionAutoUpdateSettings {
    private const val PREFS = "dns_vpn_prefs"
    private const val KEY_ENABLED = "subscription_auto_update_enabled"
    private const val KEY_INTERVAL = "subscription_auto_update_interval_hours"
    const val DEFAULT_INTERVAL_HOURS = 24
    val intervals = listOf(6, 12, 24, 48)
    const val MIN_INTERVAL_HOURS = 1
    const val MAX_INTERVAL_HOURS = 168

    fun isEnabled(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        .getBoolean(KEY_ENABLED, false)

    fun intervalHours(context: Context): Int {
        val value = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getInt(KEY_INTERVAL, DEFAULT_INTERVAL_HOURS)
        return value.takeIf { it in MIN_INTERVAL_HOURS..MAX_INTERVAL_HOURS } ?: DEFAULT_INTERVAL_HOURS
    }

    fun save(context: Context, enabled: Boolean, intervalHours: Int) {
        require(intervalHours in MIN_INTERVAL_HOURS..MAX_INTERVAL_HOURS)
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putBoolean(KEY_ENABLED, enabled)
            .putInt(KEY_INTERVAL, intervalHours)
            .apply()
    }
}

object SubscriptionAutoUpdateScheduler {
    const val WORK_TAG = "subscription_auto_update_work"
    private const val WORK_NAME = "subscription_auto_update"
    private const val RETRY_WORK_NAME = "subscription_auto_update_retry"

    fun sync(context: Context) {
        val manager = WorkManager.getInstance(context)
        if (!SubscriptionAutoUpdateSettings.isEnabled(context)) {
            manager.cancelUniqueWork(WORK_NAME)
            manager.cancelUniqueWork(RETRY_WORK_NAME)
            return
        }
        val hours = SubscriptionAutoUpdateSettings.intervalHours(context)
        val request = PeriodicWorkRequestBuilder<SubscriptionAutoUpdateWorker>(hours.toLong(), TimeUnit.HOURS)
            .addTag(WORK_TAG)
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
            .build()
        manager.enqueueUniquePeriodicWork(WORK_NAME, ExistingPeriodicWorkPolicy.UPDATE, request)
    }

    fun scheduleRetry(context: Context, batchId: String) {
        val request = OneTimeWorkRequestBuilder<SubscriptionAutoUpdateRetryWorker>()
            .addTag(WORK_TAG)
            .setInputData(workDataOf(SubscriptionAutoUpdateRetryWorker.KEY_BATCH_ID to batchId))
            .setInitialDelay(30, TimeUnit.SECONDS)
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
            .build()
        WorkManager.getInstance(context).enqueueUniqueWork(
            RETRY_WORK_NAME,
            ExistingWorkPolicy.REPLACE,
            request
        )
    }
}

class SubscriptionAutoUpdateWorker(
    context: Context,
    params: WorkerParameters
) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result = coroutineScope {
        val database = AppDatabase.getInstance(applicationContext)
        val ruleIndexDirectory = java.io.File(applicationContext.filesDir, "rule-index")
        val manager = SubscriptionManager(
            database,
            database.subscriptionDao(),
            BlockListManager(database.blockRuleDao(), ruleIndexDirectory, reloadCacheAfterChanges = false),
            AllowListManager(database.allowRuleDao(), ruleIndexDirectory, reloadCacheAfterChanges = false),
            RewriteRuleManager(database.rewriteRuleDao(), ruleIndexDirectory, reloadCacheAfterChanges = false)
        )
        val batchDao = database.subscriptionAutoUpdateDao()
        val batchId = UUID.randomUUID().toString()
        val subscriptions = database.subscriptionDao().allAutoUpdatableRemote()
        val notifier = RuleUpdateNotifier(applicationContext, AUTO_UPDATE_PROGRESS_NOTIFICATION_ID)
        var currentName = ""
        var currentIndex = 0
        setForeground(notifier.foregroundInfo(localizedText(applicationContext, "正在自动更新规则订阅"), total = subscriptions.size))
        var changed = false
        var aborted = false
            val ran = SubscriptionUpdateCoordinator.runAutomatic { shouldStop ->
                SubscriptionImportRecovery.recoverInterruptedImports(database)
                batchDao.clear()
                for ((index, subscription) in subscriptions.withIndex()) {
                    if (shouldStop()) {
                        aborted = true
                        break
                    }
                    currentName = subscription.name
                    currentIndex = index + 1
                    setProgress(automaticProgressData(subscription.id, currentIndex, subscriptions.size))
                    notifier.showProgress(
                        localizedText(applicationContext, "正在自动更新规则订阅"),
                        progressDetail(applicationContext, currentName, currentIndex, subscriptions.size),
                        currentIndex,
                        subscriptions.size
                    )
                    val manager = subscriptionManagerFor(applicationContext, database, subscription.scope)
                    manager.progressReporter = { current, total ->
                        setProgress(automaticProgressData(subscription.id, current, total))
                        notifier.showProgress(
                            localizedText(applicationContext, "正在自动更新规则订阅"),
                            "$currentName：$current / $total",
                            current,
                            total
                        )
                    }
                    val outcome = manager.updateSubscription(subscription.id)
                    changed = recordOutcome(batchDao, batchId, subscription.id, outcome) || changed
                }
                if (shouldStop()) aborted = true
            }
            if (!ran || aborted) {
                batchDao.deleteBatch(batchId)
                return@coroutineScope Result.success()
            }
            if (changed) {
                RuntimeDnsSettingsRefresher.refreshIfRunning(applicationContext, "subscriptions_auto_updated")
            }
            if (batchDao.byStatus(batchId, SubscriptionAutoUpdateItemStatus.PENDING_RETRY).isNotEmpty()) {
                SubscriptionAutoUpdateScheduler.scheduleRetry(applicationContext, batchId)
                Result.success()
            } else {
                finishBatch(applicationContext, batchDao, batchId)
                Result.success()
            }
    }
}

class SubscriptionAutoUpdateRetryWorker(
    context: Context,
    params: WorkerParameters
) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result = coroutineScope {
        val batchId = inputData.getString(KEY_BATCH_ID) ?: return@coroutineScope Result.success()
        val database = AppDatabase.getInstance(applicationContext)
        val batchDao = database.subscriptionAutoUpdateDao()
        val pendingItems = batchDao.byStatus(batchId, SubscriptionAutoUpdateItemStatus.PENDING_RETRY)
        val notifier = RuleUpdateNotifier(applicationContext, AUTO_UPDATE_RETRY_PROGRESS_NOTIFICATION_ID)
        var currentName = ""
        var currentIndex = 0
        setForeground(notifier.foregroundInfo(localizedText(applicationContext, "正在重试自动更新规则订阅"), total = pendingItems.size))
        var changed = false
        var aborted = false
            val ran = SubscriptionUpdateCoordinator.runAutomatic { shouldStop ->
                SubscriptionImportRecovery.recoverInterruptedImports(database)
                for ((index, item) in pendingItems.withIndex()) {
                    if (shouldStop()) {
                        aborted = true
                        break
                    }
                    val subscription = database.subscriptionDao().byId(item.subscriptionId)
                    if (subscription == null || !subscription.enabled || subscription.groupId == null ||
                        database.subscriptionGroupDao().byId(subscription.groupId)?.autoUpdateEnabled != true) {
                        batchDao.deleteItem(batchId, item.subscriptionId)
                        continue
                    }
                    currentName = subscription.name
                    currentIndex = index + 1
                    setProgress(automaticProgressData(subscription.id, currentIndex, pendingItems.size))
                    notifier.showProgress(
                        localizedText(applicationContext, "正在重试自动更新规则订阅"),
                        progressDetail(applicationContext, currentName, currentIndex, pendingItems.size),
                        currentIndex,
                        pendingItems.size
                    )
                    val manager = subscriptionManagerFor(applicationContext, database, subscription.scope)
                    manager.progressReporter = { current, total ->
                        setProgress(automaticProgressData(item.subscriptionId, current, total))
                        notifier.showProgress(
                            localizedText(applicationContext, "正在重试自动更新规则订阅"),
                            "$currentName：$current / $total",
                            current,
                            total
                        )
                    }
                    val outcome = manager.updateSubscription(item.subscriptionId)
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
                if (shouldStop()) aborted = true
            }
            if (!ran || aborted) {
                batchDao.deleteBatch(batchId)
                return@coroutineScope Result.success()
            }
            if (changed) {
                RuntimeDnsSettingsRefresher.refreshIfRunning(applicationContext, "subscriptions_auto_updated")
            }
            if (batchDao.byStatus(batchId, SubscriptionAutoUpdateItemStatus.PENDING_RETRY).isNotEmpty()) {
                Result.retry()
            } else {
                finishBatch(applicationContext, batchDao, batchId)
                Result.success()
            }
    }

    companion object {
        const val KEY_BATCH_ID = "batch_id"
        private const val MAX_RETRY_ATTEMPTS = 3
    }
}

private fun subscriptionManagerFor(
    context: Context,
    database: AppDatabase,
    scopeValue: String
): SubscriptionManager {
    val scope = RuleScope.fromStorage(scopeValue)
    val ruleIndexDirectory = java.io.File(context.filesDir, "rule-index").let {
        if (scope == RuleScope.HTTPS) java.io.File(it, "https") else it
    }
    return SubscriptionManager(
        database,
        database.subscriptionDao(),
        BlockListManager(database.blockRuleDao(), ruleIndexDirectory, scope, reloadCacheAfterChanges = false),
        AllowListManager(database.allowRuleDao(), ruleIndexDirectory, scope, reloadCacheAfterChanges = false),
        RewriteRuleManager(database.rewriteRuleDao(), ruleIndexDirectory, scope, reloadCacheAfterChanges = false),
        scope
    )
}

private fun progressDetail(
    context: Context,
    subscriptionName: String,
    subscriptionIndex: Int,
    subscriptionTotal: Int
): String {
    val batch = if (subscriptionTotal > 0 && subscriptionIndex > 0) {
        "第 $subscriptionIndex / $subscriptionTotal 个"
    } else {
        "正在准备"
    }
    val name = subscriptionName.takeIf { it.isNotBlank() }?.let { "：$it" }.orEmpty()
    return localizedText(context, "$batch$name，正在下载")
}

private fun automaticProgressData(subscriptionId: Long, current: Int, total: Int) = workDataOf(
    RuleOperationScheduler.KEY_TYPE to RuleOperationType.UPDATE_SUBSCRIPTION.name,
    RuleOperationScheduler.KEY_SUBSCRIPTION_ID to subscriptionId,
    RuleOperationScheduler.KEY_CURRENT to current,
    RuleOperationScheduler.KEY_TOTAL to total
)

private const val AUTO_UPDATE_PROGRESS_NOTIFICATION_ID = 4201
private const val AUTO_UPDATE_RETRY_PROGRESS_NOTIFICATION_ID = 4202

private suspend fun recordOutcome(
    dao: com.haoze.dnssr.data.dao.SubscriptionAutoUpdateDao,
    batchId: String,
    subscriptionId: Long,
    outcome: SubscriptionUpdateOutcome
): Boolean {
    val item = when (outcome) {
        is SubscriptionUpdateOutcome.Updated -> SubscriptionAutoUpdateItemEntity(
            batchId,
            subscriptionId,
            SubscriptionAutoUpdateItemStatus.SUCCESS,
            changed = true,
            ruleCount = outcome.ruleCount
        )
        is SubscriptionUpdateOutcome.NotModified -> SubscriptionAutoUpdateItemEntity(
            batchId,
            subscriptionId,
            SubscriptionAutoUpdateItemStatus.SUCCESS,
            changed = false,
            ruleCount = outcome.ruleCount
        )
        is SubscriptionUpdateOutcome.Failed -> SubscriptionAutoUpdateItemEntity(
            batchId,
            subscriptionId,
            if (outcome.retryable) {
                SubscriptionAutoUpdateItemStatus.PENDING_RETRY
            } else {
                SubscriptionAutoUpdateItemStatus.FAILED
            }
        )
    }
    dao.upsert(item)
    return outcome is SubscriptionUpdateOutcome.Updated
}

private suspend fun finishBatch(
    context: Context,
    dao: com.haoze.dnssr.data.dao.SubscriptionAutoUpdateDao,
    batchId: String
) {
    val items = dao.byBatch(batchId)
    if (items.isNotEmpty()) SubscriptionAutoUpdateNotifier.showSummary(context, items)
    dao.deleteBatch(batchId)
}

private object SubscriptionAutoUpdateNotifier {
    private const val CHANNEL_ID = "subscription_auto_update"
    private const val NOTIFICATION_ID = 4102

    fun showSummary(context: Context, items: List<SubscriptionAutoUpdateItemEntity>) {
        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) !=
                PackageManager.PERMISSION_GRANTED
        ) {
            return
        }

        val notificationManager = context.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            notificationManager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    localizedText(context, "规则订阅自动更新"),
                    NotificationManager.IMPORTANCE_DEFAULT
                )
            )
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val successCount = items.count { it.status == SubscriptionAutoUpdateItemStatus.SUCCESS }
        val failedCount = items.count { it.status == SubscriptionAutoUpdateItemStatus.FAILED }
        val updatedCount = items.count { it.status == SubscriptionAutoUpdateItemStatus.SUCCESS && it.changed }
        val unchangedCount = successCount - updatedCount
        val importedRuleCount = items.filter { it.changed }.sumOf { it.ruleCount }
        val title = when {
            successCount == 0 -> localizedText(context, "规则订阅自动更新失败")
            failedCount > 0 -> localizedText(context, "规则订阅自动更新完成")
            else -> localizedText(context, "规则订阅已自动更新")
        }
        val summaryText = "成功 $successCount 个，失败 $failedCount 个；更新 $updatedCount 个，无需更新 $unchangedCount 个"
        val summary = localizedText(context, summaryText)
        val detail = localizedText(context, "$summaryText，共导入 $importedRuleCount 条规则")
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_launcher_dnssr)
            .setContentTitle(title)
            .setContentText(summary)
            .setStyle(NotificationCompat.BigTextStyle().bigText(detail))
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .build()
        NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, notification)
    }
}
