package com.haoze.dnssr.vpn

import android.content.Context
import android.content.Intent

/**
 * Handles VPN running-state broadcasts, persistent monitor service
 * scheduling, and SharedPreferences state persistence.
 */
object DnsVpnStatusNotifier {

    private const val PREFS_NAME = "dns_vpn_prefs"
    private const val KEY_VPN_RUNNING = "vpn_running"

    /**
     * Broadcasts a VPN running-state change.
     */
    fun sendStatusBroadcast(context: Context, running: Boolean) {
        context.sendBroadcast(Intent(DnsVpnService.ACTION_VPN_STATUS_CHANGED).apply {
            putExtra(DnsVpnService.EXTRA_VPN_RUNNING, running)
            `package` = context.packageName
        })
        DnssrTileService.requestTileUpdate(context)
    }


    /**
     * Returns whether the VPN is running. If the SharedPreferences flag says
     * true but the in-process service is dead, the flag is corrected.
     */
    fun isRunning(context: Context, isServiceAlive: Boolean): Boolean {
        val flagged = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_VPN_RUNNING, false)
        if (flagged && !isServiceAlive) {
            setRunningFlag(context, false)
            return false
        }
        return flagged
    }

    /**
     * Persists the VPN running-state flag.
     */
    fun setRunningFlag(context: Context, running: Boolean) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_VPN_RUNNING, running)
            .apply()
    }
}
