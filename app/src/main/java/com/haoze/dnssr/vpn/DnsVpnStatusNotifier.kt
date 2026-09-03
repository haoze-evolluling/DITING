package com.haoze.dnssr.vpn

import android.content.Context
import android.content.Intent

/**
 * 负责 VPN 运行状态广播发送、常驻监控服务调度以及 SharedPreferences 状态持久化。
 */
object DnsVpnStatusNotifier {

    private const val TAG = "DnsVpnStatusNotifier"
    private const val PREFS_NAME = "dns_vpn_prefs"
    private const val KEY_VPN_RUNNING = "vpn_running"

    /**
     * 发送 VPN 运行状态变更广播。
     */
    fun sendStatusBroadcast(context: Context, running: Boolean) {
        context.sendBroadcast(Intent(DnsVpnService.ACTION_VPN_STATUS_CHANGED).apply {
            putExtra(DnsVpnService.EXTRA_VPN_RUNNING, running)
            `package` = context.packageName
        })
        DnssrTileService.requestTileUpdate(context)
    }


    /**
     * 查询 VPN 是否处于运行中状态。若 SharedPreferences 标记为 true 但进程内服务已死，则纠正标记。
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
     * 设置 VPN 运行状态持久化标记。
     */
    fun setRunningFlag(context: Context, running: Boolean) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_VPN_RUNNING, running)
            .apply()
    }
}
