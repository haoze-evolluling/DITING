package com.haoze.diting.core

import android.content.Context

/**
 * Registry for checking VPN running states across work modes without direct coupling.
 */
object VpnStateRegistry {
    @Volatile
    var isNormalRunning: (Context) -> Boolean = { ctx ->
        ctx.getSharedPreferences("dns_vpn_prefs", Context.MODE_PRIVATE)
            .getBoolean("vpn_running", false)
    }

    @Volatile
    var isExpressRunning: (Context) -> Boolean = { ctx ->
        ctx.getSharedPreferences("express_vpn_prefs", Context.MODE_PRIVATE)
            .getBoolean("express_vpn_running", false)
    }

    fun isAnyVpnRunning(context: Context): Boolean =
        isNormalRunning(context) || isExpressRunning(context)

    @Volatile
    var setNormalRunningFlag: (Context, Boolean) -> Unit = { ctx, r ->
        ctx.getSharedPreferences("dns_vpn_prefs", Context.MODE_PRIVATE)
            .edit()
            .putBoolean("vpn_running", r)
            .apply()
    }

    const val ACTION_VPN_STATUS_CHANGED = "com.haoze.diting.VPN_STATUS_CHANGED"
    const val EXTRA_VPN_RUNNING = "vpn_running"
}
