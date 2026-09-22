package com.haoze.diting.vpn

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
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
import com.haoze.diting.MainActivity
import com.haoze.diting.R
import com.haoze.diting.data.entity.SubscriptionAutoUpdateItemEntity
import com.haoze.diting.data.entity.SubscriptionAutoUpdateItemStatus
import com.haoze.diting.notification.AppNotificationChannels
import com.haoze.diting.notification.NotificationPermissionHelper
import com.haoze.diting.ui.localizedText
import java.util.concurrent.CancellationException
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

    fun isEnabled(context: Context): Boolean = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
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
        val appContext = context.applicationContext
        val manager = WorkManager.getInstance(appContext)
        if (!SubscriptionAutoUpdateSettings.isEnabled(appContext)) {
            manager.cancelUniqueWork(WORK_NAME)
            manager.cancelUniqueWork(RETRY_WORK_NAME)
            return
        }
        val hours = SubscriptionAutoUpdateSettings.intervalHours(appContext)
        val request = PeriodicWorkRequestBuilder<SubscriptionAutoUpdateWorker>(hours.toLong(), TimeUnit.HOURS)
            .addTag(WORK_TAG)
            .setConstraints(
                Constraints.Builder()
                    .setRequiredNetworkType(NetworkType.CONNECTED)
                    .build()
            )
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
            .build()
        manager.enqueueUniquePeriodicWork(WORK_NAME, ExistingPeriodicWorkPolicy.UPDATE, request)
    }

    fun scheduleRetry(context: Context, batchId: String) {
        val appContext = context.applicationContext
        val request = OneTimeWorkRequestBuilder<SubscriptionAutoUpdateRetryWorker>()
            .addTag(WORK_TAG)
            .setInputData(workDataOf(SubscriptionAutoUpdateRetryWorker.KEY_BATCH_ID to batchId))
            .setInitialDelay(30, TimeUnit.SECONDS)
            .setConstraints(
                Constraints.Builder()
                    .setRequiredNetworkType(NetworkType.CONNECTED)
                    .build()
            )
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
            .build()
        WorkManager.getInstance(appContext).enqueueUniqueWork(
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
        try {
            when (val result = SubscriptionAutoUpdateEngine.executePeriodic(applicationContext) { progress ->
                setProgress(progress)
            }) {
                is SubscriptionAutoUpdateEngine.ExecutionResult.Completed -> {
                    Result.success()
                }
                is SubscriptionAutoUpdateEngine.ExecutionResult.BlockedByManualOperation -> {
                    Log.w("SubAutoUpdateWorker", "Auto update blocked by manual update; scheduling backoff retry")
                    Result.retry()
                }
                is SubscriptionAutoUpdateEngine.ExecutionResult.CancelledOrAborted -> {
                    Result.success()
                }
                is SubscriptionAutoUpdateEngine.ExecutionResult.Failed -> {
                    Log.e("SubAutoUpdateWorker", "Auto update failed", result.throwable)
                    Result.retry()
                }
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            Log.e("SubAutoUpdateWorker", "Unexpected error in periodic auto-update worker", e)
            Result.retry()
        }
    }
}

class SubscriptionAutoUpdateRetryWorker(
    context: Context,
    params: WorkerParameters
) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result = coroutineScope {
        val batchId = inputData.getString(KEY_BATCH_ID) ?: return@coroutineScope Result.success()
        try {
            when (val result = SubscriptionAutoUpdateEngine.executeRetry(
                applicationContext,
                batchId,
                runAttemptCount
            ) { progress ->
                setProgress(progress)
            }) {
                is SubscriptionAutoUpdateEngine.ExecutionResult.Completed -> {
                    if (result.hasPendingRetry) {
                        Result.retry()
                    } else {
                        Result.success()
                    }
                }
                is SubscriptionAutoUpdateEngine.ExecutionResult.BlockedByManualOperation -> {
                    Result.retry()
                }
                is SubscriptionAutoUpdateEngine.ExecutionResult.CancelledOrAborted -> {
                    Result.success()
                }
                is SubscriptionAutoUpdateEngine.ExecutionResult.Failed -> {
                    Log.e("SubAutoUpdateRetry", "Retry auto update failed", result.throwable)
                    Result.retry()
                }
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            Log.e("SubAutoUpdateRetry", "Unexpected error in retry worker", e)
            Result.retry()
        }
    }

    companion object {
        const val KEY_BATCH_ID = "batch_id"
    }
}

internal object SubscriptionAutoUpdateNotifier {
    private const val CHANNEL_ID = AppNotificationChannels.CHANNEL_SUBSCRIPTION_AUTO_UPDATE
    private const val NOTIFICATION_ID = 4102

    fun showSummary(context: Context, items: List<SubscriptionAutoUpdateItemEntity>) {
        if (!NotificationPermissionHelper.hasPermission(context)) {
            return
        }

        AppNotificationChannels.createAllChannels(context)
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
            .setSmallIcon(R.drawable.dns_svgrepo_com)
            .setContentTitle(title)
            .setContentText(summary)
            .setStyle(NotificationCompat.BigTextStyle().bigText(detail))
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .build()
        runCatching {
            NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, notification)
        }
    }
}
