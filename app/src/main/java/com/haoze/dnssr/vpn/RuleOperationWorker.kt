package com.haoze.dnssr.vpn

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.Uri
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.ForegroundInfo
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequest
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import com.haoze.dnssr.MainActivity
import com.haoze.dnssr.R
import com.haoze.dnssr.data.AppDatabase
import com.haoze.dnssr.ui.RuntimeDnsSettingsRefresher
import com.haoze.dnssr.ui.localizedText
import java.io.BufferedReader
import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch

enum class RuleOperationType {
    ADD_SUBSCRIPTION,
    ADD_LOCAL_SUBSCRIPTION,
    EDIT_SUBSCRIPTION,
    UPDATE_SUBSCRIPTION,
    UPDATE_ALL_SUBSCRIPTIONS,
    IMPORT_RULES,
    IMPORT_HOSTS_RULES,
    IMPORT_ADDRESS_RULE_BACKUP,
    ADD_BLOCK_RULE,
    ADD_ALLOW_RULE
}

object RuleOperationScheduler {
    const val TAG = "manual_rule_operation"
    const val KEY_TYPE = "type"
    const val KEY_URL = "url"
    const val KEY_NAME = "name"
    const val KEY_URI = "uri"
    const val KEY_PATTERN = "pattern"
    const val KEY_SUBSCRIPTION_ID = "subscription_id"
    const val KEY_CURRENT = "current"
    const val KEY_TOTAL = "total"
    const val KEY_MESSAGE = "message"
    const val KEY_SUCCESS = "success"
    const val KEY_KIND = "kind"
    const val KEY_MIRROR_TEMPLATE = "mirror_template"
    const val KEY_MIRROR_FALLBACK = "mirror_fallback"
    const val KEY_SCOPE = "scope"
    const val KEY_GROUP_ID = "group_id"

    private const val UNIQUE_WORK_NAME = "manual_rule_operation_queue"

    fun enqueue(
        context: Context,
        type: RuleOperationType,
        subscriptionId: Long = -1,
        url: String? = null,
        name: String? = null,
        uri: Uri? = null,
        pattern: String? = null,
        kind: String? = null,
        mirrorTemplate: String? = null,
        mirrorFallback: Boolean = true,
        groupId: Long = -1,
        scope: String = com.haoze.dnssr.data.entity.RuleScope.DNS.storageValue
    ): OneTimeWorkRequest {
        val input = Data.Builder()
            .putString(KEY_TYPE, type.name)
            .putLong(KEY_SUBSCRIPTION_ID, subscriptionId)
            .putString(KEY_URL, url)
            .putString(KEY_NAME, name)
            .putString(KEY_URI, uri?.toString())
            .putString(KEY_PATTERN, pattern)
            .putString(KEY_KIND, kind ?: com.haoze.dnssr.data.entity.SubscriptionKind.UNIFIED)
            .putString(KEY_MIRROR_TEMPLATE, mirrorTemplate)
            .putBoolean(KEY_MIRROR_FALLBACK, mirrorFallback)
            .putLong(KEY_GROUP_ID, groupId)
            .putString(KEY_SCOPE, scope)
            .build()
        val builder = OneTimeWorkRequestBuilder<RuleOperationWorker>()
            .setInputData(input)
            .addTag(TAG)
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
        if (type in setOf(
                RuleOperationType.ADD_SUBSCRIPTION,
                RuleOperationType.EDIT_SUBSCRIPTION,
                RuleOperationType.UPDATE_SUBSCRIPTION,
                RuleOperationType.UPDATE_ALL_SUBSCRIPTIONS
            )
        ) {
            builder.setConstraints(
                Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build()
            )
        }
        return builder.build().also { request ->
            WorkManager.getInstance(context.applicationContext).enqueueUniqueWork(
                UNIQUE_WORK_NAME,
                ExistingWorkPolicy.APPEND_OR_REPLACE,
                request
            )
        }
    }
}

