package com.haoze.diting.vpn

import android.util.Log
import com.haoze.diting.data.dao.SubscriptionDao
import com.haoze.diting.data.entity.SubscriptionEntity
import com.haoze.diting.data.entity.SubscriptionKind
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import java.io.File
import java.util.concurrent.TimeUnit

internal class SubscriptionDownloader(
    private val subscriptionDao: SubscriptionDao,
    private val ruleStreamer: CategorizedRuleStreamImporter,
    private val ruleStorage: SubscriptionRuleStorage,
    private val client: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .build(),
    private val cacheDir: File? = null
) {
    companion object {
        private const val TAG = "SubscriptionDownloader"
    }

    private fun createTempFile(prefix: String): File {
        return if (cacheDir != null && (cacheDir.exists() || cacheDir.mkdirs())) {
            File.createTempFile(prefix, ".tmp", cacheDir)
        } else {
            File.createTempFile(prefix, ".tmp")
        }
    }

    suspend fun downloadAndImport(
        url: String,
        subscriptionId: Long,
        kind: String,
        enabled: Boolean,
        onProgressUpdate: (suspend (current: Int, totalHint: Int) -> Unit)? = null
    ): Result<InitialImportResult> = withContext(Dispatchers.IO) {
        try {
            val subscription = subscriptionDao.byId(subscriptionId) ?: SubscriptionEntity(url = url, name = url, kind = kind)
            Result.success(
                downloadAndImportStreaming(subscription, subscriptionId, kind, enabled, onProgressUpdate)
            )
        } catch (e: Exception) {
            Log.e(TAG, "下载导入失败: $url", e)
            Result.failure(e)
        }
    }

    private suspend fun downloadAndImportStreaming(
        subscription: SubscriptionEntity,
        subscriptionId: Long,
        kind: String,
        enabled: Boolean,
        onProgressUpdate: (suspend (current: Int, totalHint: Int) -> Unit)?
    ): InitialImportResult {
        val mirrorUrl = subscription.mirrorTemplate?.let {
            SubscriptionUrlHelper.buildMirrorUrl(it, subscription.url)
        }
        if (mirrorUrl != null) {
            try {
                return downloadAndImportStreamingAt(subscription, subscriptionId, kind, enabled, mirrorUrl, onProgressUpdate)
            } catch (e: Exception) {
                if (!subscription.mirrorFallback || e is CancellationException) throw e
                Log.w(TAG, "镜像下载失败，回退原始订阅地址: $mirrorUrl", e)
                ruleStorage.removeSubscriptionRules(subscriptionId)
            }
        }
        return downloadAndImportStreamingAt(subscription, subscriptionId, kind, enabled, subscription.url, onProgressUpdate)
    }

    private suspend fun downloadAndImportStreamingAt(
        subscription: SubscriptionEntity,
        subscriptionId: Long,
        kind: String,
        enabled: Boolean,
        requestUrl: String,
        onProgressUpdate: (suspend (current: Int, totalHint: Int) -> Unit)?
    ): InitialImportResult {
        val request = Request.Builder().url(requestUrl).build()
        return client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) throw httpFailure(response)
            val body = response.body ?: throw SubscriptionUpdateException("订阅响应为空", retryable = false)
            val tempFile = createTempFile("sub_import_${subscriptionId}_")
            try {
                tempFile.outputStream().use { out ->
                    body.byteStream().copyTo(out)
                }
                val badfilterKeys = tempFile.bufferedReader().use { reader ->
                    AdGuardRuleParser.extractBadfilterKeys(reader)
                }
                val totalRules = tempFile.bufferedReader().use { reader ->
                    CategorizedRuleStreamImporter.countRules(reader, badfilterKeys)
                }
                val summary = tempFile.bufferedReader().use { reader ->
                    ruleStreamer.import(
                        reader = reader,
                        source = ruleStorage.sourceTag(subscriptionId),
                        kind = kind,
                        enabled = enabled,
                        totalHint = totalRules,
                        badfilterKeys = badfilterKeys,
                        onEmpty = { typeMismatchOnly -> throw emptySourceException(typeMismatchOnly, kind) },
                        onProgress = onProgressUpdate
                    )
                }
                ruleStorage.refreshAllCaches()
                val finalTotal = if (totalRules > 0) totalRules else summary.importedCount
                onProgressUpdate?.invoke(finalTotal, finalTotal)
                InitialImportResult(
                    ruleCount = summary.importedCount,
                    ruleSetHash = null,
                    etag = response.header("ETag"),
                    lastModified = response.header("Last-Modified"),
                    summary = summary
                )
            } finally {
                tempFile.delete()
            }
        }
    }

    suspend fun downloadAndStage(
        subscription: SubscriptionEntity,
        subscriptionId: Long,
        enabled: Boolean,
        useValidators: Boolean,
        onProgressUpdate: (suspend (current: Int, totalHint: Int) -> Unit)? = null
    ): StreamingDownloadResult {
        val stagingSource = ruleStorage.stagingSourceTag(subscriptionId)
        val kind = SubscriptionKind.normalize(subscription.kind)
        ruleStorage.removeRulesBySource(stagingSource)
        val mirrorUrl = subscription.mirrorTemplate?.let {
            SubscriptionUrlHelper.buildMirrorUrl(it, subscription.url)
        }
        if (mirrorUrl != null) {
            try {
                return downloadAndStageAt(subscription, stagingSource, kind, enabled, mirrorUrl, useValidators, onProgressUpdate)
            } catch (e: Exception) {
                if (!subscription.mirrorFallback || e is CancellationException) throw e
                Log.w(TAG, "镜像下载失败，回退原始订阅地址: $mirrorUrl", e)
                ruleStorage.removeRulesBySource(stagingSource)
            }
        }
        return downloadAndStageAt(subscription, stagingSource, kind, enabled, subscription.url, useValidators, onProgressUpdate)
    }

    private suspend fun downloadAndStageAt(
        subscription: SubscriptionEntity,
        stagingSource: String,
        kind: String,
        enabled: Boolean,
        requestUrl: String,
        useValidators: Boolean,
        onProgressUpdate: (suspend (current: Int, totalHint: Int) -> Unit)?
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
                return@use downloadAndStageAt(subscription, stagingSource, kind, enabled, requestUrl, useValidators = false, onProgressUpdate)
            }
            if (!response.isSuccessful) throw httpFailure(response)
            val body = response.body ?: throw SubscriptionUpdateException("订阅响应为空", retryable = false)
            val tempFile = createTempFile("sub_stage_${subscription.id}_")
            try {
                tempFile.outputStream().use { out ->
                    body.byteStream().copyTo(out)
                }
                val badfilterKeys = tempFile.bufferedReader().use { reader ->
                    AdGuardRuleParser.extractBadfilterKeys(reader)
                }
                val totalRules = tempFile.bufferedReader().use { reader ->
                    CategorizedRuleStreamImporter.countRules(reader, badfilterKeys)
                }
                val summary = tempFile.bufferedReader().use { reader ->
                    ruleStreamer.import(
                        reader = reader,
                        source = stagingSource,
                        kind = kind,
                        enabled = enabled,
                        totalHint = totalRules,
                        badfilterKeys = badfilterKeys,
                        onEmpty = { typeMismatchOnly -> throw emptySourceException(typeMismatchOnly, kind) },
                        onProgress = onProgressUpdate
                    )
                }
                val finalTotal = if (totalRules > 0) totalRules else summary.importedCount
                onProgressUpdate?.invoke(finalTotal, finalTotal)
                StreamingDownloadResult.Content(
                    summary,
                    response.header("ETag"),
                    response.header("Last-Modified")
                )
            } finally {
                tempFile.delete()
            }
        }
    }

    private fun httpFailure(response: Response): SubscriptionUpdateException {
        val retryable = response.code in setOf(408, 425, 429) || response.code in 500..599
        return SubscriptionUpdateException("HTTP ${response.code}", retryable)
    }

    /**
     * Distinguishes "this source holds nothing of the requested type" from
     * "this source holds nothing usable at all" — the first one is almost
     * always a subscription type mismatch.
     */
    private fun emptySourceException(
        typeMismatchOnly: Boolean,
        kind: String
    ): SubscriptionUpdateException {
        val message = if (typeMismatchOnly) {
            "订阅中没有${SubscriptionKind.displayName(kind)}，请确认订阅类型是否选错"
        } else {
            "订阅中没有可导入的有效规则"
        }
        return SubscriptionUpdateException(message, retryable = false)
    }
}
