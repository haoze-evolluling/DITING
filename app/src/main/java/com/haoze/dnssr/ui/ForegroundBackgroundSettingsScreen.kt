package com.haoze.dnssr.ui

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
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
import com.haoze.dnssr.ui.components.SettingsGroupTitle
import com.haoze.dnssr.ui.components.SettingsInfoText
import com.haoze.dnssr.ui.components.SettingsNavigationGroup
import com.haoze.dnssr.ui.components.SettingsNavigationItemData
import com.haoze.dnssr.ui.components.SettingsScaffold
import com.haoze.dnssr.ui.components.SettingsSurfaceGroup
import com.haoze.dnssr.ui.components.SettingsSwitchItem

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
    var bypassLanEnabled by remember {
        mutableStateOf(AppSettings.isBypassLanEnabled(context))
    }
    var batteryOptimizationIgnored by remember(context) {
        mutableStateOf(isBatteryOptimizationIgnored(context))
    }

    fun saveHideFromRecents(enabled: Boolean) {
        hideFromRecentsEnabled = enabled
        AppSettings.setHideFromRecentsEnabled(context, enabled)
        onHideFromRecentsChanged(enabled)
    }

    fun saveBypassLan(enabled: Boolean) {
        bypassLanEnabled = enabled
        AppSettings.setBypassLanEnabled(context, enabled)
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
                        subtitle = localizedText("开启后隐藏最近任务卡片"),
                        checked = hideFromRecentsEnabled,
                        onCheckedChange = ::saveHideFromRecents
                    )
                }
            ))
            SettingsGroupTitle(localizedText("局域网"))
            SettingsSurfaceGroup(content = listOf(
                {
                    SettingsSwitchItem(
                        title = localizedText("绕过局域网"),
                        subtitle = localizedText("开启后局域网通信（如文件快传、投屏、NAS 访问等）直接走物理网络，不经过虚拟网卡"),
                        checked = bypassLanEnabled,
                        onCheckedChange = ::saveBypassLan
                    )
                }
            ))
            SettingsInfoText(localizedText("若日常使用快传、LocalSend、投屏或访问局域网设备，建议保持开启。修改后重新开启服务生效。"))
            SettingsGroupTitle(localizedText("电池"))
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
        }
    }
}

private fun isBatteryOptimizationIgnored(context: Context): Boolean {
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
