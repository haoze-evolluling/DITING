package com.haoze.diting.express.ui

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
import com.haoze.diting.data.RuleDataset
import com.haoze.diting.ui.Ipv6Mode
import com.haoze.diting.ui.components.SettingsGroupTitle
import com.haoze.diting.ui.components.SettingsInfoText
import com.haoze.diting.ui.components.SettingsNavigationGroup
import com.haoze.diting.ui.components.SettingsNavigationItemData
import com.haoze.diting.ui.components.SettingsRadioItem
import com.haoze.diting.ui.components.SettingsScaffold
import com.haoze.diting.ui.components.SettingsSurfaceGroup
import com.haoze.diting.ui.components.SettingsSwitchItem
import com.haoze.diting.ui.localizedText
import com.haoze.diting.ui.settings.SystemSettingsStore

/**
 * Dedicated Foreground & Background Settings Screen for Express Mode.
 *
 * Physically omits the "绕过局域网" (LAN bypass) section, because Express Mode
 * operates on a narrow-route DNS TUN where non-DNS local network traffic
 * already bypasses the VPN completely at the OS level.
 */
@Composable
fun ExpressForegroundBackgroundSettingsScreen(
    onBack: () -> Unit,
    title: String = "前后台行为",
    onHideFromRecentsChanged: (Boolean) -> Unit
) {
    val context = LocalContext.current
    val scrollState = rememberScrollState()
    var hideFromRecentsEnabled by remember {
        mutableStateOf(SystemSettingsStore.isHideFromRecentsEnabled(context))
    }
    var ipv6Mode by remember {
        mutableStateOf(SystemSettingsStore.getIpv6Mode(context, RuleDataset.EXPRESS))
    }
    var batteryOptimizationIgnored by remember(context) {
        mutableStateOf(isBatteryOptimizationIgnored(context))
    }

    fun saveIpv6Mode(mode: Ipv6Mode) {
        ipv6Mode = mode
        SystemSettingsStore.setIpv6Mode(context, mode, RuleDataset.EXPRESS)
    }

    fun saveHideFromRecents(enabled: Boolean) {
        hideFromRecentsEnabled = enabled
        SystemSettingsStore.setHideFromRecentsEnabled(context, enabled)
        onHideFromRecentsChanged(enabled)
    }

    fun handleBatteryOptimizationClick() {
        val ignored = isBatteryOptimizationIgnored(context)
        batteryOptimizationIgnored = ignored
        if (!ignored) {
            requestIgnoreBatteryOptimization(context)
        }
    }

    SettingsScaffold(
        title = localizedText(title),
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

            SettingsGroupTitle(localizedText("IPv6 流量接管"))
            SettingsSurfaceGroup(content = listOf(
                {
                    SettingsRadioItem(
                        title = localizedText("自动探测（推荐）"),
                        subtitle = localizedText("根据物理网络是否具备公网 IPv6 地址及有效网关路由自动决策；在纯 IPv4 网络下自动关闭 IPv6 虚拟网卡，避免产生连接黑洞"),
                        selected = ipv6Mode == Ipv6Mode.AUTO,
                        onClick = { saveIpv6Mode(Ipv6Mode.AUTO) }
                    )
                },
                {
                    SettingsRadioItem(
                        title = localizedText("始终开启"),
                        subtitle = localizedText("虚拟网卡始终配置全局 IPv6 地址与路由"),
                        selected = ipv6Mode == Ipv6Mode.ENABLED,
                        onClick = { saveIpv6Mode(Ipv6Mode.ENABLED) }
                    )
                },
                {
                    SettingsRadioItem(
                        title = localizedText("始终禁用"),
                        subtitle = localizedText("仅配置 IPv4 虚拟网卡，强制所有双栈网站走 IPv4 隧道"),
                        selected = ipv6Mode == Ipv6Mode.DISABLED,
                        onClick = { saveIpv6Mode(Ipv6Mode.DISABLED) }
                    )
                }
            ))
            SettingsInfoText(localizedText("若在无 IPv6 的 Wi-Fi 下出现部分网站无法打开，请保持“自动探测”或设为“始终禁用”。修改后重新开启服务生效。"))

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
