package com.haoze.dnssr.notification

import android.content.Context
import android.util.Log
import androidx.core.content.ContextCompat
import com.haoze.dnssr.vpn.DnsVpnService

/**
 * Safely schedules [VpnMonitorService] start/stop across the app lifecycle.
 */
object VpnMonitorManager {

    private const val TAG = "VpnMonitorManager"

    /**
     * Aligns the persistent monitor service with the current user settings,
     * system permissions, and VPN running state.
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
     * Stops the persistent monitor service.
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
     * Hook invoked when the VPN starts.
     */
    fun onVpnStarted(context: Context) {
        stop(context)
    }

    /**
     * Hook invoked when the VPN stops.
     */
    fun onVpnStopped(context: Context) {
        sync(context)
    }
}
