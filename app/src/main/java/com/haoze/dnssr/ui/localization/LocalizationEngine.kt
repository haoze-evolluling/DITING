package com.haoze.dnssr.ui.localization

import android.content.Context

/**
 * Core localization engine. Resolves a translation in the following order:
 * 1. Hash matching against Android system resource identifiers (`context.resources.getIdentifier`);
 * 2. Fast static dictionary lookup in each domain module (`translate*Exact`);
 * 3. Dynamic templates and pattern conversions in each domain module (`translate*Pattern`);
 * 4. Falls back to returning the original text.
 */
object LocalizationEngine {

    internal fun stableTextResourceName(text: String): String {
        var hash = 0
        text.forEach { character -> hash = 31 * hash + character.code }
        return "localized_text_${hash.toLong().and(0x7fffffff)}"
    }

    /**
     * Translates the given text into English.
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
            ?: translateNetworkToolsExact(text)
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
            ?: translateNetworkToolsPattern(text)
            ?: translateRulesAndSubscriptionPattern(text)
            ?: translateHttpInspectionPattern(text)
            ?: translateAppManagementPattern(text)
            ?: translateSettingsAndAppearancePattern(text)
            ?: translateLogsAndStatsPattern(text)
            ?: translateAboutAndUpdatePattern(text)
            ?: translateDynamicPattern(text)
    }
}
