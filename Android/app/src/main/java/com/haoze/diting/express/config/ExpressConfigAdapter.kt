package com.haoze.diting.express.config

import android.content.Context
import com.haoze.diting.ui.ConfigExportSelection
import com.haoze.diting.ui.ConfigImportProgress
import com.haoze.diting.ui.ConfigImportResult
import com.haoze.diting.ui.settings.AppRulesSettingsStore
import com.haoze.diting.ui.transfer.ConfigExporter
import com.haoze.diting.ui.transfer.ConfigImporter
import com.haoze.diting.ui.transfer.ConfigTransferParser
import com.haoze.diting.ui.transfer.TransferConfig

/**
 * Adapter ensuring clean, isolated configuration export and import for Express Mode.
 *
 * Express Mode operates exclusively on DNS 窄路由 and physically omits:
 * - Outbound Proxy (出站代理)
 * - Domain/CNAME Rewrite Rules (覆写规则)
 * - URL Path / Address Rules (URL 路径规则)
 * - Excluded Apps (排除应用)
 * - Blocked Apps (禁止联网应用)
 * - App Allowlist (应用放行名单)
 * - HTTPS Inspection / CA certificates (HTTPS 流量检查与证书)
 * - Traffic stats & LAN bypass settings
 *
 * This adapter guarantees that Express configuration exports contain only pure DNS
 * settings, and that configuration imports never touch full-tunnel local storage.
 */
object ExpressConfigAdapter {

    /**
     * Sanitizes export selection so that full-tunnel items are omitted.
     */
    fun sanitizeExportSelection(selection: ConfigExportSelection): ConfigExportSelection {
        return selection.copy(
            outboundProxy = false,
            customRewriteDomainRules = false,
            customRewriteCnameRules = false,
            customAddressRules = false,
            excludedApps = false,
            blockedApps = false,
            appAllowlist = false,
            httpInspection = false
        )
    }

    /**
     * Sanitizes parsed configuration before import so that full-tunnel settings
     * are stripped and never written to local storage.
     */
    fun sanitizeImportConfig(config: TransferConfig, context: Context? = null): TransferConfig {
        val sanitizedSystemSettings = config.systemSettings?.copy(
            bypassLanEnabled = null,
            appTrafficStatsEnabled = null,
            trafficStatsRetentionDays = null,
            trafficStatsHideSystemApps = null,
            trafficSpeedEnabled = null
        )

        // To avoid mutating the user's existing blocked apps preference in local storage
        // when AppRuleConfigImporter checks `isBlockedAppsEnabled(context) != config.blockedAppsEnabled`,
        // keep blockedAppsEnabled aligned with the existing local state if context is available.
        val safeBlockedAppsEnabled = context?.let {
            AppRulesSettingsStore.isBlockedAppsEnabled(it)
        } ?: config.blockedAppsEnabled

        return config.copy(
            outboundProxy = null,
            httpInspection = null,
            customRewriteDomainRules = emptyList(),
            customRewriteCnameRules = emptyList(),
            customAddressRules = emptyList(),
            addressRulesEnabled = null,
            excludedApps = emptySet(),
            blockedApps = emptySet(),
            blockedAppsEnabled = safeBlockedAppsEnabled,
            appAllowlistRules = emptyMap(),
            appAllowlistEnabled = false,
            systemSettings = sanitizedSystemSettings
        )
    }

    /**
     * Exports pure Express configuration string.
     */
    suspend fun exportConfig(context: Context, selection: ConfigExportSelection): String {
        val safeSelection = sanitizeExportSelection(selection)
        val exporter = ConfigExporter(context)
        return exporter.export(safeSelection)
    }

    /**
     * Imports configuration safely in Express Mode.
     */
    suspend fun importConfig(
        context: Context,
        content: String,
        onProgress: (ConfigImportProgress) -> Unit = {}
    ): ConfigImportResult {
        val parsed = ConfigTransferParser.parseAndValidate(content)
        val sanitized = sanitizeImportConfig(parsed, context)
        val importer = ConfigImporter(context)
        return importer.import(sanitized, onProgress)
    }
}
