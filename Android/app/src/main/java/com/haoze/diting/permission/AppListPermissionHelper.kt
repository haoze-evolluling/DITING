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

    @Volatile
    private var cachedCanQuery: Boolean? = null
    @Volatile
    private var lastQueryTimestamp: Long = 0L
    private const val CACHE_TTL_MS = 1500L

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    /**
     * 清空应用查询探测的内存缓存，强制下次检测时重新探测。
     */
    fun invalidateCache() {
        cachedCanQuery = null
        lastQueryTimestamp = 0L
    }

    /**
     * 判断当前是否具备读取已安装应用列表的权限。
     *
     * 1. 优先检查系统运行时权限 com.android.permission.GET_INSTALLED_APPS 是否已获授予（针对 MIUI/HyperOS、ColorOS 等定制系统）。
     * 2. 若未通过运行时权限判定，则进行安全的原生包管理器探测（适用于原生 Android / AOSP / Pixel）。
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
     * 内部使用短时内存缓存，避免在主线程 UI 重组时反复触发昂贵的 Binder IPC。
     */
    fun canQueryInstalledApps(context: Context): Boolean {
        val now = System.currentTimeMillis()
        val cached = cachedCanQuery
        if (cached != null && (now - lastQueryTimestamp) < CACHE_TTL_MS) {
            return cached
        }

        val result = try {
            val pm = context.packageManager
            val apps = pm.getInstalledApplications(0)
            apps.any { it.packageName != context.packageName }
        } catch (_: SecurityException) {
            false
        } catch (_: Exception) {
            false
        }

        cachedCanQuery = result
        lastQueryTimestamp = now
        return result
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
     * 1. 自动同步确认前置隐私披露。
     * 2. 若未要求降级至设置且提供了有效 launcher，尝试拉起系统运行时弹窗。
     * 3. 若系统弹窗无法拉起或指定降级，则引导用户跳转应用设置页。
     */
    fun requestPermission(
        activity: Activity?,
        launcher: ActivityResultLauncher<String>?,
        context: Context,
        fallbackToSettings: Boolean = false
    ) {
        setDisclosureAccepted(context, true)
        invalidateCache()

        if (isGranted(context)) return

        if (!fallbackToSettings && launcher != null) {
            try {
                launcher.launch(PERMISSION_GET_INSTALLED_APPS)
                return
            } catch (_: Exception) {
                // 系统不支持该权限弹窗调起，继续降级到设置页
            }
        }

        openAppSettings(context)
    }
}
