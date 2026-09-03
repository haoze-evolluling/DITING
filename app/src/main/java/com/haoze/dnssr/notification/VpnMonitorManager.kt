package com.haoze.dnssr.notification

import android.content.Context
import android.util.Log
import androidx.core.content.ContextCompat
import com.haoze.dnssr.vpn.DnsVpnService

/**
 * 负责在应用生命周期中安全调度 [VpnMonitorService] 的启动与停止。
 */
object VpnMonitorManager {

    private const val TAG = "VpnMonitorManager"

    /**
     * 根据当前用户配置、系统权限与 VPN 运行状态同步常驻监控服务。
     */
    fun sync(context: Context) {
        val appContext = context.applicationContext
        if (!NotificationSettingsStore.isPersistentNotificationEnabled(appContext) ||
            !NotificationPermissionHelper.hasPermission(appContext) ||
            DnsVpnService.isRunning(appContext)
        ) {
            stop(appContext)
            return
        }

        try {
            ContextCompat.startForegroundService(appContext, VpnMonitorService.startIntent(appContext))
        } catch (e: Exception) {
            Log.w(TAG, "Failed to start VpnMonitorService", e)
        }
    }

    /**
     * 停止常驻监控服务。
     */
    fun stop(context: Context) {
        val appContext = context.applicationContext
        try {
            appContext.stopService(VpnMonitorService.stopIntent(appContext))
        } catch (e: Exception) {
            Log.w(TAG, "Failed to stop VpnMonitorService", e)
        }
    }

    /**
     * VPN 启动时的联动钩子。
     */
    fun onVpnStarted(context: Context) {
        stop(context)
    }

    /**
     * VPN 停止时的联动钩子。
     */
    fun onVpnStopped(context: Context) {
        sync(context)
    }
}
