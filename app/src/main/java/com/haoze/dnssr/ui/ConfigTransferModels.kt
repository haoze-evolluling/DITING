package com.haoze.dnssr.ui

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
) {
    fun message(): String = buildString {
        append("导入完成：新增 $added 项，跳过 $skipped 项")
        if (failed > 0) append("，失败 $failed 项")
        if (subscriptionsAdded > 0) append("。包含 $subscriptionsAdded 个订阅，请进入订阅管理执行规则更新。")
    }
}

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
