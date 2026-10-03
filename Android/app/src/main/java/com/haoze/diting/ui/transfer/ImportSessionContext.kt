package com.haoze.diting.ui.transfer

import android.content.Context
import com.haoze.diting.data.AppDatabase
import com.haoze.diting.ui.ConfigImportProgress
import com.haoze.diting.ui.ConfigImportResult

/**
 * Tracks the state, statistics, details, and progress emissions for an ongoing config import operation.
 */
internal class ImportSessionContext(
    val context: Context,
    val database: AppDatabase,
    val total: Int,
    private val onProgress: (ConfigImportProgress) -> Unit
) {
    var added: Int = 0
    var skipped: Int = 0
    var failed: Int = 0
    var processed: Int = 0

    var excludedAppsUpdated: Boolean = false
    var blockedAppsUpdated: Boolean = false
    var appAllowlistUpdated: Boolean = false
    var httpInspectionUpdated: Boolean = false
    var outboundProxyUpdated: Boolean = false
    var dnsCacheUpdated: Boolean = false
    var appearanceUpdated: Boolean = false
    var systemSettingsUpdated: Boolean = false

    var subscriptionsAdded: Int = 0
    var customRulesAdded: Int = 0

    val addedDetails = mutableListOf<String>()
    val skippedDetails = mutableListOf<String>()
    val failedDetails = mutableListOf<String>()
    val updatedSettingsDetails = mutableListOf<String>()
    val logs = mutableListOf<String>()

    fun report(item: String, logText: String? = null) {
        if (logText != null) logs.add(logText)
        onProgress(ConfigImportProgress(processed, total, item, logText))
    }

    fun complete(item: String, logText: String? = null) {
        processed++
        if (logText != null) logs.add(logText)
        onProgress(ConfigImportProgress(processed, total, item, logText))
    }

    fun addLog(logText: String) {
        logs.add(logText)
    }

    fun addUpdatedSetting(detail: String, logText: String? = null) {
        updatedSettingsDetails.add(detail)
        if (logText != null) {
            logs.add(logText)
        }
    }

    fun toResult(): ConfigImportResult = ConfigImportResult(
        added = added,
        skipped = skipped,
        failed = failed,
        excludedAppsUpdated = excludedAppsUpdated,
        blockedAppsUpdated = blockedAppsUpdated,
        appAllowlistUpdated = appAllowlistUpdated,
        httpInspectionUpdated = httpInspectionUpdated,
        outboundProxyUpdated = outboundProxyUpdated,
        dnsCacheUpdated = dnsCacheUpdated,
        appearanceUpdated = appearanceUpdated,
        systemSettingsUpdated = systemSettingsUpdated,
        subscriptionsAdded = subscriptionsAdded,
        customRulesAdded = customRulesAdded,
        addedDetails = addedDetails,
        skippedDetails = skippedDetails,
        failedDetails = failedDetails,
        updatedSettingsDetails = updatedSettingsDetails,
        logs = logs
    )
}
