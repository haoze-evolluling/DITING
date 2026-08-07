package com.haoze.dnssr.ui

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import com.haoze.dnssr.ui.components.SettingsGroup
import com.haoze.dnssr.ui.components.SettingsGroupTitle
import com.haoze.dnssr.ui.components.SettingsInfoText
import com.haoze.dnssr.ui.components.SettingsItem
import com.haoze.dnssr.ui.components.SettingsNavigationGroup
import com.haoze.dnssr.ui.components.SettingsNavigationItemData
import com.haoze.dnssr.ui.components.SettingsScaffold
import com.haoze.dnssr.ui.components.SettingsSurfaceGroup
import com.haoze.dnssr.ui.components.SettingsSwitchItem
import com.haoze.dnssr.vpn.DnsVpnService
import com.haoze.dnssr.vpn.VpnMonitorService

@Composable
fun ForegroundBackgroundSettingsScreen(
    onBack: () -> Unit,
    title: String = "前后台行为",
    onHideFromRecentsChanged: (Boolean) -> Unit
) {
    val context = LocalContext.current
    val scrollState = rememberScrollState()
    var hideFromRecentsEnabled by remember {
        mutableStateOf(AppSettings.isHideFromRecentsEnabled(context))
    }
    var persistentNotificationEnabled by remember {
        mutableStateOf(AppSettings.isPersistentNotificationEnabled(context))
    }
    var batteryOptimizationIgnored by remember(context) {
        mutableStateOf(isBatteryOptimizationIgnored(context))
    }

    fun saveHideFromRecents(enabled: Boolean) {
        hideFromRecentsEnabled = enabled
        AppSettings.setHideFromRecentsEnabled(context, enabled)
        onHideFromRecentsChanged(enabled)
    }

    fun savePersistentNotification(enabled: Boolean) {
        persistentNotificationEnabled = enabled
        AppSettings.setPersistentNotificationEnabled(context, enabled)
        updateMonitorServiceForPersistentNotification(context, enabled)
    }

    fun handleBatteryOptimizationClick() {
        val ignored = isBatteryOptimizationIgnored(context)
        batteryOptimizationIgnored = ignored
        if (!ignored) {
            requestIgnoreBatteryOptimization(context)
        }
    }

    SettingsScaffold(
        title = title,
        onBack = onBack
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .verticalScroll(scrollState),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            SettingsGroupTitle(localizedText("后台"))
            SettingsSurfaceGroup(content = listOf(
                {
                    SettingsSwitchItem(
                    title = localizedText("后台隐藏"),
                    subtitle = localizedText("开启后隐藏最近任务卡片，并在支持的系统上禁用任务截图"),
                        checked = hideFromRecentsEnabled,
                        onCheckedChange = ::saveHideFromRecents
                    )
                },
                {
                    SettingsSwitchItem(
                    title = localizedText("通知常驻"),
                    subtitle = localizedText("VPN 未运行时在通知栏常驻提醒，不影响 VPN 运行中的连接通知"),
                        checked = persistentNotificationEnabled,
                        onCheckedChange = ::savePersistentNotification
                    )
                }
            ))
            SettingsInfoText(localizedText("关闭“通知常驻”只会停止 VPN 未运行时的监控提醒。VPN 正在运行时，系统要求的前台服务通知会继续显示。"))
            SettingsGroupTitle(localizedText("电池"))
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                SettingsNavigationGroup(
                    items = listOf(
                        SettingsNavigationItemData(
                    title = localizedText("忽略电池优化"),
                        subtitle = if (batteryOptimizationIgnored) {
                            localizedText("已忽略电池优化")
                        } else {
                            localizedText("允许应用在后台稳定运行")
                        },
                        value = if (batteryOptimizationIgnored) localizedText("已忽略") else null,
                        enabled = !batteryOptimizationIgnored,
                        onClick = ::handleBatteryOptimizationClick
                        )
                    )
                )
            } else {
                SettingsSurfaceGroup(content = listOf {
                    SettingsItem(
                        title = localizedText("忽略电池优化"),
                        subtitle = localizedText("当前 Android 版本不支持电池优化设置"),
                        enabled = false
                    )
                })
            }
        }
    }
}

private fun isBatteryOptimizationIgnored(context: Context): Boolean {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false
    val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
    return powerManager.isIgnoringBatteryOptimizations(context.packageName)
}

private fun requestIgnoreBatteryOptimization(context: Context) {
    val requestIntent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
        data = android.net.Uri.parse("package:${context.packageName}")
    }
    try {
        context.startActivity(requestIntent)
    } catch (_: ActivityNotFoundException) {
        context.startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
    }
}

private fun updateMonitorServiceForPersistentNotification(
    context: Context,
    enabled: Boolean
) {
    if (!enabled) {
        context.stopService(VpnMonitorService.stopIntent(context))
        return
    }
    if (DnsVpnService.isRunning(context) || !hasNotificationPermission(context)) return
    ContextCompat.startForegroundService(context, VpnMonitorService.startIntent(context))
}

private fun hasNotificationPermission(context: Context): Boolean {
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.POST_NOTIFICATIONS
        ) == PackageManager.PERMISSION_GRANTED
    } else {
        true
    }
}
