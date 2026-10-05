package com.haoze.diting.express

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.util.Log
import com.haoze.diting.MainActivity
import com.haoze.diting.dnsmode.backend.DnsModeManager
import com.haoze.diting.notification.AppNotificationChannels
import com.haoze.diting.notification.VpnMonitorManager
import com.haoze.diting.ui.mode.AppWorkMode
import com.haoze.diting.ui.mode.WorkModeStore
import com.haoze.diting.vpn.DnsProvider
import com.haoze.diting.vpn.DnsVpnService

/**
 * Dedicated launcher and lifecycle bridge for Express Mode.
 *
 * Encapsulates mutually exclusive switching, stopping legacy VPN and DNS
 * mode services, permission verification, and Express VPN start/stop.
 */
object ExpressModeLauncher {
    private const val TAG = "ExpressModeLauncher"

    /**
     * Executes mutual-exclusion cleanup and initializes Express Mode.
     * Stops legacy [DnsVpnService], [DnsModeService], and [VpnMonitorManager].
     */
    fun switchToExpress(
        context: Context,
        previousMode: AppWorkMode = WorkModeStore.getAppWorkMode(context),
        onComplete: (() -> Unit)? = null
    ) {
        val appContext = context.applicationContext

        // Stop legacy Go VPN service if running
        runCatching {
            appContext.startService(DnsVpnService.stopIntent(appContext))
        }.onFailure { e ->
            Log.w(TAG, "Failed to stop legacy DnsVpnService", e)
        }

        // Stop legacy Server/DNS mode service if running
        runCatching {
            DnsModeManager.stopService(appContext)
        }.onFailure { e ->
            Log.w(TAG, "Failed to stop legacy DnsModeService", e)
        }

        // Discontinue persistent disconnected monitor for Express Mode
        runCatching {
            VpnMonitorManager.stop(appContext)
        }.onFailure { e ->
            Log.w(TAG, "Failed to stop VpnMonitorManager", e)
        }

        WorkModeStore.setAppWorkMode(appContext, AppWorkMode.EXPRESS)
        WorkModeStore.setWorkModeSelected(appContext, true)

        AppNotificationChannels.createAllChannels(appContext)
        com.haoze.diting.express.notification.ExpressNotificationBuilder.ensureChannel(appContext)
        ExpressVpnController.initialize(appContext)

        onComplete?.invoke()
    }

    /**
     * Stops the Express VPN service when switching away to another mode.
     */
    fun stopExpress(context: Context) {
        val appContext = context.applicationContext
        ExpressVpnController.stop(appContext)
    }

    /**
     * Single-line delegate for mode selection within MainActivity.
     */
    fun handleModeSelected(
        activity: Context,
        selectedMode: AppWorkMode,
        onSelected: () -> Unit
    ) {
        switchToExpress(activity, WorkModeStore.getAppWorkMode(activity))
        onSelected()
    }

    /**
     * Single-line delegate for mode refresh within MainActivity LaunchedEffect.
     */
    fun handleWorkModeSwitch(
        context: Context,
        currentMode: AppWorkMode
    ) {
        switchToExpress(context, currentMode)
    }

    /**
     * Single-line delegate for mode switching inside SettingsRouteActivity.
     */
    fun handleRouteModeSelected(
        activity: Activity,
        previousMode: AppWorkMode,
        onBack: () -> Unit
    ) {
        switchToExpress(activity, previousMode)
        if (previousMode == AppWorkMode.DNS) {
            val intent = Intent(activity, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
            }
            activity.startActivity(intent)
            activity.finish()
        } else {
            onBack()
        }
    }

    /**
     * Starts the Express VPN service.
     */
    fun start(context: Context, provider: DnsProvider? = null) {
        ExpressVpnController.start(context, provider)
    }

    /**
     * Stops the Express VPN service.
     */
    fun stop(context: Context) {
        ExpressVpnController.stop(context)
    }

    /**
     * Toggles Express VPN service state, checking system VPN preparation if starting.
     */
    fun toggle(
        context: Context,
        onRequestVpnPermission: (() -> Unit)? = null
    ) {
        if (ExpressVpnController.isRunning(context)) {
            ExpressVpnController.stop(context)
        } else {
            val prepareIntent = VpnService.prepare(context)
            if (prepareIntent == null) {
                ExpressVpnController.start(context)
            } else {
                onRequestVpnPermission?.invoke()
            }
        }
    }

    /**
     * Dispatches floating log foreground/background state to the active mode service.
     */
    fun updateFloatingLogAppState(context: Context, foreground: Boolean) {
        if (WorkModeStore.getAppWorkMode(context) == AppWorkMode.EXPRESS) {
            ExpressVpnController.updateFloatingLogAppState(context, foreground)
        } else {
            DnsVpnService.updateFloatingLogAppState(context, foreground)
        }
    }

    /**
     * Checks whether the service for the current mode is running.
     */
    fun isCurrentModeRunning(context: Context): Boolean {
        return if (WorkModeStore.getAppWorkMode(context) == AppWorkMode.EXPRESS) {
            ExpressVpnController.isRunning(context)
        } else {
            DnsVpnService.isRunning(context)
        }
    }
}
