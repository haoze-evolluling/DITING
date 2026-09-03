package com.haoze.dnssr.vpn

import android.util.Log
import com.haoze.dnssr.data.dao.SubscriptionDao
import com.haoze.dnssr.data.entity.SubscriptionEntity
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import java.io.StringReader
import java.util.concurrent.TimeUnit

internal class SubscriptionDownloader(
    private val subscriptionDao: SubscriptionDao,
    private val ruleStreamer: SubscriptionRuleStreamer,
    private val ruleStorage: SubscriptionRuleStorage,
    private val client: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .build()
) {
    companion object {
        private const val TAG = "SubscriptionDownloader"
    }

    suspend fun downloadAndImport(
        url: String,
        subscriptionId: Long,
        enabled: Boolean,
        onProgressUpdate: (suspend (current: Int, totalHint: Int) -> Unit)? = null
    ): Result<InitialImportResult> = withContext(Dispatchers.IO) {
        try {
            val subscription = subscriptionDao.byId(subscriptionId) ?: SubscriptionEntity(url = url, name = url)
            Result.success(
                downloadAndImportStreaming(subscription, subscriptionId, enabled, onProgressUpdate)
            )
        } catch (e: Exception) {
            Log.e(TAG, "下载导入失败: $url", e)
            Result.failure(e)
        }
    }

    private suspend fun downloadAndImportStreaming(
        subscription: SubscriptionEntity,
        subscriptionId: Long,
        enabled: Boolean,
        onProgressUpdate: (suspend (current: Int, totalHint: Int) -> Unit)?
    ): InitialImportResult {
        val mirrorUrl = subscription.mirrorTemplate?.let {
            SubscriptionUrlHelper.buildMirrorUrl(it, subscription.url)
        }
        if (mirrorUrl != null) {
            try {
                return downloadAndImportStreamingAt(subscription, subscriptionId, enabled, mirrorUrl, onProgressUpdate)
            } catch (e: Exception) {
                if (!subscription.mirrorFallback || e is CancellationException) throw e
                Log.w(TAG, "镜像下载失败，回退原始订阅地址: $mirrorUrl", e)
                ruleStorage.removeSubscriptionRules(subscriptionId)
            }
        }
        return downloadAndImportStreamingAt(subscription, subscriptionId, enabled, subscription.url, onProgressUpdate)
    }

    private suspend fun downloadAndImportStreamingAt(
        subscription: SubscriptionEntity,
        subscriptionId: Long,
        enabled: Boolean,
        requestUrl: String,
        onProgressUpdate: (suspend (current: Int, totalHint: Int) -> Unit)?
    ): InitialImportResult {
        var progressTotalHint = subscription.ruleCount
        val request = Request.Builder().url(requestUrl).build()
        return client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) throw httpFailure(response)
            val body = response.body ?: throw SubscriptionUpdateException("订阅响应为空", retryable = false)
            val content = body.string()
            progressTotalHint = SubscriptionUrlHelper.countRules(content)
            val summary = StringReader(content).buffered().use { reader ->
                ruleStreamer.streamRules(reader, ruleStorage.sourceTag(subscriptionId), enabled) { processed ->
                    onProgressUpdate?.invoke(processed, maxOf(processed, progressTotalHint))
                }
            }
            ruleStorage.refreshAllCaches()
            onProgressUpdate?.invoke(summary.importedCount, maxOf(summary.importedCount, progressTotalHint))
            InitialImportResult(
                ruleCount = summary.importedCount,
                ruleSetHash = null,
                etag = response.header("ETag"),
                lastModified = response.header("Last-Modified"),
                summary = summary
            )
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
        ruleStorage.removeRulesBySource(stagingSource)
        val mirrorUrl = subscription.mirrorTemplate?.let {
            SubscriptionUrlHelper.buildMirrorUrl(it, subscription.url)
        }
        if (mirrorUrl != null) {
            try {
                return downloadAndStageAt(subscription, stagingSource, enabled, mirrorUrl, useValidators, onProgressUpdate)
            } catch (e: Exception) {
                if (!subscription.mirrorFallback || e is CancellationException) throw e
                Log.w(TAG, "镜像下载失败，回退原始订阅地址: $mirrorUrl", e)
                ruleStorage.removeRulesBySource(stagingSource)
            }
        }
        return downloadAndStageAt(subscription, stagingSource, enabled, subscription.url, useValidators, onProgressUpdate)
    }

    private suspend fun downloadAndStageAt(
        subscription: SubscriptionEntity,
        stagingSource: String,
        enabled: Boolean,
        requestUrl: String,
        useValidators: Boolean,
        onProgressUpdate: (suspend (current: Int, totalHint: Int) -> Unit)?
    ): StreamingDownloadResult {
        var progressTotalHint = subscription.ruleCount
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
                return@use downloadAndStageAt(subscription, stagingSource, enabled, requestUrl, useValidators = false, onProgressUpdate)
            }
            if (!response.isSuccessful) throw httpFailure(response)
            val body = response.body ?: throw SubscriptionUpdateException("订阅响应为空", retryable = false)
            val content = body.string()
            progressTotalHint = SubscriptionUrlHelper.countRules(content)
            val summary = StringReader(content).buffered().use { reader ->
                ruleStreamer.streamRules(reader, stagingSource, enabled) { processed ->
                    onProgressUpdate?.invoke(processed, maxOf(processed, progressTotalHint))
                }
            }
            onProgressUpdate?.invoke(summary.importedCount, maxOf(summary.importedCount, progressTotalHint))
            StreamingDownloadResult.Content(
                summary,
                response.header("ETag"),
                response.header("Last-Modified")
            )
        }
    }

    private fun httpFailure(response: Response): SubscriptionUpdateException {
        val retryable = response.code in setOf(408, 425, 429) || response.code in 500..599
        return SubscriptionUpdateException("HTTP ${response.code}", retryable)
    }
}
