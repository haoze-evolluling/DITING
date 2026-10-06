package com.haoze.diting.notification

import android.app.NotificationManager
import android.content.Context
import android.util.Log
import androidx.core.content.ContextCompat
import com.haoze.diting.core.VpnStateRegistry
import com.haoze.diting.ui.mode.AppWorkMode
import com.haoze.diting.ui.mode.WorkModeStore

/**
 * Safely schedules [VpnMonitorService] start/stop across the app lifecycle.
 */
object VpnMonitorManager {

    private const val TAG = "VpnMonitorManager"

    /**
     * Checks whether any VPN service (Normal mode or Express mode) is currently running.
     */
    fun isVpnRunning(context: Context): Boolean {
        val appContext = context.applicationContext
        return VpnStateRegistry.isAnyVpnRunning(appContext)
    }

    /**
     * Aligns the persistent monitor service with the current user settings,
     * system permissions, and VPN running state.
     */
    fun sync(context: Context) {
        val appContext = context.applicationContext
        if (WorkModeStore.getAppWorkMode(appContext) == AppWorkMode.DNS ||
            !NotificationSettingsStore.isPersistentNotificationEnabled(appContext) ||
            !NotificationPermissionHelper.hasPermission(appContext) ||
            isVpnRunning(appContext)
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
     * Stops the persistent monitor service and cancels its notification immediately.
     */
    fun stop(context: Context) {
        val appContext = context.applicationContext
        runCatching {
            appContext.startService(VpnMonitorService.stopIntent(appContext))
        }
        runCatching {
            appContext.stopService(VpnMonitorService.stopIntent(appContext))
        }.onFailure { e ->
            Log.w(TAG, "Failed to stop VpnMonitorService", e)
        }
        runCatching {
            val notificationManager = appContext.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            notificationManager?.cancel(VpnMonitorService.NOTIFICATION_ID_VPN_MONITOR)
        }.onFailure { e ->
            Log.w(TAG, "Failed to cancel monitor notification", e)
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
