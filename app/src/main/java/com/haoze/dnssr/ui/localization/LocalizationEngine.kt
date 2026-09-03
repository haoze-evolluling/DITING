package com.haoze.dnssr.ui.localization

import android.content.Context

/**
 * 国际化翻译核心引擎，按序调度：
 * 1. Android 系统资源标识符哈希匹配 (`context.resources.getIdentifier`)；
 * 2. 各领域模块的快速静态词典查找 (`translate*Exact`)；
 * 3. 各领域模块的动态模板与模式转换 (`translate*Pattern`)；
 * 4. 兜底返回原文本。
 */
object LocalizationEngine {

    internal fun stableTextResourceName(text: String): String {
        var hash = 0
        text.forEach { character -> hash = 31 * hash + character.code }
        return "localized_text_${hash.toLong().and(0x7fffffff)}"
    }

    /**
     * 将输入文本翻译为英文。
     */
    fun translate(text: String, context: Context): String {
        // 1. Android string resource lookup
        val resourceId = context.resources.getIdentifier(
            stableTextResourceName(text),
            "string",
            context.packageName
        )
        if (resourceId != 0) return context.getString(resourceId)

        // 2. Exact match dictionary lookup across domain modules
        translateExact(text)?.let { return it }

        // 3. Dynamic pattern transformations
        return translatePatterns(text) ?: text
    }

    internal fun translateExact(text: String): String? {
        return translateHomeAndOverviewExact(text)
            ?: translateDnsResolutionExact(text)
            ?: translateRulesAndSubscriptionExact(text)
            ?: translateHttpInspectionExact(text)
            ?: translateAppManagementExact(text)
            ?: translateSettingsAndAppearanceExact(text)
            ?: translateLogsAndStatsExact(text)
            ?: translateAboutAndUpdateExact(text)
            ?: translateCommonExact(text)
    }

    private fun translatePatterns(text: String): String? {
        return translateHomeAndOverviewPattern(text)
            ?: translateDnsResolutionPattern(text)
            ?: translateRulesAndSubscriptionPattern(text)
            ?: translateHttpInspectionPattern(text)
            ?: translateAppManagementPattern(text)
            ?: translateSettingsAndAppearancePattern(text)
            ?: translateLogsAndStatsPattern(text)
            ?: translateAboutAndUpdatePattern(text)
            ?: translateDynamicPattern(text)
    }
}
