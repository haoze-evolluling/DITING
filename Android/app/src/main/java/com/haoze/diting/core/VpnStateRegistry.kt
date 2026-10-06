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
}
