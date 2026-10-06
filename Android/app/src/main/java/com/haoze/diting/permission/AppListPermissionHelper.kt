package com.haoze.diting.permission

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.widget.Toast
import androidx.activity.result.ActivityResultLauncher
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat

/**
 * 统一管理“应用列表访问权限”的检测、授权请求及状态同步。
 *
 * 针对国内厂商系统（HyperOS/MIUI、ColorOS、OriginOS、EMUI 等）自定义的运行时权限
 * com.android.permission.GET_INSTALLED_APPS，以及原生 Android (AOSP/Pixel) 的
 * QUERY_ALL_PACKAGES 机制，提供统一、可靠的权限判定与授权跳转。
 */
object AppListPermissionHelper {

    const val PERMISSION_GET_INSTALLED_APPS = "com.android.permission.GET_INSTALLED_APPS"
    private const val PREFS_NAME = "permission_disclosures"
    private const val KEY_APP_LIST_EXPLAINED = "app_list_explained"
    private const val KEY_RUNTIME_REQUEST_ATTEMPTED = "app_list_runtime_request_attempted"

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    /**
     * 判断当前是否具备读取已安装应用列表的权限。
     *
     * 1. 优先检查系统运行时权限 com.android.permission.GET_INSTALLED_APPS 是否已获授予。
     * 2. 若未明确获得运行时授权，则进行安全的应用列表探测，验证是否能实际读取到其他已安装应用。
     *    （适用于 AOSP/Pixel、Android 10 及以下等未将该权限列为运行时危险权限的系统）
     */
    fun isGranted(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val runtimeStatus = ContextCompat.checkSelfPermission(
                context,
                PERMISSION_GET_INSTALLED_APPS
            )
            if (runtimeStatus == PackageManager.PERMISSION_GRANTED) {
                return true
            }
        }
        return canQueryInstalledApps(context)
    }

    /**
     * 实际探测是否能通过 PackageManager 读取到除本应用以外的已安装应用。
     */
    fun canQueryInstalledApps(context: Context): Boolean {
        return try {
            val pm = context.packageManager
            val apps = pm.getInstalledApplications(0)
            apps.any { it.packageName != context.packageName }
        } catch (_: SecurityException) {
            false
        } catch (_: Exception) {
            false
        }
    }

    /**
     * 判断前置说明（隐私披露）是否已被用户确认同意。
     */
    fun isDisclosureAccepted(context: Context): Boolean {
        return prefs(context).getBoolean(KEY_APP_LIST_EXPLAINED, false)
    }

    /**
     * 记录前置说明（隐私披露）确认状态。
     */
    fun setDisclosureAccepted(context: Context, accepted: Boolean) {
        prefs(context).edit().putBoolean(KEY_APP_LIST_EXPLAINED, accepted).apply()
    }

    /**
     * 判断是否已尝试过调起系统运行时权限弹窗。
     */
    fun hasAttemptedRuntimeRequest(context: Context): Boolean {
        return prefs(context).getBoolean(KEY_RUNTIME_REQUEST_ATTEMPTED, false)
    }

    /**
     * 记录已尝试调起系统运行时权限弹窗。
     */
    fun recordRuntimeRequestAttempted(context: Context) {
        prefs(context).edit().putBoolean(KEY_RUNTIME_REQUEST_ATTEMPTED, true).apply()
    }

    /**
     * 重置运行时权限尝试标记。
     */
    fun resetRuntimeRequestAttempted(context: Context) {
        prefs(context).edit().remove(KEY_RUNTIME_REQUEST_ATTEMPTED).apply()
    }

    /**
     * 创建跳转应用设置详情页的 Intent。
     */
    fun createSettingsIntent(context: Context): Intent {
        return Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.parse("package:${context.packageName}")
        }
    }

    /**
     * 打开应用设置详情页供用户手动授予权限，并展示操作提示。
     */
    fun openAppSettings(context: Context) {
        val intent = createSettingsIntent(context).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        try {
            context.startActivity(intent)
            Toast.makeText(context, "请在权限管理中允许“读取已安装应用列表”", Toast.LENGTH_LONG).show()
        } catch (_: ActivityNotFoundException) {
            runCatching {
                context.startActivity(
                    Intent(Settings.ACTION_SETTINGS).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                )
            }
        }
    }

    /**
     * 触发统一的授权请求流程。
     *
     * - 若尚未尝试过运行时授权弹窗，或系统允许展示授权理由（未勾选“不再询问”），则优先调起系统弹窗。
     * - 若无法通过弹窗调起或已被永久拒绝，则引导跳转系统应用设置页。
     */
    fun requestPermission(
        activity: Activity?,
        launcher: ActivityResultLauncher<String>?,
        context: Context
    ) {
        if (isGranted(context)) return

        if (launcher != null) {
            val hasAttempted = hasAttemptedRuntimeRequest(context)
            val canShowRationale = activity != null &&
                ActivityCompat.shouldShowRequestPermissionRationale(activity, PERMISSION_GET_INSTALLED_APPS)

            if (!hasAttempted || canShowRationale) {
                recordRuntimeRequestAttempted(context)
                try {
                    launcher.launch(PERMISSION_GET_INSTALLED_APPS)
                    return
                } catch (_: Exception) {
                    // 系统不支持该权限弹窗调起，继续降级到设置页
                }
            }
        }

        openAppSettings(context)
    }
}
