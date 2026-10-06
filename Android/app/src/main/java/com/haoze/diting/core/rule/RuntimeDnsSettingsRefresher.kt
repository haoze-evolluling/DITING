package com.haoze.diting.core.rule

import android.content.Context
import android.content.Intent
import android.util.Log
import com.haoze.diting.core.VpnStateRegistry
import com.haoze.diting.data.RuleDataset
import com.haoze.diting.data.entity.RuleScope
import com.haoze.diting.ui.mode.AppWorkMode
import com.haoze.diting.ui.mode.WorkModeStore

/**
 * Dispatches runtime DNS configuration and rule refresh events across work modes
 * without coupling callers directly to concrete mode service implementations.
 */
object RuntimeDnsSettingsRefresher {
    private const val TAG = "RuntimeDnsRefresh"

    private const val NORMAL_SERVICE_CLASS = "com.haoze.diting.normal.DnsVpnService"
    private const val EXPRESS_SERVICE_CLASS = "com.haoze.diting.express.ExpressVpnService"
    private const val SERVER_SERVICE_CLASS = "com.haoze.diting.server.backend.DnsModeService"

    private const val ACTION_NORMAL_REFRESH_CONFIG = "com.haoze.diting.REFRESH_RUNTIME_CONFIG"
    private const val ACTION_NORMAL_SYNC_RULE = "com.haoze.diting.SYNC_RULE"
    private const val ACTION_NORMAL_REFRESH_RULE_INDEXES = "com.haoze.diting.REFRESH_RULE_INDEXES"
    private const val ACTION_NORMAL_SYNC_HTTPS = "com.haoze.diting.SYNC_HTTPS_REQUEST_RULES"
    private const val ACTION_NORMAL_REFRESH_EXCLUSIONS = "com.haoze.diting.REFRESH_APP_EXCLUSIONS"
    private const val ACTION_NORMAL_REFRESH_ALLOWLIST = "com.haoze.diting.REFRESH_APP_ALLOWLIST"

    private const val ACTION_EXPRESS_REFRESH_CONFIG = "com.haoze.diting.express.REFRESH_CONFIG"
    private const val ACTION_EXPRESS_SYNC_RULES = "com.haoze.diting.express.SYNC_RULES"

    private const val ACTION_SERVER_REFRESH = "com.haoze.diting.server.REFRESH"

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
                if (!VpnStateRegistry.isExpressRunning(appContext)) return
                runCatching {
                    val intent = Intent().setClassName(appContext.packageName, EXPRESS_SERVICE_CLASS)
                        .setAction(ACTION_EXPRESS_REFRESH_CONFIG)
                        .putExtra("refresh_reason", reason)
                    appContext.startService(intent)
                }.onFailure { error ->
                    Log.w(TAG, "Failed to send express config refresh intent", error)
                }
            }
            RuleDataset.NORMAL -> {
                if (!VpnStateRegistry.isNormalRunning(appContext)) return
                runCatching {
                    val intent = Intent().setClassName(appContext.packageName, NORMAL_SERVICE_CLASS)
                        .setAction(ACTION_NORMAL_REFRESH_CONFIG)
                        .putExtra("refresh_reason", reason)
                    appContext.startService(intent)
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
                if (!VpnStateRegistry.isExpressRunning(appContext)) return
                runCatching {
                    val intent = Intent().setClassName(appContext.packageName, EXPRESS_SERVICE_CLASS)
                        .setAction(ACTION_EXPRESS_SYNC_RULES)
                    appContext.startService(intent)
                }.onFailure { error ->
                    Log.w(TAG, "Failed to send express rule sync intent", error)
                }
            }
            RuleDataset.NORMAL -> {
                if (!VpnStateRegistry.isNormalRunning(appContext)) return
                runCatching {
                    val intent = Intent().setClassName(appContext.packageName, NORMAL_SERVICE_CLASS)
                        .setAction(ACTION_NORMAL_SYNC_RULE)
                        .putExtra("rule_type", ruleType)
                        .putExtra("rule_pattern", pattern)
                        .putExtra("rule_scope", scope.storageValue)
                    appContext.startService(intent)
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
                if (!VpnStateRegistry.isExpressRunning(appContext)) return
                runCatching {
                    val intent = Intent().setClassName(appContext.packageName, EXPRESS_SERVICE_CLASS)
                        .setAction(ACTION_EXPRESS_SYNC_RULES)
                    appContext.startService(intent)
                }.onFailure { error ->
                    Log.w(TAG, "Failed to send express rule sync intent", error)
                }
            }
            RuleDataset.NORMAL -> {
                if (!VpnStateRegistry.isNormalRunning(appContext)) return
                runCatching {
                    val intent = Intent().setClassName(appContext.packageName, NORMAL_SERVICE_CLASS)
                        .setAction(ACTION_NORMAL_REFRESH_RULE_INDEXES)
                        .putExtra("refresh_block", refreshBlock)
                        .putExtra("refresh_allow", refreshAllow)
                        .putExtra("refresh_rewrite", refreshRewrite)
                        .putExtra("rule_scope", scope.storageValue)
                    appContext.startService(intent)
                }.onFailure { error ->
                    Log.w(TAG, "Failed to request rule index refresh", error)
                }
            }
        }
    }

    fun syncHttpsRequestRulesIfRunning(context: Context) {
        val appContext = context.applicationContext
        if (!VpnStateRegistry.isNormalRunning(appContext)) return
        runCatching {
            val intent = Intent().setClassName(appContext.packageName, NORMAL_SERVICE_CLASS)
                .setAction(ACTION_NORMAL_SYNC_HTTPS)
            appContext.startService(intent)
        }.onFailure { error ->
            Log.w(TAG, "Failed to sync HTTPS request rules", error)
        }
    }

    fun refreshAppExclusionsIfRunning(context: Context) {
        val appContext = context.applicationContext
        if (!VpnStateRegistry.isNormalRunning(appContext)) return
        runCatching {
            val intent = Intent().setClassName(appContext.packageName, NORMAL_SERVICE_CLASS)
                .setAction(ACTION_NORMAL_REFRESH_EXCLUSIONS)
            appContext.startService(intent)
        }.onFailure { error ->
            Log.w(TAG, "Failed to refresh application exclusions", error)
        }
    }

    fun refreshAppAllowlistIfRunning(context: Context) {
        val appContext = context.applicationContext
        if (!VpnStateRegistry.isNormalRunning(appContext)) return
        runCatching {
            val intent = Intent().setClassName(appContext.packageName, NORMAL_SERVICE_CLASS)
                .setAction(ACTION_NORMAL_REFRESH_ALLOWLIST)
            appContext.startService(intent)
        }.onFailure { error ->
            Log.w(TAG, "Failed to refresh application allowlist", error)
        }
    }

    private fun pingDnsModeFilterReload(appContext: Context, logMessage: String) {
        if (WorkModeStore.getAppWorkMode(appContext) != AppWorkMode.DNS) return
        runCatching {
            val intent = Intent().setClassName(appContext.packageName, SERVER_SERVICE_CLASS)
                .setAction(ACTION_SERVER_REFRESH)
            appContext.startService(intent)
        }.onFailure { error ->
            Log.w(TAG, logMessage, error)
        }
    }
}
