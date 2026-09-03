package com.haoze.dnssr.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import android.widget.Toast
import com.haoze.dnssr.ui.components.SettingsGroup
import com.haoze.dnssr.ui.components.SettingsGroupTitle
import com.haoze.dnssr.ui.components.SettingsInfoText
import com.haoze.dnssr.ui.components.SettingsRadioItem
import com.haoze.dnssr.ui.components.SettingsScaffold
import com.haoze.dnssr.ui.components.SettingsSurfaceGroup
import com.haoze.dnssr.ui.components.SettingsSwitchItem
import com.haoze.dnssr.vpn.DnsVpnService
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver

private val logRetentionOptions = listOf(1, 7, 30)

@Composable
fun LogRetentionSettingsScreen(
    onBack: () -> Unit,
    onRuntimeDnsSettingsChanged: () -> Unit,
    title: String = "日志模式"
) {
    val context = LocalContext.current
    val scrollState = rememberScrollState()

    var logRetention by remember { mutableIntStateOf(AppSettings.logRetentionDays(context)) }
    var logMode by remember { mutableStateOf(AppSettings.getDnsLogMode(context)) }
    var floatingLogEnabled by remember { mutableStateOf(AppSettings.isFloatingLogEnabled(context)) }
    var waitingForOverlayPermission by remember { mutableStateOf(false) }
    val lifecycleOwner = LocalLifecycleOwner.current

    DisposableEffect(lifecycleOwner, waitingForOverlayPermission) {
        if (!waitingForOverlayPermission) return@DisposableEffect onDispose { }
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                waitingForOverlayPermission = false
                if (Settings.canDrawOverlays(context)) {
                    floatingLogEnabled = true
                    AppSettings.setFloatingLogEnabled(context, true)
                    DnsVpnService.refreshFloatingLogOverlay(context)
                } else {
                    floatingLogEnabled = false
                    AppSettings.setFloatingLogEnabled(context, false)
                    Toast.makeText(context, localizedText(context, "未授予悬浮窗权限，悬浮窗日志未开启"), Toast.LENGTH_SHORT).show()
                }
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    fun setFloatingLog(enabled: Boolean) {
        if (!enabled) {
            floatingLogEnabled = false
            AppSettings.setFloatingLogEnabled(context, false)
            DnsVpnService.refreshFloatingLogOverlay(context)
            return
        }
        if (Settings.canDrawOverlays(context)) {
            floatingLogEnabled = true
            AppSettings.setFloatingLogEnabled(context, true)
            DnsVpnService.refreshFloatingLogOverlay(context)
        } else {
            waitingForOverlayPermission = true
            runCatching {
                context.startActivity(
                    Intent(
                        Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                        Uri.parse("package:${context.packageName}")
                    )
                )
            }.onFailure {
                waitingForOverlayPermission = false
                Toast.makeText(context, localizedText(context, "无法打开悬浮窗权限设置"), Toast.LENGTH_SHORT).show()
            }
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
            SettingsGroupTitle(localizedText("DNS 请求日志"))
            SettingsSurfaceGroup(
                content = DnsLogMode.entries.map { mode ->
                    {
                        SettingsRadioItem(
                            title = localizedText(mode.displayName),
                            subtitle = when (mode) {
                                DnsLogMode.ALL -> localizedText("保存通过、拦截和错误请求")
                                DnsLogMode.BLOCKED_AND_ERRORS -> localizedText("减少数据库写入，同时保留关键记录")
                                DnsLogMode.OFF -> localizedText("不创建或写入 DNS 请求日志")
                            },
                            selected = logMode == mode,
                            contentPadding = PaddingValues(horizontal = 24.dp, vertical = 20.dp),
                            onClick = {
                                logMode = mode
                                AppSettings.setDnsLogMode(context, mode)
                                onRuntimeDnsSettingsChanged()
                            }
                        )
                    }
                }
            )
            SettingsInfoText(localizedText("关闭后不会删除已有日志，重新开启即可继续查看。"))

            SettingsGroupTitle(localizedText("悬浮窗"))
            SettingsSurfaceGroup(content = listOf {
                SettingsSwitchItem(
                    title = localizedText("悬浮窗日志"),
                    subtitle = localizedText("VPN 运行且应用在后台时显示悬浮球，点击查看最近请求"),
                    checked = floatingLogEnabled,
                    onCheckedChange = ::setFloatingLog
                )
            })
            SettingsInfoText(localizedText("需要系统悬浮窗权限；回到应用前台时悬浮窗会自动隐藏。"))

            if (logMode != DnsLogMode.OFF) {
            SettingsGroupTitle(localizedText("自动清理时间"))
            SettingsSurfaceGroup(
                content = logRetentionOptions.map { days ->
                    {
                        SettingsRadioItem(
                            title = localizedText("保留 $days 天"),
                            selected = logRetention == days,
                            contentPadding = PaddingValues(horizontal = 24.dp, vertical = 20.dp),
                            onClick = {
                                logRetention = days
                                AppSettings.setLogRetentionDays(context, days)
                            }
                        )
                    }
                }
            )
            SettingsInfoText(localizedText("超过所选时间的 DNS 请求日志会自动删除，用于控制本地日志占用。"))
            }
        }
    }
}
