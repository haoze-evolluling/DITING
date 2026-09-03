package com.haoze.dnssr.vpn

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

internal sealed interface StreamingDownloadResult {
    data class NotModified(val etag: String?, val lastModified: String?) : StreamingDownloadResult
    data class Content(
        val summary: RuleImportSummary,
        val etag: String?,
        val lastModified: String?
    ) : StreamingDownloadResult
}

internal class SubscriptionUpdateException(
    message: String,
    val retryable: Boolean,
    cause: Throwable? = null
) : Exception(message, cause)

internal data class InitialImportResult(
    val ruleCount: Int,
    val ruleSetHash: String?,
    val etag: String?,
    val lastModified: String?,
    val summary: RuleImportSummary? = null
)
