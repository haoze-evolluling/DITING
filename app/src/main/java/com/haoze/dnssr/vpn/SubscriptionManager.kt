package com.haoze.dnssr.vpn

import android.util.Log
import com.haoze.dnssr.data.AppDatabase
import com.haoze.dnssr.data.dao.SubscriptionDao
import com.haoze.dnssr.data.entity.RuleScope
import com.haoze.dnssr.data.entity.SubscriptionEntity
import com.haoze.dnssr.data.entity.SubscriptionImportState
import com.haoze.dnssr.data.entity.SubscriptionKind
import com.haoze.dnssr.data.entity.SubscriptionSourceType
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import java.io.Reader

/**
 * 规则订阅管理器。
 *
 * 负责下载、解析、导入和删除订阅规则。
 * 使用分块批量导入避免大规则列表导致卡顿。
 */
class SubscriptionManager(
    private val database: AppDatabase,
    private val subscriptionDao: SubscriptionDao,
    private val blockListManager: BlockListManager,
    private val allowListManager: AllowListManager,
    private val rewriteRuleManager: RewriteRuleManager,
    private val scope: RuleScope = RuleScope.DNS
) {
    companion object {
        private const val TAG = "SubscriptionManager"
    }

    private val ruleStorage = SubscriptionRuleStorage(
        database,
        subscriptionDao,
        blockListManager,
        allowListManager,
        rewriteRuleManager
    )

    private val ruleStreamer = CategorizedRuleStreamImporter(
        blockListManager,
        allowListManager,
        rewriteRuleManager
    )

    private val downloader = SubscriptionDownloader(
        subscriptionDao,
        ruleStreamer,
        ruleStorage
    )

    private val _importing = MutableStateFlow(false)
    val importing: StateFlow<Boolean> = _importing.asStateFlow()

    private val _importingSubscriptionId = MutableStateFlow<Long?>(null)
    val importingSubscriptionId: StateFlow<Long?> = _importingSubscriptionId.asStateFlow()

    @Volatile
    private var lastImportSummary: RuleImportSummary? = null

    @Volatile
    var progressReporter: (suspend (current: Int, total: Int) -> Unit)? = null

    fun latestImportSummary(): RuleImportSummary? = lastImportSummary

    fun sourceTag(subscriptionId: Long): String = ruleStorage.sourceTag(subscriptionId)

    /**
     * 添加新订阅并下载导入规则。
     */
    suspend fun addSubscription(
        url: String,
        name: String? = null,
        kind: String = SubscriptionKind.UNIFIED,
        mirrorTemplate: String? = null,
        mirrorFallback: Boolean = true,
        groupId: Long? = null
    ): Result<SubscriptionEntity> = withContext(Dispatchers.IO) {
        if (_importing.value) return@withContext Result.failure(IllegalStateException("正在导入中"))
        val trimmedUrl = url.trim()
        if (!trimmedUrl.startsWith("https://") && !trimmedUrl.startsWith("http://")) {
            return@withContext Result.failure(IllegalArgumentException("订阅链接必须使用 HTTP 或 HTTPS"))
        }
        if (subscriptionDao.byUrl(trimmedUrl) != null) {
            return@withContext Result.failure(IllegalArgumentException("该订阅链接已存在"))
        }
        val normalizedKind = kind
        val normalizedMirror = SubscriptionUrlHelper.normalizeMirrorTemplate(mirrorTemplate)

        _importing.value = true
        var saved: SubscriptionEntity? = null
        try {
            val displayName = name?.trim()?.takeIf { it.isNotEmpty() }
                ?: SubscriptionUrlHelper.extractNameFromUrl(trimmedUrl)
            val subscription = SubscriptionEntity(
                url = trimmedUrl,
                name = displayName,
                sourceType = SubscriptionSourceType.REMOTE,
                kind = normalizedKind,
                enabled = true,
                ruleCount = 0,
                lastUpdated = 0,
                addedAt = System.currentTimeMillis(),
                importState = SubscriptionImportState.IMPORTING,
                mirrorTemplate = normalizedMirror,
                mirrorFallback = mirrorFallback,
                groupId = groupId
            )
            val id = subscriptionDao.insert(subscription)
            saved = subscription.copy(id = id)
            _importingSubscriptionId.value = id

            val importResult = downloader.downloadAndImport(
                url = trimmedUrl,
                subscriptionId = id,
                enabled = true,
                onProgressUpdate = { current, total -> progressReporter?.invoke(current, total) }
            )
            if (importResult.isFailure) {
                ruleStorage.removeSubscriptionRules(id)
                val error = importResult.exceptionOrNull() ?: Exception("导入失败")
                subscriptionDao.setImportState(id, SubscriptionImportState.FAILED, error.message)
                return@withContext Result.failure(error)
            }

            val imported = importResult.getOrThrow()
            lastImportSummary = imported.summary
            val completed = saved.copy(
                ruleCount = imported.ruleCount,
                lastUpdated = System.currentTimeMillis(),
                importState = SubscriptionImportState.READY,
                importError = null,
                httpEtag = imported.etag,
                httpLastModified = imported.lastModified,
                ruleSetHash = imported.ruleSetHash,
                lastAttemptAt = System.currentTimeMillis(),
                consecutiveFailureCount = 0
            )
            subscriptionDao.update(completed)
            Result.success(completed)
        } catch (e: Exception) {
            Log.e(TAG, "添加订阅失败", e)
            saved?.let { subscription ->
                ruleStorage.removeSubscriptionRules(subscription.id)
                subscriptionDao.setImportState(
                    subscription.id,
                    SubscriptionImportState.FAILED,
                    e.message ?: "导入失败"
                )
            }
            Result.failure(e)
        } finally {
            _importing.value = false
            _importingSubscriptionId.value = null
        }
    }

    /** Saves a remote subscription without downloading its rules. */
    suspend fun addRemoteSubscription(
        url: String,
        name: String,
        groupId: Long? = null,
        kind: String = SubscriptionKind.UNIFIED,
        mirrorTemplate: String? = null,
        mirrorFallback: Boolean = true
    ): Result<SubscriptionEntity> = withContext(Dispatchers.IO) {
        val trimmedUrl = url.trim()
        val trimmedName = name.trim()
        if (trimmedName.isEmpty()) {
            return@withContext Result.failure(IllegalArgumentException("订阅名称不能为空"))
        }
        if (!trimmedUrl.startsWith("https://") && !trimmedUrl.startsWith("http://")) {
            return@withContext Result.failure(IllegalArgumentException("订阅链接必须使用 HTTP 或 HTTPS"))
        }
        if (subscriptionDao.byUrl(trimmedUrl) != null) {
            return@withContext Result.failure(IllegalArgumentException("该订阅链接已存在"))
        }

        try {
            val subscription = SubscriptionEntity(
                url = trimmedUrl,
                name = trimmedName,
                sourceType = SubscriptionSourceType.REMOTE,
                kind = kind,
                mirrorTemplate = mirrorTemplate,
                mirrorFallback = mirrorFallback,
                enabled = true,
                groupId = groupId
            )
            Result.success(subscription.copy(id = subscriptionDao.insert(subscription)))
        } catch (e: Exception) {
            Log.e(TAG, "保存订阅失败", e)
            Result.failure(e)
        }
    }

    suspend fun addLocalSubscription(
        sourceRef: String,
        name: String,
        kind: String = SubscriptionKind.UNIFIED,
        contentLoader: () -> Reader
    ): Result<SubscriptionEntity> = withContext(Dispatchers.IO) {
        if (_importing.value) return@withContext Result.failure(IllegalStateException("正在导入中"))

        val trimmedName = name.trim()
        if (trimmedName.isEmpty()) {
            return@withContext Result.failure(IllegalArgumentException("订阅名称不能为空"))
        }
        val normalizedKind = kind
        if (subscriptionDao.byUrl(sourceRef) != null) {
            return@withContext Result.failure(IllegalArgumentException("该文件已作为订阅导入"))
        }

        _importing.value = true
        var saved: SubscriptionEntity? = null
        try {
            val subscription = SubscriptionEntity(
                url = sourceRef,
                name = trimmedName,
                sourceType = SubscriptionSourceType.LOCAL,
                kind = normalizedKind,
                enabled = true,
                ruleCount = 0,
                lastUpdated = 0,
                addedAt = System.currentTimeMillis(),
                importState = SubscriptionImportState.IMPORTING
            )
            val id = subscriptionDao.insert(subscription)
            saved = subscription.copy(id = id)
            _importingSubscriptionId.value = id

            val summary = contentLoader().buffered().use { reader ->
                ruleStreamer.import(
                    reader,
                    ruleStorage.sourceTag(id),
                    enabled = true,
                    onEmpty = { throw SubscriptionUpdateException("订阅中没有可导入的有效规则", retryable = false) }
                ) { processed ->
                    progressReporter?.invoke(processed, processed)
                }
            }
            lastImportSummary = summary

            val importedAt = System.currentTimeMillis()
            val completed = saved.copy(
                ruleCount = summary.importedCount,
                lastUpdated = importedAt,
                importState = SubscriptionImportState.READY,
                importError = null
            )
            subscriptionDao.update(completed)
            ruleStorage.refreshAllCaches()
            Result.success(completed)
        } catch (e: Exception) {
            saved?.let { subscription ->
                ruleStorage.removeSubscriptionRules(subscription.id)
                subscriptionDao.setImportState(
                    subscription.id,
                    SubscriptionImportState.FAILED,
                    e.message ?: "导入失败"
                )
            }
            Log.e(TAG, "本地文件订阅导入失败", e)
            Result.failure(e)
        } finally {
            _importing.value = false
            _importingSubscriptionId.value = null
        }
    }

    suspend fun renameSubscription(id: Long, name: String): Result<Unit> = withContext(Dispatchers.IO) {
        val trimmed = name.trim()
        if (trimmed.isEmpty()) {
            return@withContext Result.failure(IllegalArgumentException("订阅名称不能为空"))
        }
        val subscription = subscriptionDao.byId(id)
            ?: return@withContext Result.failure(IllegalArgumentException("订阅不存在"))
        try {
            subscriptionDao.setName(subscription.id, trimmed)
            Result.success(Unit)
        } catch (e: Exception) {
            Log.e(TAG, "重命名订阅失败", e)
            Result.failure(e)
        }
    }

    /**
     * 更新订阅（删除旧规则后重新下载导入）。
     */
    suspend fun editSubscription(
        id: Long,
        url: String,
        name: String,
        mirrorTemplate: String? = null,
        mirrorFallback: Boolean = true,
        groupId: Long? = null
    ): Result<SubscriptionEntity> = withContext(Dispatchers.IO) {
        val trimmedName = name.trim()
        val trimmedUrl = url.trim()
        val normalizedMirror = SubscriptionUrlHelper.normalizeMirrorTemplate(mirrorTemplate)
        if (trimmedName.isEmpty() || trimmedUrl.isEmpty()) {
            return@withContext Result.failure(IllegalArgumentException("Subscription name and URL are required"))
        }
        if (!trimmedUrl.startsWith("https://") && !trimmedUrl.startsWith("http://")) {
            return@withContext Result.failure(IllegalArgumentException("Subscription URL must use HTTP or HTTPS"))
        }
        if (_importing.value) {
            return@withContext Result.failure(IllegalStateException("A subscription import is already running"))
        }

        val subscription = subscriptionDao.byId(id)
            ?: return@withContext Result.failure(IllegalArgumentException("Subscription does not exist"))
        if (subscription.sourceType == SubscriptionSourceType.LOCAL) {
            return@withContext Result.failure(IllegalStateException("本地文件订阅仅支持重命名"))
        }
        if (subscription.url == trimmedUrl &&
            subscription.mirrorTemplate == normalizedMirror &&
            subscription.mirrorFallback == mirrorFallback
        ) {
            subscriptionDao.update(subscription.copy(name = trimmedName, groupId = groupId))
            return@withContext Result.success(subscription.copy(name = trimmedName, groupId = groupId))
        }
        val duplicate = subscriptionDao.byUrl(trimmedUrl)
        if (duplicate != null && duplicate.id != id) {
            return@withContext Result.failure(IllegalArgumentException("This subscription URL already exists"))
        }

        _importing.value = true
        _importingSubscriptionId.value = id
        subscriptionDao.setImportState(id, SubscriptionImportState.IMPORTING, null)
        val pending = subscription.copy(
            name = trimmedName,
            url = trimmedUrl,
            mirrorTemplate = normalizedMirror,
            mirrorFallback = mirrorFallback,
            groupId = groupId,
            importState = SubscriptionImportState.IMPORTING,
            importError = null
        )
        // Preserve the saved source configuration even when its immediate refresh fails.
        subscriptionDao.update(pending)
        try {
            val download = downloader.downloadAndStage(
                pending.copy(httpEtag = null, httpLastModified = null, ruleSetHash = null),
                id,
                subscription.enabled,
                useValidators = false,
                onProgressUpdate = { current, total -> progressReporter?.invoke(current, total) }
            ) as StreamingDownloadResult.Content
            val summary = download.summary
            val etag = download.etag
            val lastModified = download.lastModified
            lastImportSummary = summary

            val updatedAt = System.currentTimeMillis()
            val updated = subscription.copy(
                name = trimmedName,
                url = trimmedUrl,
                mirrorTemplate = normalizedMirror,
                mirrorFallback = mirrorFallback,
                groupId = groupId,
                ruleCount = summary.importedCount,
                lastUpdated = updatedAt,
                importState = SubscriptionImportState.READY,
                importError = null,
                httpEtag = etag,
                httpLastModified = lastModified,
                ruleSetHash = null,
                lastAttemptAt = updatedAt,
                consecutiveFailureCount = 0
            )
            ruleStorage.publishStagedRules(id, updated)
            Result.success(updated)
        } catch (e: CancellationException) {
            ruleStorage.markUpdateCancelled(id)
            throw e
        } catch (e: Exception) {
            Log.e(TAG, "Failed to edit subscription", e)
            ruleStorage.removeStagingRules(id)
            subscriptionDao.setImportState(
                id,
                SubscriptionImportState.FAILED,
                e.message ?: "更新失败"
            )
            Result.failure(e)
        } finally {
            _importing.value = false
            _importingSubscriptionId.value = null
        }
    }

    suspend fun updateSubscription(id: Long): SubscriptionUpdateOutcome = withContext(Dispatchers.IO) {
        if (_importing.value) {
            return@withContext SubscriptionUpdateOutcome.Failed("正在导入中", retryable = false)
        }

        val subscription = subscriptionDao.byId(id)
            ?: return@withContext SubscriptionUpdateOutcome.Failed("订阅不存在", retryable = false)
        if (subscription.sourceType == SubscriptionSourceType.LOCAL) {
            return@withContext SubscriptionUpdateOutcome.Failed("本地文件订阅无法更新", retryable = false)
        }

        _importing.value = true
        _importingSubscriptionId.value = id
        subscriptionDao.setImportState(id, SubscriptionImportState.IMPORTING, null)
        try {
            when (
                val download = downloader.downloadAndStage(
                    subscription,
                    id,
                    subscription.enabled,
                    useValidators = true,
                    onProgressUpdate = { current, total -> progressReporter?.invoke(current, total) }
                )
            ) {
                is StreamingDownloadResult.NotModified -> {
                    subscriptionDao.markNotModified(
                        id,
                        SubscriptionImportState.READY,
                        System.currentTimeMillis(),
                        download.etag ?: subscription.httpEtag,
                        download.lastModified ?: subscription.httpLastModified
                    )
                    SubscriptionUpdateOutcome.NotModified(subscription.ruleCount)
                }
                is StreamingDownloadResult.Content -> {
                    lastImportSummary = download.summary
                    val now = System.currentTimeMillis()
                    val updated = subscription.copy(
                        ruleCount = download.summary.importedCount,
                        lastUpdated = now,
                        importState = SubscriptionImportState.READY,
                        importError = null,
                        httpEtag = download.etag,
                        httpLastModified = download.lastModified,
                        ruleSetHash = null,
                        lastAttemptAt = now,
                        consecutiveFailureCount = 0
                    )
                    ruleStorage.publishStagedRules(id, updated)
                    SubscriptionUpdateOutcome.Updated(download.summary.importedCount)
                }
            }
        } catch (e: CancellationException) {
            ruleStorage.markUpdateCancelled(id)
            throw e
        } catch (e: SubscriptionUpdateException) {
            Log.e(TAG, "更新订阅失败", e)
            ruleStorage.removeStagingRules(id)
            subscriptionDao.markUpdateFailed(
                id,
                SubscriptionImportState.FAILED,
                e.message ?: "更新失败",
                System.currentTimeMillis()
            )
            SubscriptionUpdateOutcome.Failed(e.message ?: "更新失败", e.retryable)
        } catch (e: Exception) {
            Log.e(TAG, "更新订阅失败", e)
            ruleStorage.removeStagingRules(id)
            subscriptionDao.markUpdateFailed(
                id,
                SubscriptionImportState.FAILED,
                e.message ?: "更新失败",
                System.currentTimeMillis()
            )
            SubscriptionUpdateOutcome.Failed(e.message ?: "更新失败", retryable = true)
        } finally {
            _importing.value = false
            _importingSubscriptionId.value = null
        }
    }

    /**
     * 删除订阅及其关联的所有规则。
     */
    suspend fun deleteSubscription(id: Long) = withContext(Dispatchers.IO) {
        val subscription = subscriptionDao.byId(id)
            ?: throw IllegalArgumentException("订阅不存在")
        ruleStorage.removeSubscriptionRules(id)
        subscriptionDao.deleteById(id)
    }

    suspend fun setSubscriptionEnabled(id: Long, enabled: Boolean): Result<Unit> = withContext(Dispatchers.IO) {
        val subscription = subscriptionDao.byId(id)
            ?: return@withContext Result.failure(IllegalArgumentException("订阅不存在"))

        try {
            ruleStorage.setSubscriptionRulesEnabled(id, enabled)
            subscriptionDao.setEnabled(id, enabled)
            Result.success(Unit)
        } catch (e: Exception) {
            Log.e(TAG, "切换订阅状态失败", e)
            Result.failure(e)
        }
    }

    suspend fun allSubscriptions(): List<SubscriptionEntity> = subscriptionDao.all()

    suspend fun remoteSubscriptions(): List<SubscriptionEntity> = subscriptionDao.allRemote()

    suspend fun enabledRemoteSubscriptions(): List<SubscriptionEntity> = subscriptionDao.allEnabledRemote()
}
