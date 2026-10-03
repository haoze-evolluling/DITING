package com.haoze.diting.ui.batch

/**
 * Recognition mode for plain domains and general batch import behavior.
 */
enum class BatchRecognitionMode(val title: String, val description: String) {
    AUTO("智能识别", "按语法自动识别，普通域名归入黑名单"),
    WHITELIST_FIRST("白名单优先", "普通域名归入白名单，保留语法识别"),
    BLACKLIST_FIRST("黑名单优先", "普通域名归入黑名单，保留语法识别");

    companion object {
        fun fromTarget(target: BatchRuleTarget?): BatchRecognitionMode = when (target) {
            BatchRuleTarget.WHITELIST -> WHITELIST_FIRST
            BatchRuleTarget.BLACKLIST -> BLACKLIST_FIRST
            else -> AUTO
        }
    }
}

/**
 * Target list for batch rule addition (kept for navigation hints and backward compatibility).
 */
enum class BatchRuleTarget(val title: String, val singularName: String) {
    BLACKLIST("批量添加黑名单规则", "黑名单"),
    WHITELIST("批量添加白名单规则", "白名单"),
    REWRITE("批量添加覆写规则", "覆写名单")
}

/**
 * Category enum for a valid batch rule.
 */
enum class BatchRuleCategory(val displayName: String) {
    BLOCK("黑名单"),
    ALLOW("白名单"),
    REWRITE("覆写")
}

/**
 * Represents the parsed result of a single line in batch input.
 */
sealed class BatchRuleItem {
    abstract val lineNumber: Int
    abstract val rawLine: String

    open val category: BatchRuleCategory? get() = null

    data class ValidDomain(
        override val lineNumber: Int,
        override val rawLine: String,
        val pattern: String,
        val isAllow: Boolean = false,
        val appScope: String? = null,
        val important: Boolean = false,
        val isWildcard: Boolean = false,
        val denyallow: String? = null,
        val isRegex: Boolean = false,
        val dnsType: String? = null
    ) : BatchRuleItem() {
        override val category: BatchRuleCategory
            get() = if (isAllow) BatchRuleCategory.ALLOW else BatchRuleCategory.BLOCK
    }

    data class ValidUrl(
        override val lineNumber: Int,
        override val rawLine: String,
        val urlPattern: String,
        val isAllow: Boolean
    ) : BatchRuleItem() {
        override val category: BatchRuleCategory
            get() = if (isAllow) BatchRuleCategory.ALLOW else BatchRuleCategory.BLOCK
    }

    data class ValidCosmetic(
        override val lineNumber: Int,
        override val rawLine: String,
        val domain: String,
        val selector: String,
        val isException: Boolean = false
    ) : BatchRuleItem() {
        override val category: BatchRuleCategory
            get() = if (isException) BatchRuleCategory.ALLOW else BatchRuleCategory.BLOCK
    }

    data class ValidRewrite(
        override val lineNumber: Int,
        override val rawLine: String,
        val domain: String,
        val targetType: String,
        val targetValue: String
    ) : BatchRuleItem() {
        override val category: BatchRuleCategory
            get() = BatchRuleCategory.REWRITE
    }

    data class Duplicate(
        override val lineNumber: Int,
        override val rawLine: String,
        val ruleKey: String,
        val reason: String,
        val duplicateCategory: BatchRuleCategory? = null
    ) : BatchRuleItem() {
        override val category: BatchRuleCategory? get() = duplicateCategory
    }

    data class Invalid(
        override val lineNumber: Int,
        override val rawLine: String,
        val reason: String
    ) : BatchRuleItem()

    data class Ignored(
        override val lineNumber: Int,
        override val rawLine: String
    ) : BatchRuleItem()
}

/**
 * Summary of batch validation results.
 */
data class BatchValidationSummary(
    val target: BatchRuleTarget = BatchRuleTarget.BLACKLIST,
    val mode: BatchRecognitionMode = BatchRecognitionMode.AUTO,
    val totalLines: Int,
    val validItems: List<BatchRuleItem>,
    val duplicateItems: List<BatchRuleItem.Duplicate>,
    val invalidItems: List<BatchRuleItem.Invalid>,
    val ignoredCount: Int
) {
    val validCount: Int get() = validItems.size
    val duplicateCount: Int get() = duplicateItems.size
    val invalidCount: Int get() = invalidItems.size

    val blockCount: Int get() = validItems.count { it.category == BatchRuleCategory.BLOCK }
    val allowCount: Int get() = validItems.count { it.category == BatchRuleCategory.ALLOW }
    val rewriteCount: Int get() = validItems.count { it.category == BatchRuleCategory.REWRITE }
}

/**
 * Summary of batch commit execution.
 */
data class BatchCommitResult(
    val blockInserted: Int = 0,
    val allowInserted: Int = 0,
    val rewriteInserted: Int = 0
) {
    val totalInserted: Int get() = blockInserted + allowInserted + rewriteInserted
}
