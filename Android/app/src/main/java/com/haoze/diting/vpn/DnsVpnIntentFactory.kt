package com.haoze.diting.vpn

import android.content.Context
import android.content.Intent
import com.haoze.diting.data.entity.RuleScope

/**
 * Factory for creating [Intent] instances targeting [DnsVpnService].
 */
object DnsVpnIntentFactory {

    const val ACTION_STOP = "com.haoze.diting.STOP_VPN"
    const val ACTION_REFRESH_APP_EXCLUSIONS = "com.haoze.diting.REFRESH_APP_EXCLUSIONS"
    const val ACTION_REFRESH_APP_ALLOWLIST = "com.haoze.diting.REFRESH_APP_ALLOWLIST"
    const val ACTION_REFRESH_RUNTIME_CONFIG = "com.haoze.diting.REFRESH_RUNTIME_CONFIG"
    const val ACTION_REFRESH_NOTIFICATION = "com.haoze.diting.notification.REFRESH_NOTIFICATION"
    const val ACTION_REFRESH_FLOATING_LOG = "com.haoze.diting.REFRESH_FLOATING_LOG"
    const val ACTION_FLOATING_LOG_APP_STATE = "com.haoze.diting.FLOATING_LOG_APP_STATE"
    const val ACTION_SYNC_RULE = "com.haoze.diting.SYNC_RULE"
    const val ACTION_REFRESH_RULE_INDEXES = "com.haoze.diting.REFRESH_RULE_INDEXES"
    const val ACTION_SYNC_HTTPS_REQUEST_RULES = "com.haoze.diting.SYNC_HTTPS_REQUEST_RULES"
    const val ACTION_VPN_STATUS_CHANGED = "com.haoze.diting.VPN_STATUS_CHANGED"

    const val EXTRA_VPN_RUNNING = "vpn_running"
    const val EXTRA_REFRESH_REASON = "refresh_reason"
    const val EXTRA_RULE_TYPE = "rule_type"
    const val EXTRA_RULE_PATTERN = "rule_pattern"
    const val EXTRA_RULE_SCOPE = "rule_scope"
    const val EXTRA_REFRESH_BLOCK = "refresh_block"
    const val EXTRA_REFRESH_ALLOW = "refresh_allow"
    const val EXTRA_REFRESH_REWRITE = "refresh_rewrite"
    const val EXTRA_APP_FOREGROUND = "app_foreground"

    const val EXTRA_DOH_URL = "doh_url"
    const val EXTRA_DNS_NAME = "dns_name"
    const val EXTRA_DNS_PROTOCOL = "dns_protocol"
    const val EXTRA_DNS_HOST = "dns_host"
    const val EXTRA_DNS_PORT = "dns_port"

    fun startIntent(
        context: Context,
        provider: DnsProvider? = null
    ): Intent {
        return Intent(context, DnsVpnService::class.java).apply {
            provider?.let {
                putExtra(EXTRA_DNS_PROTOCOL, it.protocol.name)
                if (it.protocol == DnsProtocol.DOH) {
                    putExtra(EXTRA_DOH_URL, it.url)
                } else {
                    putExtra(EXTRA_DNS_HOST, it.host)
                    putExtra(EXTRA_DNS_PORT, it.port)
                }
                putExtra(EXTRA_DNS_NAME, it.name)
            }
        }
    }

    fun stopIntent(context: Context): Intent {
        return Intent(context, DnsVpnService::class.java).setAction(ACTION_STOP)
    }

    fun refreshRuntimeConfigIntent(
        context: Context,
        reason: String = "runtime_config"
    ): Intent {
        return Intent(context, DnsVpnService::class.java)
            .setAction(ACTION_REFRESH_RUNTIME_CONFIG)
            .putExtra(EXTRA_REFRESH_REASON, reason)
    }

    fun syncRuleIntent(
        context: Context,
        ruleType: String,
        pattern: String,
        scope: RuleScope = RuleScope.DNS
    ): Intent {
        return Intent(context, DnsVpnService::class.java)
            .setAction(ACTION_SYNC_RULE)
            .putExtra(EXTRA_RULE_TYPE, ruleType)
            .putExtra(EXTRA_RULE_PATTERN, pattern)
            .putExtra(EXTRA_RULE_SCOPE, scope.storageValue)
    }

    fun refreshRuleIndexesIntent(
        context: Context,
        refreshBlock: Boolean,
        refreshAllow: Boolean,
        refreshRewrite: Boolean,
        scope: RuleScope = RuleScope.DNS
    ): Intent = Intent(context, DnsVpnService::class.java)
        .setAction(ACTION_REFRESH_RULE_INDEXES)
        .putExtra(EXTRA_REFRESH_BLOCK, refreshBlock)
        .putExtra(EXTRA_REFRESH_ALLOW, refreshAllow)
        .putExtra(EXTRA_REFRESH_REWRITE, refreshRewrite)
        .putExtra(EXTRA_RULE_SCOPE, scope.storageValue)

    fun syncHttpsRequestRulesIntent(context: Context): Intent =
        Intent(context, DnsVpnService::class.java).setAction(ACTION_SYNC_HTTPS_REQUEST_RULES)

    fun refreshAppExclusionsIntent(context: Context): Intent {
        return Intent(context, DnsVpnService::class.java).setAction(ACTION_REFRESH_APP_EXCLUSIONS)
    }

    fun refreshAppAllowlistIntent(context: Context): Intent {
        return Intent(context, DnsVpnService::class.java).setAction(ACTION_REFRESH_APP_ALLOWLIST)
    }
}
