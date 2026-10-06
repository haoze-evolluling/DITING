package com.haoze.diting.permission

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner

/**
 * 统一管理“忽略电池优化权限”的检测、授权申请、降级处理与状态同步。
 *
 * 针对各厂商系统（AOSP/Pixel、HyperOS/MIUI、ColorOS、OriginOS、EMUI 等）提供统一且可靠的
 * 电池白名单检测与申请流程，彻底杜绝权限误判、重复申请及二级页面与首页状态不同步。
 */
object BatteryOptimizationHelper {

    private const val CACHE_TTL_MS = 1500L

    @Volatile
    private var cachedIsIgnored: Boolean? = null

    @Volatile
    private var lastQueryTimestamp: Long = 0L

    /**
     * 清空电池优化状态的内存缓存，强制下次检测时重新向系统服务查询。
     */
    fun invalidateCache() {
        cachedIsIgnored = null
        lastQueryTimestamp = 0L
    }

    /**
     * 判断当前应用是否已处于系统“忽略电池优化”（白名单）状态。
     *
     * 1. Android 6.0 (API 23) 以下设备无 Doze 电池优化机制，恒定返回 true。
     * 2. 具备短时内存缓存，避免在 Compose 高频重组或渲染时频繁发起 Binder IPC。
     * 3. 安全获取 PowerManager 服务并捕获异常，杜绝由于系统服务缺失或异常导致的崩溃。
     */
    fun isGranted(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return true
        }

        val now = System.currentTimeMillis()
        val cached = cachedIsIgnored
        if (cached != null && (now - lastQueryTimestamp) < CACHE_TTL_MS) {
            return cached
        }

        val result = try {
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
            powerManager?.isIgnoringBatteryOptimizations(context.packageName) ?: false
        } catch (_: Exception) {
            false
        }

        cachedIsIgnored = result
        lastQueryTimestamp = now
        return result
    }

    /**
     * 判断用户是否已选择忽略此项建议。
     */
    fun isDismissed(context: Context): Boolean {
        return ModePermissionStore.isRecommendationDismissed(context, AppPermission.BATTERY_OPTIMIZATION)
    }

    /**
     * 记录用户忽略此项建议的决定。
     */
    fun setDismissed(context: Context, dismissed: Boolean) {
        ModePermissionStore.setRecommendationDismissed(context, AppPermission.BATTERY_OPTIMIZATION, dismissed)
    }

    /**
     * 创建系统级“请求忽略电池优化”直接弹窗 Intent。
     */
    fun createRequestIntent(context: Context): Intent {
        return Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
            data = Uri.parse("package:${context.packageName}")
        }
    }

    /**
     * 创建跳转系统“电池优化设置列表” Intent。
     */
    fun createSettingsIntent(): Intent {
        return Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
    }

    /**
     * 创建跳转应用详情设置 Intent 作为终极降级路径。
     */
    fun createAppSettingsIntent(context: Context): Intent {
        return Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.parse("package:${context.packageName}")
        }
    }

    /**
     * 统一发起忽略电池优化申请流程。
     *
     * 1. 若当前已处于忽略状态，则直接触发 onAlreadyGranted 回调并返回，避免无谓弹窗与重复申请。
     * 2. 优先通过系统弹窗 Action 请求当前应用豁免。
     * 3. 若当前系统不支持弹窗或拦截报错，自动降级打开系统电池优化列表或应用设置详情页。
     */
    fun requestPermission(
        context: Context,
        launcher: ActivityResultLauncher<Intent>? = null,
        onAlreadyGranted: (() -> Unit)? = null
    ) {
        if (isGranted(context)) {
            invalidateCache()
            onAlreadyGranted?.invoke()
            return
        }

        invalidateCache()

        val requestIntent = createRequestIntent(context)
        val settingsIntent = createSettingsIntent()
        val appSettingsIntent = createAppSettingsIntent(context)

        if (context !is Activity) {
            requestIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            settingsIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            appSettingsIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

        if (launcher != null) {
            try {
                launcher.launch(requestIntent)
                return
            } catch (_: Exception) {
                // 请求弹窗受阻，降级至电池优化设置页
            }

            try {
                launcher.launch(settingsIntent)
                return
            } catch (_: Exception) {
                // 再次降级至应用详情页
            }

            try {
                launcher.launch(appSettingsIntent)
                return
            } catch (_: Exception) {
                // 忽略最终启动异常
            }
        } else {
            try {
                context.startActivity(requestIntent)
                return
            } catch (_: Exception) {
                // 降级尝试
            }

            try {
                context.startActivity(settingsIntent)
                return
            } catch (_: Exception) {
                // 降级尝试
            }

            try {
                context.startActivity(appSettingsIntent)
                return
            } catch (_: Exception) {
                // 忽略最终启动异常
            }
        }
    }

    /**
     * Compose 级统一电池优化状态监听。
     * 自动随 Lifecycle ON_RESUME 与 Launcher 返回刷新最新状态，保证实时双向同步。
     */
    @Composable
    fun rememberBatteryOptimizationState(
        onGranted: (() -> Unit)? = null
    ): BatteryOptimizationState {
        val context = LocalContext.current
        val lifecycleOwner = LocalLifecycleOwner.current

        var isIgnored by remember {
            mutableStateOf(isGranted(context))
        }

        fun refresh() {
            invalidateCache()
            val current = isGranted(context)
            isIgnored = current
            if (current) {
                onGranted?.invoke()
            }
        }

        val launcher = rememberLauncherForActivityResult(
            contract = ActivityResultContracts.StartActivityForResult()
        ) {
            refresh()
        }

        DisposableEffect(lifecycleOwner) {
            val observer = LifecycleEventObserver { _, event ->
                if (event == Lifecycle.Event.ON_RESUME) {
                    refresh()
                }
            }
            lifecycleOwner.lifecycle.addObserver(observer)
            onDispose {
                lifecycleOwner.lifecycle.removeObserver(observer)
            }
        }

        return remember(isIgnored) {
            BatteryOptimizationState(
                isIgnored = isIgnored,
                requestIgnore = {
                    if (!isIgnored) {
                        requestPermission(
                            context = context,
                            launcher = launcher,
                            onAlreadyGranted = ::refresh
                        )
                    }
                },
                refresh = ::refresh
            )
        }
    }
}

/**
 * 电池优化状态包装对象。
 */
class BatteryOptimizationState(
    val isIgnored: Boolean,
    val requestIgnore: () -> Unit,
    val refresh: () -> Unit
)
