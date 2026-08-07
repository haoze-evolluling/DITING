package com.haoze.dnssr.ui

import android.content.Context
import android.util.Log
import com.haoze.dnssr.data.entity.RuleScope
import com.haoze.dnssr.vpn.DnsVpnService

object RuntimeDnsSettingsRefresher {
    private const val TAG = "RuntimeDnsRefresh"

    fun refreshIfRunning(context: Context, reason: String = "settings_changed") {
        val appContext = context.applicationContext
        if (!DnsVpnService.isRunning(appContext)) return

        runCatching {
            appContext.startService(DnsVpnService.refreshRuntimeConfigIntent(appContext, reason))
        }.onFailure { error ->
            Log.w(TAG, "Failed to request DNS runtime config refresh", error)
        }
    }

    fun syncRuleIfRunning(
        context: Context,
        ruleType: String,
        pattern: String,
        scope: RuleScope = RuleScope.DNS
    ) {
        val appContext = context.applicationContext
        if (!DnsVpnService.isRunning(appContext)) return
        runCatching {
            appContext.startService(DnsVpnService.syncRuleIntent(appContext, ruleType, pattern, scope))
        }.onFailure { error ->
            Log.w(TAG, "Failed to request incremental rule cache sync", error)
        }
    }

    fun refreshRuleIndexesIfRunning(
        context: Context,
        refreshBlock: Boolean,
        refreshAllow: Boolean,
        refreshRewrite: Boolean,
        scope: RuleScope = RuleScope.DNS
    ) {
        val appContext = context.applicationContext
        if (!DnsVpnService.isRunning(appContext)) return
        runCatching {
            appContext.startService(
                DnsVpnService.refreshRuleIndexesIntent(appContext, refreshBlock, refreshAllow, refreshRewrite, scope)
            )
        }.onFailure { error ->
            Log.w(TAG, "Failed to request rule index refresh", error)
        }
    }

    fun refreshHttpsRuleIndexesIfRunning(context: Context, refreshBlock: Boolean, refreshAllow: Boolean, refreshRewrite: Boolean) {
        val appContext = context.applicationContext
        if (!DnsVpnService.isRunning(appContext)) return
        runCatching {
            appContext.startService(
                DnsVpnService.refreshRuleIndexesIntent(
                    appContext,
                    refreshBlock,
                    refreshAllow,
                    refreshRewrite,
                    RuleScope.HTTPS
                )
            )
        }.onFailure { error ->
            Log.w(TAG, "Failed to request HTTPS rule index refresh", error)
        }
    }

    fun syncHttpsManualRewriteRulesIfRunning(context: Context) {
        val appContext = context.applicationContext
        if (!DnsVpnService.isRunning(appContext)) return
        runCatching {
            appContext.startService(DnsVpnService.syncHttpsManualRewriteRulesIntent(appContext))
        }.onFailure { error ->
            Log.w(TAG, "Failed to sync manual HTTPS rewrite rules", error)
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
}
