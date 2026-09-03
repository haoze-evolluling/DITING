package com.haoze.dnssr.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.haoze.dnssr.notification.NotificationPermissionHelper
import com.haoze.dnssr.notification.NotificationSettingsStore
import com.haoze.dnssr.notification.VpnMonitorManager
import com.haoze.dnssr.ui.components.SettingsActionButton
import com.haoze.dnssr.ui.components.SettingsCornerShape
import com.haoze.dnssr.ui.components.SettingsGroupTitle
import com.haoze.dnssr.ui.components.SettingsInfoText
import com.haoze.dnssr.ui.components.SettingsNavigationGroup
import com.haoze.dnssr.ui.components.SettingsNavigationItemData
import com.haoze.dnssr.ui.components.SettingsScaffold
import com.haoze.dnssr.ui.components.SettingsSurfaceGroup
import com.haoze.dnssr.ui.components.SettingsSwitchItem
import com.haoze.dnssr.vpn.DnsVpnService

@Composable
fun NotificationSettingsScreen(onBack: () -> Unit, title: String = "通知设置") {
    val context = LocalContext.current
    var persistentEnabled by remember {
        mutableStateOf(NotificationSettingsStore.isPersistentNotificationEnabled(context))
    }
    var speedEnabled by remember {
        mutableStateOf(NotificationSettingsStore.isTrafficSpeedEnabled(context))
    }
    var runningText by remember {
        mutableStateOf(NotificationSettingsStore.getCustomRunningText(context))
    }
    var stoppedText by remember {
        mutableStateOf(NotificationSettingsStore.getCustomStoppedText(context))
    }

    val hasPermission = NotificationPermissionHelper.hasPermission(context)

    SettingsScaffold(title = localizedText(title), onBack = onBack) { innerPadding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            item { SettingsGroupTitle(localizedText("常驻与监控")) }
            item {
                SettingsSurfaceGroup(
                    content = listOf {
                        SettingsSwitchItem(
                            title = localizedText("通知常驻"),
                            subtitle = localizedText("VPN 未运行时在通知栏常驻提醒，不影响 VPN 运行中的连接通知"),
                            checked = persistentEnabled,
                            onCheckedChange = { enabled ->
                                persistentEnabled = enabled
                                NotificationSettingsStore.setPersistentNotificationEnabled(context, enabled)
                                VpnMonitorManager.sync(context)
                            }
                        )
                    }
                )
            }
            item {
                SettingsInfoText(
                    localizedText("关闭“通知常驻”只会停止 VPN 未运行时的监控提醒。VPN 正在运行时，系统要求的前台服务通知会继续显示。")
                )
            }

            item { SettingsGroupTitle(localizedText("实时速率")) }
            item {
                SettingsSurfaceGroup(
                    content = listOf {
                        SettingsSwitchItem(
                            title = localizedText("通知栏显示实时速率"),
                            subtitle = localizedText("服务开启时在通知栏中实时显示上传和下载速率"),
                            checked = speedEnabled,
                            onCheckedChange = { enabled ->
                                speedEnabled = enabled
                                NotificationSettingsStore.setTrafficSpeedEnabled(context, enabled)
                                DnsVpnService.refreshNotification(context)
                            }
                        )
                    }
                )
            }

            item { SettingsGroupTitle(localizedText("通知栏文案")) }
            item {
                SettingsSurfaceGroup(
                    content = listOf {
                        Column(
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            OutlinedTextField(
                                value = runningText,
                                onValueChange = { runningText = it },
                                label = { Text(localizedText("DNS 服务开启时")) },
                                minLines = 2,
                                shape = SettingsCornerShape,
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(start = 16.dp, top = 16.dp, end = 16.dp)
                            )
                            OutlinedTextField(
                                value = stoppedText,
                                onValueChange = { stoppedText = it },
                                label = { Text(localizedText("DNS 服务关闭时")) },
                                minLines = 2,
                                shape = SettingsCornerShape,
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(16.dp)
                            )
                            SettingsActionButton(
                                onClick = {
                                    NotificationSettingsStore.setCustomTexts(context, runningText, stoppedText)
                                    DnsVpnService.refreshNotification(context)
                                    VpnMonitorManager.sync(context)
                                    onBack()
                                },
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(start = 16.dp, end = 16.dp, bottom = 16.dp)
                            ) {
                                Text(localizedText("确定"))
                            }
                        }
                    }
                )
            }
            item {
                SettingsInfoText(localizedText("两项内容均可留空；留空后对应通知栏会使用默认状态文案。"))
            }

            item { SettingsGroupTitle(localizedText("系统权限")) }
            item {
                SettingsNavigationGroup(
                    items = listOf(
                        SettingsNavigationItemData(
                            title = localizedText("系统通知权限"),
                            subtitle = localizedText("前往系统设置管理谛听的通知与渠道配置"),
                            value = if (hasPermission) localizedText("已授予") else localizedText("未授予"),
                            onClick = { NotificationPermissionHelper.openNotificationSettings(context) }
                        )
                    )
                )
            }
        }
    }
}
