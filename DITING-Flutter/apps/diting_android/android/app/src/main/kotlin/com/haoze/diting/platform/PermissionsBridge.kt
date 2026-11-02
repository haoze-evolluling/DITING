package com.haoze.diting.platform

import android.Manifest
import android.app.Activity
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.net.VpnService
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.haoze.diting.overlay.FloatingLogOverlay
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/// Runtime permissions the onboarding and troubleshooting screens ask for. Each one is a real
/// system dialog or settings hand-off: the app cannot grant any of them itself, and reporting a
/// made-up state was the previous behaviour.
class PermissionsBridge(private val activity: Activity) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.haoze.diting/permissions"

        /// A vendor runtime permission, granted only on MIUI/HyperOS, ColorOS, EMUI and friends.
        private const val GET_INSTALLED_APPS = "com.android.permission.GET_INSTALLED_APPS"

        private const val REQUEST_NOTIFICATION = 0x5801
        private const val REQUEST_APP_LIST = 0x5802
        private const val REQUEST_VPN = 0x5803
        private const val REQUEST_SETTINGS = 0x5804
    }

    private var pending: MethodChannel.Result? = null

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "states" -> result.success(states())
            "request" -> request(call.argument<String>("permission").orEmpty(), result)
            "openNotificationSettings" -> {
                result.success(openNotificationSettings())
            }
            "openAppSettings" -> {
                result.success(openAppSettings())
            }
            else -> result.notImplemented()
        }
    }

    /// Snapshot of every permission the onboarding lists, keyed by the Dart enum name.
    private fun states(): Map<String, Boolean> = mapOf(
        "vpn" to isVpnGranted(),
        "notification" to isNotificationGranted(),
        "appList" to isAppListGranted(),
        "batteryOptimization" to isIgnoringBatteryOptimizations(),
        "overlay" to FloatingLogOverlay.canDrawOverlays(activity),
    )

    private fun isVpnGranted(): Boolean = runCatching {
        VpnService.prepare(activity) == null
    }.getOrDefault(false)

    private fun isNotificationGranted(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            // Below 13 the permission does not exist; what matters is whether the user muted
            // the channel, which only the notification settings can change.
            val manager = activity.getSystemService(NotificationManager::class.java)
            return manager?.areNotificationsEnabled() ?: true
        }
        return hasPermission(Manifest.permission.POST_NOTIFICATIONS)
    }

    /// A granted vendor permission, or a successful probe: the probe is what AOSP/Pixel rely on,
    /// since they expose QUERY_ALL_PACKAGES instead of a runtime permission.
    private fun isAppListGranted(): Boolean {
        if (hasPermission(GET_INSTALLED_APPS)) {
            return true
        }
        return runCatching {
            activity.packageManager.getInstalledApplications(0).any {
                it.packageName != activity.packageName
            }
        }.getOrDefault(false)
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        val power = activity.getSystemService(PowerManager::class.java) ?: return false
        return power.isIgnoringBatteryOptimizations(activity.packageName)
    }

    private fun hasPermission(permission: String): Boolean =
        ContextCompat.checkSelfPermission(activity, permission) ==
            PackageManager.PERMISSION_GRANTED

    private fun request(name: String, result: MethodChannel.Result) {
        if (pending != null) {
            result.error("request_busy", "另一个权限请求仍在等待", null)
            return
        }
        when (name) {
            "vpn" -> requestVpn(result)
            "notification" -> requestNotification(result)
            "appList" -> requestAppList(result)
            "batteryOptimization" -> requestBatteryOptimization(result)
            "overlay" -> requestOverlay(result)
            else -> result.error("unknown_permission", "未知的权限：$name", null)
        }
    }

    /// `VpnService.prepare` returns either "already granted" or the consent intent; there is no
    /// runtime permission for the tunnel.
    private fun requestVpn(result: MethodChannel.Result) {
        val intent = runCatching { VpnService.prepare(activity) }.getOrNull()
        if (intent == null) {
            result.success(states())
            return
        }
        pending = result
        runCatching { activity.startActivityForResult(intent, REQUEST_VPN) }
            .onFailure {
                pending = null
                result.error("request_failed", it.message, null)
            }
    }

    private fun requestNotification(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            // No dialog exists, so the honest answer is "open the settings screen".
            openNotificationSettings()
            result.success(states())
            return
        }
        if (isNotificationGranted()) {
            result.success(states())
            return
        }
        pending = result
        runCatching {
            ActivityCompat.requestPermissions(
                activity,
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                REQUEST_NOTIFICATION,
            )
        }.onFailure {
            pending = null
            result.error("request_failed", it.message, null)
        }
    }

    private fun requestAppList(result: MethodChannel.Result) {
        if (isAppListGranted()) {
            result.success(states())
            return
        }
        pending = result
        // The vendor permission has no AOSP dialog: requestPermissions throws or answers denied
        // at once. The Dart caller opens the settings screen when the request leaves the
        // permission denied, so a second hand-off here would stack two settings activities.
        runCatching {
            ActivityCompat.requestPermissions(
                activity,
                arrayOf(GET_INSTALLED_APPS),
                REQUEST_APP_LIST,
            )
        }.onFailure {
            pending = null
            result.success(states())
        }
    }

    private fun requestBatteryOptimization(result: MethodChannel.Result) {
        if (isIgnoringBatteryOptimizations()) {
            result.success(states())
            return
        }
        val direct = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
            .setData(Uri.parse("package:${activity.packageName}"))
        val fallback = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
        // The direct intent is a dialog only where the ROM allows it; the list is always there.
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            activity.packageManager.resolveActivity(direct, 0) != null
        ) {
            direct
        } else {
            fallback
        }
        pending = result
        runCatching { activity.startActivityForResult(intent, REQUEST_SETTINGS) }
            .onFailure {
                pending = null
                result.success(states())
            }
    }

    /// No dialog exists: the per-app "display over other apps" screen is the only way in.
    private fun requestOverlay(result: MethodChannel.Result) {
        if (FloatingLogOverlay.canDrawOverlays(activity)) {
            result.success(states())
            return
        }
        val intent = Intent(
            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
            Uri.parse("package:${activity.packageName}"),
        )
        pending = result
        runCatching { activity.startActivityForResult(intent, REQUEST_SETTINGS) }
            .onFailure {
                pending = null
                result.success(states())
            }
    }

    /// Resolves whatever request is pending with a fresh snapshot; MainActivity forwards every
    /// unknown result code here last, so returning false means "not mine".
    fun onActivityResult(requestCode: Int, resultCode: Int): Boolean {
        val mine = requestCode == REQUEST_NOTIFICATION ||
            requestCode == REQUEST_APP_LIST ||
            requestCode == REQUEST_VPN ||
            requestCode == REQUEST_SETTINGS
        if (!mine) return false
        finish(resultCode)
        return true
    }

    /// Same contract for the runtime-permission callback; false when it belongs to someone else.
    fun onRequestPermissionsResult(requestCode: Int): Boolean {
        if (requestCode != REQUEST_NOTIFICATION && requestCode != REQUEST_APP_LIST) {
            return false
        }
        finish(Activity.RESULT_OK)
        return true
    }

    private fun finish(resultCode: Int) {
        val result = pending ?: return
        pending = null
        result.success(states() + mapOf("result" to resultCode))
    }

    private fun openNotificationSettings(): Boolean = runCatching {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName)
        } else {
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.parse("package:${activity.packageName}"))
        }
        activity.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        true
    }.getOrDefault(false)

    private fun openAppSettings(): Boolean = runCatching {
        activity.startActivity(
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.parse("package:${activity.packageName}"))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
        true
    }.getOrDefault(false)
}
