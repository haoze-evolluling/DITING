package com.haoze.diting.ui

data class ConfigExportSelection(
    val providers: Boolean = true,
    val bootstrapIps: Boolean = true,
    val dnsCache: Boolean = true,
    val outboundProxy: Boolean = true,
    val subscriptions: Boolean = true,
    val customDomainRules: Boolean = true,
    val customRewriteDomainRules: Boolean = true,
    val customRewriteCnameRules: Boolean = true,
    val customAddressRules: Boolean = true,
    val excludedApps: Boolean = true,
    val blockedApps: Boolean = true,
    val appAllowlist: Boolean = true,
    val httpInspection: Boolean = true,
    val appearance: Boolean = true,
    val systemSettings: Boolean = true
)

data class ConfigImportResult(
    val added: Int,
    val skipped: Int,
    val failed: Int,
    val excludedAppsUpdated: Boolean,
    val blockedAppsUpdated: Boolean,
    val appAllowlistUpdated: Boolean,
    val httpInspectionUpdated: Boolean = false,
    val outboundProxyUpdated: Boolean = false,
    val dnsCacheUpdated: Boolean = false,
    val appearanceUpdated: Boolean = false,
    val systemSettingsUpdated: Boolean = false,
    val subscriptionsAdded: Int = 0,
    val customRulesAdded: Int = 0,
    val addedDetails: List<String> = emptyList(),
    val skippedDetails: List<String> = emptyList(),
    val failedDetails: List<String> = emptyList(),
    val updatedSettingsDetails: List<String> = emptyList(),
    val logs: List<String> = emptyList()
)

data class ConfigImportProgress(
    val processed: Int,
    val total: Int,
    val currentItem: String,
    val log: String? = null
)

data class ConfigDashboardStats(
    val customProvidersCount: Int = 0,
    val subscriptionsCount: Int = 0,
    val customRulesCount: Int = 0,
    val managedAppsCount: Int = 0
)
