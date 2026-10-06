package com.haoze.diting.ui

import android.content.Context
import android.util.Log
import com.haoze.diting.data.entity.RuleScope
import com.haoze.diting.data.RuleDataset
import com.haoze.diting.server.backend.DnsModeService
import com.haoze.diting.ui.mode.AppWorkMode
import com.haoze.diting.ui.mode.WorkModeStore
import com.haoze.diting.normal.DnsVpnService

object RuntimeDnsSettingsRefresher {
    private const val TAG = "RuntimeDnsRefresh"

    fun refreshIfRunning(
        context: Context,
        reason: String = "settings_changed",
        dataset: RuleDataset = RuleDataset.NORMAL
    ) {
        val appContext = context.applicationContext
        when (dataset) {
            RuleDataset.DNS_MODE -> {
                pingDnsModeFilterReload(appContext, "Failed to request DNS mode filter reload")
            }
            RuleDataset.EXPRESS -> {
                com.haoze.diting.express.ExpressSettingsRefresher.refreshIfRunning(appContext, reason)
            }
            RuleDataset.NORMAL -> {
                if (!DnsVpnService.isRunning(appContext)) return
                runCatching {
                    appContext.startService(DnsVpnService.refreshRuntimeConfigIntent(appContext, reason))
                }.onFailure { error ->
                    Log.w(TAG, "Failed to request DNS runtime config refresh", error)
                }
            }
        }
    }

    fun syncRuleIfRunning(
        context: Context,
        ruleType: String,
        pattern: String,
        scope: RuleScope = RuleScope.DNS,
        dataset: RuleDataset = RuleDataset.NORMAL
    ) {
        val appContext = context.applicationContext
        when (dataset) {
            RuleDataset.DNS_MODE -> {
                pingDnsModeFilterReload(appContext, "Failed to request DNS mode rule sync")
            }
            RuleDataset.EXPRESS -> {
                com.haoze.diting.express.ExpressSettingsRefresher.syncRulesIfRunning(appContext)
            }
            RuleDataset.NORMAL -> {
                if (!DnsVpnService.isRunning(appContext)) return
                runCatching {
                    appContext.startService(DnsVpnService.syncRuleIntent(appContext, ruleType, pattern, scope))
                }.onFailure { error ->
                    Log.w(TAG, "Failed to request incremental rule cache sync", error)
                }
            }
        }
    }

    fun refreshRuleIndexesIfRunning(
        context: Context,
        refreshBlock: Boolean,
        refreshAllow: Boolean,
        refreshRewrite: Boolean,
        scope: RuleScope = RuleScope.DNS,
        dataset: RuleDataset = RuleDataset.NORMAL
    ) {
        val appContext = context.applicationContext
        when (dataset) {
            RuleDataset.DNS_MODE -> {
                pingDnsModeFilterReload(appContext, "Failed to request DNS mode rule index refresh")
            }
            RuleDataset.EXPRESS -> {
                com.haoze.diting.express.ExpressSettingsRefresher.syncRulesIfRunning(appContext)
            }
            RuleDataset.NORMAL -> {
                if (!DnsVpnService.isRunning(appContext)) return
                runCatching {
                    appContext.startService(
                        DnsVpnService.refreshRuleIndexesIntent(appContext, refreshBlock, refreshAllow, refreshRewrite, scope)
                    )
                }.onFailure { error ->
                    Log.w(TAG, "Failed to request rule index refresh", error)
                }
            }
        }
    }

    fun syncHttpsRequestRulesIfRunning(context: Context) {
        val appContext = context.applicationContext
        if (!DnsVpnService.isRunning(appContext)) return
        runCatching {
            appContext.startService(DnsVpnService.syncHttpsRequestRulesIntent(appContext))
        }.onFailure { error ->
            Log.w(TAG, "Failed to sync HTTPS request rules", error)
        }
    }

    fun refreshAppExclusionsIfRunning(context: Context) {
        val appContext = context.applicationContext
        if (!DnsVpnService.isRunning(appContext)) return

        runCatching {
            appContext.startService(DnsVpnService.refreshAppExclusionsIntent(appContext))
        }.onFailure { error ->
            Log.w(TAG, "Failed to refresh application exclusions", error)
        }
    }

    fun refreshAppAllowlistIfRunning(context: Context) {
        val appContext = context.applicationContext
        if (!DnsVpnService.isRunning(appContext)) return

        runCatching {
            appContext.startService(DnsVpnService.refreshAppAllowlistIntent(appContext))
        }.onFailure { error ->
            Log.w(TAG, "Failed to refresh application allowlist", error)
        }
    }

    /**
     * Rule datasets are fully isolated, so a DNS dataset change reloads the DNS
     * mode filter (full in-memory reload via ACTION_REFRESH) while a normal
     * dataset change only ever touches the VPN service.
     */
    private fun pingDnsModeFilterReload(appContext: Context, logMessage: String) {
        if (WorkModeStore.getAppWorkMode(appContext) != AppWorkMode.DNS) return
        runCatching {
            appContext.startService(DnsModeService.refreshIntent(appContext))
        }.onFailure { error ->
            Log.w(TAG, logMessage, error)
        }
    }
}
