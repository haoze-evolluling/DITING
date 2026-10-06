package com.haoze.diting.permission

import android.Manifest
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.net.VpnService
import android.os.Build
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.compose.material3.Text
import com.haoze.diting.notification.NotificationPermissionHelper
import com.haoze.diting.ui.PermissionDisclosureSettings
import com.haoze.diting.ui.components.AppAlertDialog
import com.haoze.diting.ui.components.AppDialogButton
import com.haoze.diting.ui.localizedText
import com.haoze.diting.ui.mode.AppWorkMode

/**
 * 位于主页顶部切换模式按钮左侧的危险权限未就绪提醒标志。
 *
 * 当存在任意未就绪权限时显示红色危险感叹号；
 * 点击弹出模态框提示最高优先级缺失权限，确认后引导授予或跳转设置。
 */
@Composable
fun ModePermissionWarningAction(
    mode: AppWorkMode,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current

    var readinessState by remember(mode) {
        mutableStateOf(ModeReadinessEvaluator.evaluate(context, mode))
    }
    var showDialog by remember { mutableStateOf(false) }

    var appListRequestAttempted by remember { mutableStateOf(false) }

    DisposableEffect(lifecycleOwner, mode) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                AppListPermissionHelper.invalidateCache()
                BatteryOptimizationHelper.invalidateCache()
                readinessState = ModeReadinessEvaluator.evaluate(context, mode)
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
        }
    }

    val missingPermissions = remember(readinessState) {
        readinessState.missingRequired + readinessState.getActiveRecommended(context)
    }
    val primaryMissing = missingPermissions.firstOrNull()

    val notificationLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission()
    ) { isGranted ->
        if (!isGranted && !NotificationPermissionHelper.hasPermission(context)) {
            NotificationPermissionHelper.openNotificationSettings(context)
        }
        readinessState = ModeReadinessEvaluator.evaluate(context, mode)
    }

    val vpnLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.StartActivityForResult()
    ) { result ->
        val granted = result.resultCode == Activity.RESULT_OK
        PermissionDisclosureSettings.updateVpnGrant(context, granted)
        readinessState = ModeReadinessEvaluator.evaluate(context, mode)
    }

    val batteryLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.StartActivityForResult()
    ) { _ ->
        BatteryOptimizationHelper.invalidateCache()
        readinessState = ModeReadinessEvaluator.evaluate(context, mode)
    }

    val appListLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission()
    ) { _ ->
        AppListPermissionHelper.invalidateCache()
        appListRequestAttempted = true
        readinessState = ModeReadinessEvaluator.evaluate(context, mode)
    }

    fun requestPermission(permission: AppPermission) {
        when (permission) {
            AppPermission.NOTIFICATION -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    notificationLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                } else {
                    NotificationPermissionHelper.openNotificationSettings(context)
                }
            }
            AppPermission.VPN -> {
                val intent = VpnService.prepare(context)
                if (intent != null) {
                    vpnLauncher.launch(intent)
                } else {
                    PermissionDisclosureSettings.updateVpnGrant(context, true)
                    readinessState = ModeReadinessEvaluator.evaluate(context, mode)
                }
            }
            AppPermission.BATTERY_OPTIMIZATION -> {
                BatteryOptimizationHelper.requestPermission(
                    context = context,
                    launcher = batteryLauncher,
                    onAlreadyGranted = {
                        BatteryOptimizationHelper.invalidateCache()
                        readinessState = ModeReadinessEvaluator.evaluate(context, mode)
                    }
                )
            }
            AppPermission.PACKAGE_QUERY -> {
                AppListPermissionHelper.requestPermission(
                    activity = context as? Activity,
                    launcher = if (appListRequestAttempted) null else appListLauncher,
                    context = context,
                    fallbackToSettings = appListRequestAttempted
                )
            }
            else -> {
                val intent = permission.createRequestIntent(context)
                if (intent != null) {
                    runCatching { context.startActivity(intent) }
                }
            }
        }
    }

    if (primaryMissing != null) {
        val isRecommended = primaryMissing.getLevel(mode) != PermissionLevel.REQUIRED
        IconButton(
            onClick = { showDialog = true },
            modifier = modifier
        ) {
            Icon(
                imageVector = Icons.Filled.Warning,
                contentDescription = localizedText("未授予权限警告"),
                tint = if (isRecommended) MaterialTheme.colorScheme.secondary else MaterialTheme.colorScheme.error
            )
        }

        if (showDialog) {
            val dialogTitle = "${primaryMissing.title}未授予"
            val explanation = when (primaryMissing) {
                AppPermission.VPN -> "当前${mode.title}需要建立本地 VPN 通道接管与解析 DNS。"
                AppPermission.NOTIFICATION -> "需要前台通知权限以维持服务正常运行并显示当前状态。"
                AppPermission.BATTERY_OPTIMIZATION -> "建议将谛听加入电池优化白名单，防止后台守护进程被系统强制回收。"
                AppPermission.PACKAGE_QUERY -> "用于选择需要排除、禁止联网或进行 HTTPS 检查的应用，仅在本地读取。"
                else -> primaryMissing.summary
            }
            val dialogMessage = "没有授予这个权限。$explanation"

            AppAlertDialog(
                onDismissRequest = { showDialog = false },
                icon = {
                    Icon(
                        imageVector = Icons.Filled.Warning,
                        contentDescription = null,
                        tint = if (isRecommended) MaterialTheme.colorScheme.secondary else MaterialTheme.colorScheme.error
                    )
                },
                title = { Text(localizedText(dialogTitle)) },
                text = {
                    Text(
                        localizedText(dialogMessage),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                },
                confirmButton = {
                    AppDialogButton(
                        label = "授予",
                        onClick = {
                            showDialog = false
                            requestPermission(primaryMissing)
                        }
                    )
                },
                dismissButton = {
                    AppDialogButton(
                        label = "取消",
                        onClick = { showDialog = false }
                    )
                },
                neutralButton = if (isRecommended) {
                    {
                        AppDialogButton(
                            label = "不再提示",
                            onClick = {
                                ModePermissionStore.setRecommendationDismissed(context, primaryMissing, true)
                                BatteryOptimizationHelper.invalidateCache()
                                readinessState = ModeReadinessEvaluator.evaluate(context, mode)
                                showDialog = false
                            }
                        )
                    }
                } else null
            )
        }
    }
}
