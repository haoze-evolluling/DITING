package com.haoze.dnssr.vpn

import android.util.Log
import androidx.room.withTransaction
import com.haoze.dnssr.data.AppDatabase
import com.haoze.dnssr.data.dao.SubscriptionDao
import com.haoze.dnssr.data.entity.SubscriptionEntity
import com.haoze.dnssr.data.entity.SubscriptionImportState
import com.haoze.dnssr.data.entity.SubscriptionKind
import com.haoze.dnssr.data.entity.SubscriptionSourceType
import com.haoze.dnssr.data.entity.RuleScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.ResponseBody
import java.io.BufferedReader
import java.io.FilterInputStream
import java.io.IOException
import java.io.InputStream
import java.io.Reader
import java.net.URLEncoder
import java.net.URI
import java.util.concurrent.TimeUnit

data class RuleImportSummary(
    val blockCount: Int,
    val allowCount: Int,
    val rewriteCount: Int = 0,
    val duplicateCount: Int,
    val invalidCount: Int,
    val unsupportedCount: Int
) {
    val importedCount: Int get() = blockCount + allowCount + rewriteCount
    val skippedCount: Int get() = duplicateCount + invalidCount + unsupportedCount

    fun displayMessage(prefix: String): String =
        "$prefix：黑名单 $blockCount 条，白名单 $allowCount 条，覆写 $rewriteCount 条，重复 $duplicateCount 条，" +
            "无效/不支持 ${invalidCount + unsupportedCount} 条"
}

sealed interface SubscriptionUpdateOutcome {
    data class Updated(val ruleCount: Int) : SubscriptionUpdateOutcome
    data class NotModified(val ruleCount: Int) : SubscriptionUpdateOutcome
    data class Failed(val error: String, val retryable: Boolean) : SubscriptionUpdateOutcome
}

private sealed interface StreamingDownloadResult {
    data class NotModified(val etag: String?, val lastModified: String?) : StreamingDownloadResult
    data class Content(
        val summary: RuleImportSummary,
        val etag: String?,
        val lastModified: String?
    ) : StreamingDownloadResult
}

private class SubscriptionUpdateException(
    message: String,
    val retryable: Boolean,
    cause: Throwable? = null
) : Exception(message, cause)

private data class InitialImportResult(
    val ruleCount: Int,
    val ruleSetHash: String?,
    val etag: String?,
    val lastModified: String?
)

