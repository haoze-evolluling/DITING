package com.haoze.diting.express

import android.content.Context
import android.content.Intent
import com.haoze.diting.vpn.DnsProtocol
import com.haoze.diting.vpn.DnsProvider

/**
 * Dedicated Intent actions and factory methods for Express Mode VPN.
 */
object ExpressVpnIntents {

    const val ACTION_START = "com.haoze.diting.express.START_VPN"
    const val ACTION_STOP = "com.haoze.diting.express.STOP_VPN"
    const val ACTION_REFRESH_CONFIG = "com.haoze.diting.express.REFRESH_CONFIG"
    const val ACTION_SYNC_RULES = "com.haoze.diting.express.SYNC_RULES"
    const val ACTION_CLEAR_CACHE = "com.haoze.diting.express.CLEAR_CACHE"
    const val ACTION_STATUS_CHANGED = "com.haoze.diting.express.STATUS_CHANGED"
    const val ACTION_REFRESH_FLOATING_LOG = "com.haoze.diting.express.REFRESH_FLOATING_LOG"
    const val ACTION_FLOATING_LOG_APP_STATE = "com.haoze.diting.express.FLOATING_LOG_APP_STATE"

    const val EXTRA_RUNNING = "vpn_running"
    const val EXTRA_REFRESH_REASON = "refresh_reason"
    const val EXTRA_DNS_NAME = "dns_name"
    const val EXTRA_DNS_PROTOCOL = "dns_protocol"
    const val EXTRA_DNS_HOST = "dns_host"
    const val EXTRA_DNS_PORT = "dns_port"
    const val EXTRA_DOH_URL = "doh_url"
    const val EXTRA_APP_FOREGROUND = "app_foreground"

    fun startIntent(
        context: Context,
        provider: DnsProvider? = null
    ): Intent = Intent(context, ExpressVpnService::class.java).apply {
        action = ACTION_START
        provider?.let {
            putExtra(EXTRA_DNS_NAME, it.name)
            putExtra(EXTRA_DNS_PROTOCOL, it.protocol.name)
            if (it.protocol == DnsProtocol.DOH) {
                putExtra(EXTRA_DOH_URL, it.url)
            } else {
                putExtra(EXTRA_DNS_HOST, it.host)
                putExtra(EXTRA_DNS_PORT, it.port)
            }
        }
    }

    fun stopIntent(context: Context): Intent =
        Intent(context, ExpressVpnService::class.java).apply {
            action = ACTION_STOP
        }

    fun refreshConfigIntent(
        context: Context,
        reason: String = "runtime_config"
    ): Intent = Intent(context, ExpressVpnService::class.java).apply {
        action = ACTION_REFRESH_CONFIG
        putExtra(EXTRA_REFRESH_REASON, reason)
    }

    fun syncRulesIntent(context: Context): Intent =
        Intent(context, ExpressVpnService::class.java).apply {
            action = ACTION_SYNC_RULES
        }

    fun clearCacheIntent(context: Context): Intent =
        Intent(context, ExpressVpnService::class.java).apply {
            action = ACTION_CLEAR_CACHE
        }

    fun refreshFloatingLogIntent(context: Context): Intent =
        Intent(context, ExpressVpnService::class.java).apply {
            action = ACTION_REFRESH_FLOATING_LOG
        }

    fun floatingLogAppStateIntent(context: Context, foreground: Boolean): Intent =
        Intent(context, ExpressVpnService::class.java).apply {
            action = ACTION_FLOATING_LOG_APP_STATE
            putExtra(EXTRA_APP_FOREGROUND, foreground)
        }

    fun statusBroadcastIntent(context: Context, running: Boolean): Intent =
        Intent(ACTION_STATUS_CHANGED).apply {
            `package` = context.packageName
            putExtra(EXTRA_RUNNING, running)
        }
}
