package com.haoze.diting.ui.batch

/**
 * Target list for batch rule addition.
 */
enum class BatchRuleTarget(val title: String, val singularName: String) {
    BLACKLIST("批量添加黑名单规则", "黑名单"),
    WHITELIST("批量添加白名单规则", "白名单"),
    REWRITE("批量添加覆写规则", "覆写名单")
}

/**
 * Represents the parsed result of a single line in batch input.
 */
sealed class BatchRuleItem {
    abstract val lineNumber: Int
    abstract val rawLine: String

    data class ValidDomain(
        override val lineNumber: Int,
        override val rawLine: String,
        val pattern: String,
        val appScope: String? = null,
        val important: Boolean = false,
        val isWildcard: Boolean = false,
        val denyallow: String? = null,
        val isRegex: Boolean = false,
        val dnsType: String? = null
    ) : BatchRuleItem()

    data class ValidUrl(
        override val lineNumber: Int,
        override val rawLine: String,
        val urlPattern: String,
        val isAllow: Boolean
    ) : BatchRuleItem()

    data class ValidRewrite(
        override val lineNumber: Int,
        override val rawLine: String,
        val domain: String,
        val targetType: String,
        val targetValue: String
    ) : BatchRuleItem()

    data class Duplicate(
        override val lineNumber: Int,
        override val rawLine: String,
        val ruleKey: String,
        val reason: String
    ) : BatchRuleItem()

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
    val target: BatchRuleTarget,
    val totalLines: Int,
    val validItems: List<BatchRuleItem>,
    val duplicateItems: List<BatchRuleItem.Duplicate>,
    val invalidItems: List<BatchRuleItem.Invalid>,
    val ignoredCount: Int
) {
    val validCount: Int get() = validItems.size
    val duplicateCount: Int get() = duplicateItems.size
    val invalidCount: Int get() = invalidItems.size
}