private class LimitedInputStream(
    input: InputStream,
    private val limit: Long,
) : FilterInputStream(input) {
    private var bytesRead = 0L

    override fun read(): Int {
        val value = super.read()
        if (value >= 0) checkLimit(1)
        return value
    }

    override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
        if (length == 0) return 0
        val allowed = minOf(length.toLong(), limit - bytesRead + 1L).coerceAtLeast(1L).toInt()
        val count = super.read(buffer, offset, allowed)
        if (count > 0) checkLimit(count.toLong())
        return count
    }

    private fun checkLimit(read: Long) {
        bytesRead += read
        if (bytesRead > limit) throw IOException("订阅内容超过大小限制")
    }
}

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
        private const val CHUNK_SIZE = 500
        private const val MAX_SUBSCRIPTION_URL_LENGTH = 4_096
        private const val MAX_SUBSCRIPTION_BYTES = 32L * 1024L * 1024L
        private const val MAX_RULE_LINE_CHARS = 64 * 1024
        private const val MAX_IMPORTED_RULES = 500_000
        private val MIRROR_PLACEHOLDERS = setOf(
            "{url}", "{urlEncoded}", "{scheme}", "{host}", "{path}", "{pathAndQuery}"
        )
    }

    private val client = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .callTimeout(2, TimeUnit.MINUTES)
        .build()

    private val _importing = MutableStateFlow(false)
    val importing: StateFlow<Boolean> = _importing.asStateFlow()

    private val _importingSubscriptionId = MutableStateFlow<Long?>(null)
    val importingSubscriptionId: StateFlow<Long?> = _importingSubscriptionId.asStateFlow()

    @Volatile
    private var lastImportSummary: RuleImportSummary? = null

    fun latestImportSummary(): RuleImportSummary? = lastImportSummary

    /**
     * 添加新订阅并下载导入规则。
     */
    suspend fun addSubscription(
        url: String,
        name: String? = null,
        kind: String = SubscriptionKind.BLOCK,
        mirrorTemplate: String? = null,
        mirrorFallback: Boolean = true,
        groupId: Long? = null
    ): Result<SubscriptionEntity> = withContext(Dispatchers.IO) {
        if (_importing.value) return@withContext Result.failure(IllegalStateException("正在导入中"))
        val trimmedUrl = url.trim()
        if (!isValidSubscriptionUrl(trimmedUrl)) {
            return@withContext Result.failure(IllegalArgumentException("订阅链接必须使用 HTTP 或 HTTPS"))
        }
        if (subscriptionDao.byUrlAndScope(trimmedUrl, scope.storageValue) != null) {
            return@withContext Result.failure(IllegalArgumentException("该订阅链接已存在"))
        }
        val normalizedKind = kind
        val normalizedMirror = normalizeMirrorTemplate(mirrorTemplate)

        _importing.value = true
        var saved: SubscriptionEntity? = null
        try {
            val displayName = name?.trim()?.takeIf { it.isNotEmpty() } ?: extractNameFromUrl(trimmedUrl)
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
                scope = scope.storageValue,
                groupId = groupId
            )
            val id = subscriptionDao.insert(subscription)
            saved = subscription.copy(id = id)
            _importingSubscriptionId.value = id

            val importResult = downloadAndImport(
                url = trimmedUrl,
                subscriptionId = id,
                enabled = true
            )
            if (importResult.isFailure) {
                removeRulesBySource(sourceTag(id))
                val error = importResult.exceptionOrNull() ?: Exception("导入失败")
                subscriptionDao.setImportState(id, SubscriptionImportState.FAILED, error.message)
                return@withContext Result.failure(error)
            }

            val imported = importResult.getOrThrow()
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
                removeRulesBySource(sourceTag(subscription.id))
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
    suspend fun addRemoteSubscription(url: String, name: String, groupId: Long? = null): Result<SubscriptionEntity> =
        withContext(Dispatchers.IO) {
            val trimmedUrl = url.trim()
            val trimmedName = name.trim()
            if (trimmedName.isEmpty()) {
                return@withContext Result.failure(IllegalArgumentException("订阅名称不能为空"))
            }
            if (!isValidSubscriptionUrl(trimmedUrl)) {
                return@withContext Result.failure(IllegalArgumentException("订阅链接必须使用 HTTP 或 HTTPS"))
            }
            if (subscriptionDao.byUrlAndScope(trimmedUrl, scope.storageValue) != null) {
                return@withContext Result.failure(IllegalArgumentException("该订阅链接已存在"))
            }

            try {
                val subscription = SubscriptionEntity(
                    url = trimmedUrl,
                    name = trimmedName,
                    sourceType = SubscriptionSourceType.REMOTE,
                    kind = SubscriptionKind.BLOCK,
                    enabled = true,
                    scope = scope.storageValue,
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
        kind: String = SubscriptionKind.BLOCK,
        contentLoader: () -> Reader
    ): Result<SubscriptionEntity> = withContext(Dispatchers.IO) {
        if (_importing.value) return@withContext Result.failure(IllegalStateException("正在导入中"))

        val trimmedName = name.trim()
        if (trimmedName.isEmpty()) {
            return@withContext Result.failure(IllegalArgumentException("订阅名称不能为空"))
        }
        val normalizedKind = kind
        if (subscriptionDao.byUrlAndScope(sourceRef, scope.storageValue) != null) {
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
                ,scope = scope.storageValue
            )
            val id = subscriptionDao.insert(subscription)
            saved = subscription.copy(id = id)
            _importingSubscriptionId.value = id

            val summary = contentLoader().buffered().use { reader ->
                streamRules(reader, kind, sourceTag(id), enabled = true)
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
            Result.success(completed)
        } catch (e: Exception) {
            saved?.let { subscription ->
                removeRulesBySource(sourceTag(subscription.id))
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

    suspend fun renameSubscription(id: Long, name: String): Result<Unit> =
        withContext(Dispatchers.IO) {
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
    ): Result<SubscriptionEntity> =
        withContext(Dispatchers.IO) {
            val trimmedName = name.trim()
            val trimmedUrl = url.trim()
            val normalizedMirror = normalizeMirrorTemplate(mirrorTemplate)
            if (trimmedName.isEmpty() || trimmedUrl.isEmpty()) {
                return@withContext Result.failure(IllegalArgumentException("Subscription name and URL are required"))
            }
            if (!isValidSubscriptionUrl(trimmedUrl)) {
                return@withContext Result.failure(IllegalArgumentException("Subscription URL must use HTTP or HTTPS"))
            }
            if (_importing.value) {
                return@withContext Result.failure(IllegalStateException("A subscription import is already running"))
            }

            val subscription = subscriptionDao.byId(id)
                ?: return@withContext Result.failure(IllegalArgumentException("Subscription does not exist"))
            if (subscription.scope != scope.storageValue) {
                return@withContext Result.failure(IllegalArgumentException("订阅不属于当前规则范围"))
            }
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
            val duplicate = subscriptionDao.byUrlAndScope(trimmedUrl, scope.storageValue)
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
                val summary: RuleImportSummary
                val etag: String?
                val lastModified: String?
                val download = downloadAndStage(
                    pending.copy(httpEtag = null, httpLastModified = null, ruleSetHash = null),
                    id,
                    subscription.enabled,
                    useValidators = false
                ) as StreamingDownloadResult.Content
                summary = download.summary
                etag = download.etag
                lastModified = download.lastModified
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
                publishStagedRules(id, subscription.kind, updated)
                Result.success(updated)
            } catch (e: CancellationException) {
                markUpdateCancelled(id)
                throw e
            } catch (e: Exception) {
                Log.e(TAG, "Failed to edit subscription", e)
                removeRulesBySource(stagingSourceTag(id))
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
        if (subscription.scope != scope.storageValue) {
            return@withContext SubscriptionUpdateOutcome.Failed("订阅不属于当前规则范围", retryable = false)
        }
        if (subscription.sourceType == SubscriptionSourceType.LOCAL) {
            return@withContext SubscriptionUpdateOutcome.Failed("本地文件订阅无法更新", retryable = false)
        }

        _importing.value = true
        _importingSubscriptionId.value = id
        subscriptionDao.setImportState(id, SubscriptionImportState.IMPORTING, null)
        try {
            when (val download = downloadAndStage(subscription, id, subscription.enabled, useValidators = true)) {
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
                        publishStagedRules(id, subscription.kind, updated)
                        SubscriptionUpdateOutcome.Updated(download.summary.importedCount)
                    }
            }
        } catch (e: CancellationException) {
            markUpdateCancelled(id)
            throw e
        } catch (e: SubscriptionUpdateException) {
            Log.e(TAG, "更新订阅失败", e)
            removeRulesBySource(stagingSourceTag(id))
            subscriptionDao.markUpdateFailed(
                id,
                SubscriptionImportState.FAILED,
                e.message ?: "更新失败",
                System.currentTimeMillis()
            )
            SubscriptionUpdateOutcome.Failed(e.message ?: "更新失败", e.retryable)
        } catch (e: Exception) {
            Log.e(TAG, "更新订阅失败", e)
            removeRulesBySource(stagingSourceTag(id))
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
        require(subscription.scope == scope.storageValue) { "订阅不属于当前规则范围" }
        val source = sourceTag(id)
        removeRulesBySource(source)
        subscriptionDao.deleteById(id)
    }

    suspend fun setSubscriptionEnabled(id: Long, enabled: Boolean): Result<Unit> =
        withContext(Dispatchers.IO) {
            val subscription = subscriptionDao.byId(id)
                ?: return@withContext Result.failure(IllegalArgumentException("订阅不存在"))
            if (subscription.scope != scope.storageValue) {
                return@withContext Result.failure(IllegalArgumentException("订阅不属于当前规则范围"))
            }

            try {
                val source = sourceTag(id)
                blockListManager.setRulesEnabledBySource(source, enabled)
                allowListManager.setRulesEnabledBySource(source, enabled)
                rewriteRuleManager.setRulesEnabledBySource(source, enabled)
                subscriptionDao.setEnabled(id, enabled)
                Result.success(Unit)
            } catch (e: Exception) {
                Log.e(TAG, "切换订阅状态失败", e)
                Result.failure(e)
            }
        }

    suspend fun allSubscriptions(): List<SubscriptionEntity> = subscriptionDao.allByScope(scope.storageValue)

    suspend fun remoteSubscriptions(): List<SubscriptionEntity> = subscriptionDao.allRemoteByScope(scope.storageValue)

    suspend fun enabledRemoteSubscriptions(): List<SubscriptionEntity> = subscriptionDao.allEnabledRemote()

    fun sourceTag(subscriptionId: Long): String = "sub_$subscriptionId"

    private fun stagingSourceTag(subscriptionId: Long): String = "staging_sub_$subscriptionId"

    private suspend fun markUpdateCancelled(subscriptionId: Long) {
        withContext(NonCancellable) {
            removeRulesBySource(stagingSourceTag(subscriptionId))
            subscriptionDao.setImportState(
                subscriptionId,
                SubscriptionImportState.FAILED,
                "更新已取消，已保留原有规则"
            )
        }
    }

    private suspend fun downloadAndImport(
        url: String,
        subscriptionId: Long,
        enabled: Boolean
    ): Result<InitialImportResult> =
        withContext(Dispatchers.IO) {
            try {
                val subscription = subscriptionDao.byId(subscriptionId) ?: SubscriptionEntity(url = url, name = url)
                return@withContext Result.success(
                    downloadAndImportStreaming(subscription, subscriptionId, enabled)
                )
            } catch (e: Exception) {
                Log.e(TAG, "下载导入失败: $url", e)
                Result.failure(e)
            }
        }

    private suspend fun downloadAndImportStreaming(
        subscription: SubscriptionEntity,
        subscriptionId: Long,
        enabled: Boolean
    ): InitialImportResult {
        val mirrorUrl = subscription.mirrorTemplate?.let { buildMirrorUrl(it, subscription.url) }
        if (mirrorUrl != null) {
            try {
                return downloadAndImportStreamingAt(subscription, subscriptionId, enabled, mirrorUrl)
            } catch (e: Exception) {
                if (!subscription.mirrorFallback || e is CancellationException) throw e
                Log.w(TAG, "镜像下载失败，回退原始订阅地址: $mirrorUrl", e)
                removeRulesBySource(sourceTag(subscriptionId))
            }
        }
        return downloadAndImportStreamingAt(subscription, subscriptionId, enabled, subscription.url)
    }

    private suspend fun downloadAndImportStreamingAt(
        subscription: SubscriptionEntity,
        subscriptionId: Long,
        enabled: Boolean,
        requestUrl: String
    ): InitialImportResult {
        val request = Request.Builder().url(requestUrl).build()
        return client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) throw httpFailure(response)
            val body = response.body ?: throw SubscriptionUpdateException("订阅响应为空", retryable = false)
            val summary = limitedReader(body).use { reader ->
                streamRules(reader, subscription.kind, sourceTag(subscriptionId), enabled)
            }
            lastImportSummary = summary
            InitialImportResult(
                ruleCount = summary.importedCount,
                ruleSetHash = null,
                etag = response.header("ETag"),
                lastModified = response.header("Last-Modified")
            )
        }
    }

    private suspend fun streamCategorizedRules(
        reader: BufferedReader,
        source: String,
        enabled: Boolean
    ): RuleImportSummary {
        val blockBatch = ArrayList<AdGuardRuleParser.ParsedRule>(CHUNK_SIZE)
        val allowBatch = ArrayList<AdGuardRuleParser.ParsedRule>(CHUNK_SIZE)
        var insertedBlock = 0
        var insertedAllow = 0
        var parsedRules = 0
        var invalid = 0
        var unsupported = 0

        suspend fun flushBlock() {
            if (blockBatch.isEmpty()) return
            insertedBlock += blockListManager.addRulesBatch(blockBatch, source, CHUNK_SIZE, enabled)
            blockBatch.clear()
        }

        suspend fun flushAllow() {
            if (allowBatch.isEmpty()) return
            insertedAllow += allowListManager.addRulesBatch(allowBatch, source, CHUNK_SIZE, enabled)
            allowBatch.clear()
        }

        while (true) {
            currentCoroutineContext().ensureActive()
            val line = reader.readLine() ?: break
            if (line.length > MAX_RULE_LINE_CHARS) {
                throw SubscriptionUpdateException("订阅规则行超过长度限制", retryable = false)
            }
            val parsed = AdGuardRuleParser.parseCategorizedLine(line)
            invalid += parsed.invalidCount
            unsupported += parsed.unsupportedCount
            parsedRules += parsed.blockRules.size + parsed.allowRules.size
            if (parsedRules > MAX_IMPORTED_RULES) {
                throw SubscriptionUpdateException("订阅规则数量超过限制", retryable = false)
            }
            for (rule in parsed.blockRules) {
                blockBatch += rule
                if (blockBatch.size == CHUNK_SIZE) flushBlock()
            }
            for (rule in parsed.allowRules) {
                allowBatch += rule
                if (allowBatch.size == CHUNK_SIZE) flushAllow()
            }
        }
        flushBlock()
        flushAllow()

        if (parsedRules == 0) {
            throw SubscriptionUpdateException("订阅中没有可导入的有效 DNS 规则", retryable = false)
        }
        return RuleImportSummary(
            blockCount = insertedBlock,
            allowCount = insertedAllow,
            duplicateCount = (parsedRules - insertedBlock - insertedAllow).coerceAtLeast(0),
            invalidCount = invalid,
            unsupportedCount = unsupported
        )
    }

    private suspend fun streamRules(
        reader: BufferedReader,
        kind: String,
        source: String,
        enabled: Boolean
    ): RuleImportSummary = if (kind == SubscriptionKind.REWRITE) {
        streamRewriteRules(reader, source, enabled)
    } else {
        streamCategorizedRules(reader, source, enabled)
    }

    private suspend fun streamRewriteRules(reader: BufferedReader, source: String, enabled: Boolean): RuleImportSummary {
        val batch = ArrayList<RewriteRule>(CHUNK_SIZE)
        var inserted = 0
        var parsed = 0
        suspend fun flush() {
            if (batch.isEmpty()) return
            inserted += rewriteRuleManager.addRules(batch, source, enabled, CHUNK_SIZE)
            batch.clear()
        }
        while (true) {
            currentCoroutineContext().ensureActive()
            val line = reader.readLine() ?: break
            if (line.length > MAX_RULE_LINE_CHARS) {
                throw SubscriptionUpdateException("订阅规则行超过长度限制", retryable = false)
            }
            for (rule in AdGuardRuleParser.parseHostsRewriteLine(line)) {
                batch += rule
                parsed++
                if (parsed > MAX_IMPORTED_RULES) {
                    throw SubscriptionUpdateException("订阅规则数量超过限制", retryable = false)
                }
                if (batch.size == CHUNK_SIZE) flush()
            }
        }
        flush()
        if (parsed == 0) throw SubscriptionUpdateException("订阅中没有可导入的有效 hosts 规则", retryable = false)
        return RuleImportSummary(0, 0, inserted, (parsed - inserted).coerceAtLeast(0), 0, 0)
    }

    private suspend fun downloadAndStage(
        subscription: SubscriptionEntity,
        subscriptionId: Long,
        enabled: Boolean,
        useValidators: Boolean
    ): StreamingDownloadResult {
        val stagingSource = stagingSourceTag(subscriptionId)
        removeRulesBySource(stagingSource)
        val mirrorUrl = subscription.mirrorTemplate?.let { buildMirrorUrl(it, subscription.url) }
        if (mirrorUrl != null) {
            try {
                return downloadAndStageAt(subscription, stagingSource, enabled, mirrorUrl, useValidators)
            } catch (e: Exception) {
                if (!subscription.mirrorFallback || e is CancellationException) throw e
                Log.w(TAG, "镜像下载失败，回退原始订阅地址: $mirrorUrl", e)
                removeRulesBySource(stagingSource)
            }
        }
        return downloadAndStageAt(subscription, stagingSource, enabled, subscription.url, useValidators)
    }

    private suspend fun downloadAndStageAt(
        subscription: SubscriptionEntity,
        stagingSource: String,
        enabled: Boolean,
        requestUrl: String,
        useValidators: Boolean
    ): StreamingDownloadResult {
        val request = Request.Builder().url(requestUrl).apply {
            if (useValidators) {
                subscription.httpEtag?.let { header("If-None-Match", it) }
                subscription.httpLastModified?.let { header("If-Modified-Since", it) }
            }
        }.build()
        return client.newCall(request).execute().use { response ->
            if (response.code == 304) {
                return@use StreamingDownloadResult.NotModified(response.header("ETag"), response.header("Last-Modified"))
            }
            if (response.code == 412 && useValidators) {
                return@use downloadAndStageAt(subscription, stagingSource, enabled, requestUrl, useValidators = false)
            }
            if (!response.isSuccessful) throw httpFailure(response)
            val body = response.body ?: throw SubscriptionUpdateException("订阅响应为空", retryable = false)
            StreamingDownloadResult.Content(
                limitedReader(body).use { reader ->
                    streamRules(reader, subscription.kind, stagingSource, enabled)
                },
                response.header("ETag"),
                response.header("Last-Modified")
            )
        }
    }

    private suspend fun publishStagedRules(
        subscriptionId: Long,
        kind: String,
        completedSubscription: SubscriptionEntity
    ) {
        val source = sourceTag(subscriptionId)
        val stagingSource = stagingSourceTag(subscriptionId)
        database.withTransaction {
            if (kind == SubscriptionKind.REWRITE) {
                rewriteRuleManager.promoteRulesBySource(stagingSource, source, refreshCache = false)
            } else {
                blockListManager.promoteRulesBySource(stagingSource, source, refreshCache = false)
                allowListManager.promoteRulesBySource(stagingSource, source, refreshCache = false)
            }
            subscriptionDao.update(completedSubscription)
        }
        if (kind == SubscriptionKind.REWRITE) {
            rewriteRuleManager.refreshCacheAfterExternalChange()
        } else {
            blockListManager.refreshCacheAfterExternalChange()
            allowListManager.refreshCacheAfterExternalChange()
        }
    }


    private fun normalizeMirrorTemplate(template: String?): String? {
        val normalized = template?.trim()?.takeIf { it.isNotEmpty() } ?: return null
        require(MIRROR_PLACEHOLDERS.any { it in normalized }) {
            "镜像模板必须包含 {url}、{urlEncoded}、{scheme}、{host}、{path} 或 {pathAndQuery}"
        }
        buildMirrorUrl(normalized, "https://example.com/rules.txt")
        return normalized
    }

    private fun buildMirrorUrl(template: String, originalUrl: String): String {
        val encoded = URLEncoder.encode(originalUrl, Charsets.UTF_8.name()).replace("+", "%20")
        val uri = runCatching { URI(originalUrl) }.getOrElse {
            throw IllegalArgumentException("原始订阅地址格式无效", it)
        }
        val path = uri.rawPath?.takeIf { it.isNotEmpty() } ?: "/"
        val pathAndQuery = path + (uri.rawQuery?.let { "?$it" } ?: "")
        val result = template
            .replace("{urlEncoded}", encoded)
            .replace("{url}", originalUrl)
            .replace("{scheme}", uri.scheme.orEmpty())
            .replace("{host}", uri.host.orEmpty())
            .replace("{pathAndQuery}", pathAndQuery)
            .replace("{path}", path)
        require(result.startsWith("https://") || result.startsWith("http://")) {
            "镜像模板生成的地址必须使用 HTTP 或 HTTPS"
        }
        require(isValidSubscriptionUrl(result)) { "镜像模板生成的地址无效" }
        return result
    }

    private fun limitedReader(body: ResponseBody): BufferedReader =
        LimitedInputStream(body.byteStream(), MAX_SUBSCRIPTION_BYTES).bufferedReader(Charsets.UTF_8)

    private fun isValidSubscriptionUrl(value: String): Boolean {
        if (value.length > MAX_SUBSCRIPTION_URL_LENGTH) return false
        val uri = runCatching { URI(value) }.getOrNull() ?: return false
        return uri.scheme?.lowercase() in setOf("http", "https") &&
            !uri.host.isNullOrBlank() &&
            uri.userInfo == null &&
            uri.fragment == null
    }

    private fun httpFailure(response: Response): SubscriptionUpdateException {
        val retryable = response.code in setOf(408, 425, 429) || response.code in 500..599
        return SubscriptionUpdateException("HTTP ${response.code}", retryable)
    }


    private suspend fun removeRulesBySource(source: String) {
        blockListManager.removeRulesBySource(source)
        allowListManager.removeRulesBySource(source)
        rewriteRuleManager.removeRulesBySource(source)
    }

    private fun extractNameFromUrl(url: String): String {
        return try {
            val uri = URI(url)
            val path = uri.path ?: ""
            val fileName = path.substringAfterLast('/')
            if (fileName.isNotBlank()) fileName else uri.host ?: url
        } catch (_: Exception) {
            url
        }
    }
}
