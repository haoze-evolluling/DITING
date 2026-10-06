package com.haoze.diting.main

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.os.Build
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import com.haoze.diting.MainActivity
import com.haoze.diting.express.ExpressModeLauncher
import com.haoze.diting.normal.DnsVpnService
import com.haoze.diting.notification.NotificationPermissionHelper
import com.haoze.diting.notification.VpnMonitorManager
import com.haoze.diting.permission.BatteryOptimizationHelper
import com.haoze.diting.server.backend.DnsModeManager
import com.haoze.diting.ui.PermissionDisclosure
import com.haoze.diting.ui.PermissionDisclosureSettings
import com.haoze.diting.ui.mode.AppWorkMode

/**
 * Manages VPN service lifecycle, system permissions, and disclosure dialog states.
 */
class MainVpnController(
    private val activity: ComponentActivity,
    private val getCurrentWorkMode: () -> AppWorkMode,
    private val onRefreshStatus: () -> Unit
) {
    var permissionDisclosure by mutableStateOf<PermissionDisclosure?>(null)

    private val vpnPrepareLauncher = activity.registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        if (result.resultCode == Activity.RESULT_OK) {
            PermissionDisclosureSettings.updateVpnGrant(activity, true)
            startVpnService()
        } else {
            PermissionDisclosureSettings.updateVpnGrant(activity, false)
            VpnMonitorManager.sync(activity)
            onRefreshStatus()
        }
    }

    private val notificationPermissionLauncher = activity.registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) {
        prepareVpn()
    }

    private val batteryOptimizationLauncher = activity.registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) {
        BatteryOptimizationHelper.invalidateCache()
        prepareVpn()
    }

    fun handleAutoStartIfNeeded(intent: Intent?) {
        if (intent?.getBooleanExtra(MainActivity.EXTRA_AUTO_START_VPN, false) != true) return
        intent.removeExtra(MainActivity.EXTRA_AUTO_START_VPN)
        if (getCurrentWorkMode() == AppWorkMode.DNS) {
            DnsModeManager.startService(activity)
            return
        }
        if (!ExpressModeLauncher.isCurrentModeRunning(activity)) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                !NotificationPermissionHelper.hasPermission(activity)
            ) {
                notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
            } else {
                prepareVpn()
            }
        }
    }

    fun onToggleVpn(isRunning: Boolean) {
        if (getCurrentWorkMode() == AppWorkMode.DNS) return
        if (getCurrentWorkMode() == AppWorkMode.EXPRESS) {
            ExpressModeLauncher.toggle(activity, ::prepareVpn)
            return
        }
        if (isRunning) {
            stopVpnService()
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            !NotificationPermissionHelper.hasPermission(activity)
        ) {
            notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        } else {
            prepareVpn()
        }
    }

    fun prepareVpn() {
        val intent = VpnService.prepare(activity)
        if (intent != null) {
            PermissionDisclosureSettings.updateVpnGrant(activity, false)
            if (PermissionDisclosureSettings.isVpnExplained(activity)) {
                vpnPrepareLauncher.launch(intent)
            } else {
                permissionDisclosure = PermissionDisclosure.VPN
            }
        } else {
            PermissionDisclosureSettings.updateVpnGrant(activity, true)
            startVpnService()
        }
    }

    fun continuePermissionRequest(disclosure: PermissionDisclosure) {
        permissionDisclosure = null
        when (disclosure) {
            PermissionDisclosure.VPN -> {
                PermissionDisclosureSettings.setVpnExplained(activity, true)
                prepareVpn()
            }
            PermissionDisclosure.NOTIFICATION -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                }
            }
            PermissionDisclosure.BATTERY_OPTIMIZATION -> {
                BatteryOptimizationHelper.requestPermission(
                    context = activity,
                    launcher = batteryOptimizationLauncher,
                    onAlreadyGranted = { prepareVpn() }
                )
            }
        }
    }

    fun dismissPermissionRequest(disclosure: PermissionDisclosure) {
        permissionDisclosure = null
        when (disclosure) {
            PermissionDisclosure.VPN -> {
                PermissionDisclosureSettings.setVpnExplained(activity, true)
                onRefreshStatus()
            }
            PermissionDisclosure.NOTIFICATION -> {
                // User declined notification disclosure; proceed without notifications
                prepareVpn()
            }
            PermissionDisclosure.BATTERY_OPTIMIZATION -> {
                BatteryOptimizationHelper.setDismissed(activity, true)
                prepareVpn()
            }
        }
    }

    fun startVpnService() {
        if (getCurrentWorkMode() == AppWorkMode.EXPRESS) {
            ExpressModeLauncher.start(activity)
        } else {
            ContextCompat.startForegroundService(activity, DnsVpnService.startIntent(activity))
        }
    }

    fun stopVpnService() {
        if (getCurrentWorkMode() == AppWorkMode.EXPRESS) {
            ExpressModeLauncher.stop(activity)
        } else {
            activity.startService(DnsVpnService.stopIntent(activity))
        }
    }
}
