package com.haoze.diting.platform

import android.Manifest
import android.app.Activity
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.net.VpnService
import android.os.Build
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.haoze.diting.overlay.FloatingLogOverlay
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class PermissionsBridge(private val activity: Activity) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.haoze.diting/permissions"

        private const val GET_INSTALLED_APPS = "com.android.permission.GET_INSTALLED_APPS"

        private const val REQUEST_NOTIFICATION = 0x5801
        private const val REQUEST_APP_LIST = 0x5802
        private const val REQUEST_VPN = 0x5803
        private const val REQUEST_SETTINGS = 0x5804
    }

    private var pending: MethodChannel.Result? = null

    private var pendingPermission: String? = null

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "states" -> result.success(states())
            "request" -> request(call.argument<String>("permission").orEmpty(), result)
            "openNotificationSettings" -> result.success(openNotificationSettings())
            "openAppSettings" -> result.success(openAppSettings())
            else -> result.notImplemented()
        }
    }

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
            val manager = activity.getSystemService(NotificationManager::class.java)
            return manager?.areNotificationsEnabled() ?: true
        }
        return hasPermission(Manifest.permission.POST_NOTIFICATIONS)
    }

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

    private fun isIgnoringBatteryOptimizations(): Boolean =
        BatteryOptimizationProbe.isIgnoring(activity)

    private fun hasPermission(permission: String): Boolean =
        ContextCompat.checkSelfPermission(activity, permission) ==
            PackageManager.PERMISSION_GRANTED

    private fun request(name: String, result: MethodChannel.Result) {
        if (pending != null) {
            result.error("request_busy", "另一个权限请求仍在等待", null)
            return
        }
        pendingPermission = name
        when (name) {
            "vpn" -> requestVpn(result)
            "notification" -> requestNotification(result)
            "appList" -> requestAppList(result)
            "batteryOptimization" -> requestBatteryOptimization(result)
            "overlay" -> requestOverlay(result)
            else -> result.error("unknown_permission", "未知的权限：$name", null)
        }
    }

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
        val intent = if (activity.packageManager.resolveActivity(direct, 0) != null) {
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

    fun onActivityResult(requestCode: Int, resultCode: Int): Boolean {
        val mine = requestCode == REQUEST_NOTIFICATION ||
            requestCode == REQUEST_APP_LIST ||
            requestCode == REQUEST_VPN ||
            requestCode == REQUEST_SETTINGS
        if (!mine) return false
        finish(resultCode)
        return true
    }

    fun onRequestPermissionsResult(requestCode: Int): Boolean {
        if (requestCode != REQUEST_NOTIFICATION && requestCode != REQUEST_APP_LIST) {
            return false
        }
        finish(Activity.RESULT_OK)
        return true
    }

    private fun finish(resultCode: Int) {
        val result = pending ?: return
        val permission = pendingPermission
        pending = null
        pendingPermission = null
        if (permission == "batteryOptimization") {
            BatteryOptimizationProbe.awaitSettled(activity) {
                result.success(states() + mapOf("result" to resultCode))
            }
            return
        }
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