class RuleOperationWorker(
    context: Context,
    params: WorkerParameters
) : CoroutineWorker(context, params) {
    private val notificationManager = NotificationManagerCompat.from(context)
    private val notificationId = id.hashCode()
    private val completionNotificationId = notificationId xor COMPLETION_ID_MASK

    override suspend fun doWork(): Result = coroutineScope {
        val type = runCatching {
            RuleOperationType.valueOf(inputData.getString(RuleOperationScheduler.KEY_TYPE).orEmpty())
        }.getOrNull() ?: return@coroutineScope failure("未知的规则操作")
        val subscriptionId = inputData.getLong(RuleOperationScheduler.KEY_SUBSCRIPTION_ID, -1)
        val title = titleFor(type)
        createNotificationChannel()
        setForeground(createForegroundInfo(title, -1, 0))
        setProgress(progressData(type, subscriptionId, -1, 0))

        val database = AppDatabase.getInstance(applicationContext)
        val ruleScope = com.haoze.dnssr.data.entity.RuleScope.fromStorage(
            inputData.getString(RuleOperationScheduler.KEY_SCOPE).orEmpty()
        )
        val ruleIndexDirectory = java.io.File(applicationContext.filesDir, "rule-index").let {
            if (ruleScope == com.haoze.dnssr.data.entity.RuleScope.HTTPS) java.io.File(it, "https") else it
        }
        val blockManager = BlockListManager(database.blockRuleDao(), ruleIndexDirectory, ruleScope, reloadCacheAfterChanges = false)
        val allowManager = AllowListManager(database.allowRuleDao(), ruleIndexDirectory, ruleScope, reloadCacheAfterChanges = false)
        val rewriteManager = RewriteRuleManager(database.rewriteRuleDao(), ruleIndexDirectory, ruleScope, reloadCacheAfterChanges = false)
        val subscriptionManager = SubscriptionManager(
            database,
            database.subscriptionDao(),
            blockManager,
            allowManager,
            rewriteManager,
            ruleScope
        )
        var activeSubscriptionId = subscriptionId
        subscriptionManager.progressReporter = { current, total ->
            if (type != RuleOperationType.UPDATE_ALL_SUBSCRIPTIONS) {
                setProgressAsync(progressData(type, activeSubscriptionId, current, total))
                notifyProgress(title, current, total)
            }
        }
        val subscriptionIdJob = launch {
            subscriptionManager.importingSubscriptionId.collect { id ->
                if (id != null) {
                    activeSubscriptionId = id
                    setProgress(progressData(type, activeSubscriptionId, -1, 0))
                }
            }
        }

        try {
            val result = SubscriptionUpdateCoordinator.runManual {
                SubscriptionImportRecovery.recoverInterruptedImports(database)
                execute(type, subscriptionId, blockManager, allowManager, rewriteManager, subscriptionManager)
            }
            val message = result.message
            when (type) {
                RuleOperationType.ADD_BLOCK_RULE -> RuntimeDnsSettingsRefresher.syncRuleIfRunning(
                    applicationContext,
                    "block",
                    AdGuardRuleParser.parseLine(inputData.getString(RuleOperationScheduler.KEY_PATTERN).orEmpty())?.pattern.orEmpty(),
                    ruleScope
                )
                RuleOperationType.ADD_ALLOW_RULE -> RuntimeDnsSettingsRefresher.syncRuleIfRunning(
                    applicationContext,
                    "allow",
                    AdGuardRuleParser.parseAllowLine(inputData.getString(RuleOperationScheduler.KEY_PATTERN).orEmpty())?.pattern.orEmpty(),
                    ruleScope
                )
                RuleOperationType.IMPORT_ADDRESS_RULE_BACKUP -> {
                    RuntimeDnsSettingsRefresher.syncHttpsRequestRulesIfRunning(applicationContext)
                }
                RuleOperationType.ADD_SUBSCRIPTION,
                RuleOperationType.ADD_LOCAL_SUBSCRIPTION,
                RuleOperationType.EDIT_SUBSCRIPTION,
                RuleOperationType.UPDATE_SUBSCRIPTION,
                RuleOperationType.UPDATE_ALL_SUBSCRIPTIONS,
                RuleOperationType.IMPORT_RULES,
                RuleOperationType.IMPORT_HOSTS_RULES -> {
                    if (result.hasChanges) {
                        RuntimeDnsSettingsRefresher.refreshRuleIndexesIfRunning(
                            applicationContext,
                            refreshBlock = true,
                            refreshAllow = true,
                            refreshRewrite = true,
                            scope = ruleScope
                        )
                        RuntimeDnsSettingsRefresher.syncHttpsRequestRulesIfRunning(applicationContext)
                    }
                }
            }
            showFinishedNotification("$title 已完成", message)
            Result.success(
                workDataOf(
                    RuleOperationScheduler.KEY_SUCCESS to true,
                    RuleOperationScheduler.KEY_MESSAGE to message
                )
            )
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            val message = e.message ?: "操作失败"
            showFinishedNotification("$title 失败", message)
            Result.success(
                workDataOf(
                    RuleOperationScheduler.KEY_SUCCESS to false,
                    RuleOperationScheduler.KEY_MESSAGE to message
                )
            )
        } finally {
            subscriptionIdJob.cancel()
        }
    }

    private data class OperationExecutionResult(
        val message: String,
        val hasChanges: Boolean = true
    )

    private suspend fun execute(
        type: RuleOperationType,
        subscriptionId: Long,
        blockManager: BlockListManager,
        allowManager: AllowListManager,
        rewriteManager: RewriteRuleManager,
        subscriptionManager: SubscriptionManager
    ): OperationExecutionResult = when (type) {
        RuleOperationType.ADD_SUBSCRIPTION -> {
            val result = subscriptionManager.addSubscription(
                inputData.getString(RuleOperationScheduler.KEY_URL).orEmpty(),
                inputData.getString(RuleOperationScheduler.KEY_NAME),
                inputData.getString(RuleOperationScheduler.KEY_KIND) ?: com.haoze.dnssr.data.entity.SubscriptionKind.UNIFIED,
                inputData.getString(RuleOperationScheduler.KEY_MIRROR_TEMPLATE),
                inputData.getBoolean(RuleOperationScheduler.KEY_MIRROR_FALLBACK, true),
                inputData.getLong(RuleOperationScheduler.KEY_GROUP_ID, -1).takeIf { it >= 0 }
            )
            result.getOrThrow()
            OperationExecutionResult(subscriptionManager.latestImportSummary()?.displayMessage("导入成功") ?: "导入成功")
        }
        RuleOperationType.ADD_LOCAL_SUBSCRIPTION -> {
            val uri = requiredUri()
            val result = subscriptionManager.addLocalSubscription(
                uri.toString(),
                inputData.getString(RuleOperationScheduler.KEY_NAME).orEmpty(),
                inputData.getString(RuleOperationScheduler.KEY_KIND) ?: com.haoze.dnssr.data.entity.SubscriptionKind.UNIFIED
            ) { openUriReader(uri) }
            result.getOrThrow()
            OperationExecutionResult(subscriptionManager.latestImportSummary()?.displayMessage("导入成功") ?: "导入成功")
        }
        RuleOperationType.EDIT_SUBSCRIPTION -> {
            subscriptionManager.editSubscription(
                subscriptionId,
                inputData.getString(RuleOperationScheduler.KEY_URL).orEmpty(),
                inputData.getString(RuleOperationScheduler.KEY_NAME).orEmpty(),
                inputData.getString(RuleOperationScheduler.KEY_MIRROR_TEMPLATE),
                inputData.getBoolean(RuleOperationScheduler.KEY_MIRROR_FALLBACK, true),
                inputData.getLong(RuleOperationScheduler.KEY_GROUP_ID, -1).takeIf { it >= 0 }
            ).getOrThrow()
            OperationExecutionResult(subscriptionManager.latestImportSummary()?.displayMessage("订阅已保存") ?: "订阅已保存")
        }
        RuleOperationType.UPDATE_SUBSCRIPTION -> when (
            val outcome = subscriptionManager.updateSubscription(subscriptionId)
        ) {
            is SubscriptionUpdateOutcome.Updated -> OperationExecutionResult(
                subscriptionManager.latestImportSummary()
                    ?.displayMessage("更新成功") ?: "更新成功，共导入 ${outcome.ruleCount} 条规则",
                hasChanges = true
            )
            is SubscriptionUpdateOutcome.NotModified -> OperationExecutionResult("订阅已是最新", hasChanges = false)
            is SubscriptionUpdateOutcome.Failed -> throw IOException(outcome.error)
        }
        RuleOperationType.UPDATE_ALL_SUBSCRIPTIONS -> {
            var updated = 0
            var unchanged = 0
            var failed = 0
            var totalRules = 0
            val subscriptions = subscriptionManager.remoteSubscriptions()
            subscriptions.forEachIndexed { index, subscription ->
                setProgressAsync(progressData(type, subscription.id, index, subscriptions.size))
                notifyProgress(titleFor(type), index, subscriptions.size)
                when (val outcome = subscriptionManager.updateSubscription(subscription.id)) {
                    is SubscriptionUpdateOutcome.Updated -> {
                        updated++
                        totalRules += outcome.ruleCount
                    }
                    is SubscriptionUpdateOutcome.NotModified -> unchanged++
                    is SubscriptionUpdateOutcome.Failed -> failed++
                }
                setProgressAsync(progressData(type, subscription.id, index + 1, subscriptions.size))
                notifyProgress(titleFor(type), index + 1, subscriptions.size)
            }
            OperationExecutionResult(
                "检查完成：更新 $updated 个，已是最新 $unchanged 个，失败 $failed 个，共导入 $totalRules 条规则",
                hasChanges = updated > 0
            )
        }
        RuleOperationType.IMPORT_RULES -> {
            val msg = openUriReader(requiredUri()).use { reader ->
                importCategorizedRules(reader, blockManager, allowManager, rewriteManager, type)
            }.displayMessage("导入完成")
            OperationExecutionResult(msg)
        }
        RuleOperationType.IMPORT_HOSTS_RULES -> {
            val msg = openUriReader(requiredUri()).use { reader ->
                importHostsRules(reader, rewriteManager, type)
            }.let { summary ->
                "hosts 导入完成：新增 ${summary.rewriteCount} 条，跳过 ${summary.duplicateCount} 条"
            }
            OperationExecutionResult(msg)
        }
        RuleOperationType.IMPORT_ADDRESS_RULE_BACKUP -> {
            val backup = AddressRuleBackupCodec.decode(readUri(requiredUri()))
            val (block, allow) = AddressRuleBackupTransfer.restore(
                backup,
                GoUrlRuleManager(AppDatabase.getInstance(applicationContext).goUrlRuleDao())
            )
            OperationExecutionResult("恢复完成：URL 屏蔽 $block 条，URL 放行 $allow 条，跳过 ${backup.totalCount - block - allow} 条")
        }
        RuleOperationType.ADD_BLOCK_RULE -> {
            check(blockManager.addRule(inputData.getString(RuleOperationScheduler.KEY_PATTERN).orEmpty())) {
                "规则格式无效或规则已存在"
            }
            OperationExecutionResult("已添加到屏蔽规则")
        }
        RuleOperationType.ADD_ALLOW_RULE -> {
            check(allowManager.addRule(inputData.getString(RuleOperationScheduler.KEY_PATTERN).orEmpty())) {
                "规则格式无效或规则已存在"
            }
            OperationExecutionResult("已添加到白名单规则")
        }
    }

    private fun requiredUri(): Uri = inputData.getString(RuleOperationScheduler.KEY_URI)
        ?.let(Uri::parse) ?: throw IllegalArgumentException("缺少规则文件")

    private fun readUri(uri: Uri): String = applicationContext.contentResolver.openInputStream(uri)
        ?.bufferedReader()?.use { it.readText() }
        ?: throw IOException("无法读取所选文件")

    private fun openUriReader(uri: Uri): BufferedReader = applicationContext.contentResolver.openInputStream(uri)
        ?.bufferedReader()
        ?: throw IOException("无法读取所选文件")

    private suspend fun importCategorizedRules(
        reader: BufferedReader,
        blockManager: BlockListManager,
        allowManager: AllowListManager,
        rewriteManager: RewriteRuleManager,
        type: RuleOperationType
    ): RuleImportSummary {
        val importer = CategorizedRuleStreamImporter(blockManager, allowManager, rewriteManager, IMPORT_CHUNK_SIZE)
        return importer.import(
            reader = reader,
            source = LOCAL_IMPORT_SOURCE,
            enabled = true,
            refreshCache = true,
            onProgress = { processed ->
                setProgressAsync(progressData(type, -1, processed, 0))
                notifyProgress(titleFor(type), processed, 0)
            },
            onEmpty = { throw IllegalArgumentException("文件中没有可导入的有效规则") }
        )
    }

    private suspend fun importHostsRules(
        reader: BufferedReader,
        rewriteManager: RewriteRuleManager,
        type: RuleOperationType
    ): RuleImportSummary {
        val batch = ArrayList<RewriteRule>(IMPORT_CHUNK_SIZE)
        var inserted = 0
        var parsed = 0
        var processed = 0
        suspend fun flush() {
            if (batch.isEmpty()) return
            val insertedBatch = rewriteManager.addRules(batch, LOCAL_HOSTS_SOURCE, true, IMPORT_CHUNK_SIZE)
            inserted += insertedBatch
            processed += insertedBatch
            parsed += batch.size
            batch.clear()
            setProgressAsync(progressData(type, -1, processed, 0))
            notifyProgress(titleFor(type), processed, 0)
        }
        while (true) {
            val line = reader.readLine() ?: break
            AdGuardRuleParser.parseHostsRewriteLine(line).forEach { rule ->
                batch += rule
                if (batch.size == IMPORT_CHUNK_SIZE) flush()
            }
        }
        flush()
        require(parsed > 0) { "文件中没有可导入的真实 IP hosts 规则" }
        return RuleImportSummary(0, 0, inserted, (parsed - inserted).coerceAtLeast(0), 0, 0)
    }

    private fun progressData(type: RuleOperationType, subscriptionId: Long, current: Int, total: Int) =
        workDataOf(
            RuleOperationScheduler.KEY_TYPE to type.name,
            RuleOperationScheduler.KEY_SUBSCRIPTION_ID to subscriptionId,
            RuleOperationScheduler.KEY_CURRENT to current,
            RuleOperationScheduler.KEY_TOTAL to total
        )

    private fun failure(message: String) = Result.failure(
        workDataOf(RuleOperationScheduler.KEY_SUCCESS to false, RuleOperationScheduler.KEY_MESSAGE to message)
    )

    private fun titleFor(type: RuleOperationType): String = when (type) {
        RuleOperationType.ADD_SUBSCRIPTION, RuleOperationType.ADD_LOCAL_SUBSCRIPTION -> applicationContext.getString(R.string.operation_import_subscription)
        RuleOperationType.EDIT_SUBSCRIPTION -> applicationContext.getString(R.string.operation_save_subscription)
        RuleOperationType.UPDATE_SUBSCRIPTION -> applicationContext.getString(R.string.operation_update_subscription)
        RuleOperationType.UPDATE_ALL_SUBSCRIPTIONS -> applicationContext.getString(R.string.operation_update_all_subscriptions)
        RuleOperationType.IMPORT_RULES -> applicationContext.getString(R.string.operation_import_rules)
        RuleOperationType.IMPORT_HOSTS_RULES -> applicationContext.getString(R.string.operation_import_hosts_rules)
        RuleOperationType.IMPORT_ADDRESS_RULE_BACKUP -> applicationContext.getString(R.string.operation_restore_address_rules)
        RuleOperationType.ADD_BLOCK_RULE -> applicationContext.getString(R.string.operation_add_block_rule)
        RuleOperationType.ADD_ALLOW_RULE -> applicationContext.getString(R.string.operation_add_allow_rule)
    }

    private fun createForegroundInfo(title: String, current: Int, total: Int) = ForegroundInfo(
        notificationId,
        buildNotification(title, current, total, ongoing = true),
        ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
    )

    private fun notifyProgress(title: String, current: Int, total: Int) {
        notificationManager.notify(notificationId, buildNotification(title, current, total, ongoing = true))
    }

    private fun buildNotification(title: String, current: Int, total: Int, ongoing: Boolean) =
        NotificationCompat.Builder(applicationContext, CHANNEL_ID)
            .setSmallIcon(R.drawable.dns_svgrepo_com)
            .setContentTitle(localizedText(applicationContext, title))
            .setContentText(if (total > 0) "$current / $total" else applicationContext.getString(R.string.operation_preparing))
            .setProgress(total.coerceAtLeast(0), current.coerceAtLeast(0), total <= 0)
            .setOngoing(ongoing)
            .setOnlyAlertOnce(true)
            .setContentIntent(mainPendingIntent())
            .build()

    private fun showFinishedNotification(title: String, message: String) {
        val notification = NotificationCompat.Builder(applicationContext, CHANNEL_ID)
            .setSmallIcon(R.drawable.dns_svgrepo_com)
            .setContentTitle(localizedText(applicationContext, title))
            .setContentText(localizedText(applicationContext, message))
            .setStyle(NotificationCompat.BigTextStyle().bigText(localizedText(applicationContext, message)))
            .setAutoCancel(true)
            .setContentIntent(mainPendingIntent())
            .build()
        if (com.haoze.dnssr.notification.NotificationPermissionHelper.hasPermission(applicationContext)) {
            notificationManager.notify(completionNotificationId, notification)
        }
    }

    private fun mainPendingIntent(): PendingIntent = PendingIntent.getActivity(
        applicationContext,
        notificationId,
        Intent(applicationContext, MainActivity::class.java),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )

    private fun createNotificationChannel() {
        val manager = applicationContext.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, applicationContext.getString(R.string.rule_update_channel), NotificationManager.IMPORTANCE_LOW)
        )
    }

    private companion object {
        const val CHANNEL_ID = "rule_operations"
        const val LOCAL_IMPORT_SOURCE = "local_import"
        const val LOCAL_HOSTS_SOURCE = "local_hosts"
        const val COMPLETION_ID_MASK = 0x40000000
        const val IMPORT_CHUNK_SIZE = 1000
    }
}
