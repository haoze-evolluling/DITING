package com.haoze.dnssr.ui

import android.os.Build
import android.widget.Toast
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ErrorOutline
import com.haoze.dnssr.ui.components.AppAlertDialog as AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.haoze.dnssr.ui.components.SettingsGroupTitle
import com.haoze.dnssr.ui.components.SettingsNavigationItem
import com.haoze.dnssr.ui.components.SettingsSurfaceGroup
import com.haoze.dnssr.ui.components.SettingsScaffold
import com.haoze.dnssr.ui.components.SettingsSwitchItem
import kotlinx.coroutines.launch

@Composable
fun HttpInspectionSettingsScreen(
    onBack: () -> Unit,
    onNavigateToRequestLogs: () -> Unit,
    onNavigateToApps: () -> Unit,
    onNavigateToCaCertificateSettings: () -> Unit
) {
    val context = androidx.compose.ui.platform.LocalContext.current
    val supported = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
    var enabled by remember {
        mutableStateOf(
            AppSettings.isHttpInspectionEnabled(context) &&
                AppSettings.isHttpsInspectionReady(context) && supported
        )
    }
    var httpsReady by remember { mutableStateOf(AppSettings.isHttpsInspectionReady(context)) }
    var filterHttp3 by remember { mutableStateOf(AppSettings.isHttp3InspectionEnabled(context)) }
    var blockEncryptedDns by remember { mutableStateOf(AppSettings.isEncryptedDnsBlockingEnabled(context)) }
    var initializingApps by remember { mutableStateOf(false) }
    var showUsageNotice by remember {
        mutableStateOf(!AppSettings.isSettingsGuideAcknowledged(context, SettingsGuides.HTTP_INSPECTION.id))
    }
    val scope = rememberCoroutineScope()
    val scrollState = rememberScrollState()
    val httpsControlsEnabled = supported && httpsReady

    SettingsScaffold(
        title = localizedText("HTTPS 流量检查"),
        onBack = onBack,
        actions = {
            IconButton(onClick = {
                showUsageNotice = true
            }) {
                Icon(Icons.Outlined.ErrorOutline, contentDescription = localizedText("使用前说明"))
            }
        }
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .verticalScroll(scrollState),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            SettingsGroupTitle(localizedText("检查范围"))
            val selectedCount = AppSettings.getHttpInspectionAppPackages(context).size
            val appPackagesInitialized = AppSettings.isHttpInspectionAppPackagesInitialized(context)
            SettingsSurfaceGroup(
                content = listOf(
                    {
                SettingsSwitchItem(
                    title = localizedText("启用所选应用的 HTTPS 流量检查"),
                        subtitle = localizedText(when {
                        !httpsReady -> "需先安装并验证 HTTPS 检查根证书"
                        selectedCount == 0 && !appPackagesInitialized -> "首次开启时默认选择全部用户应用"
                        selectedCount == 0 -> "尚未选择应用；开启后仅保留 DNS 过滤"
                        else -> "仅检查已选择的 $selectedCount 个应用；其他应用直接转发"
                    }),
                    checked = enabled,
                    enabled = httpsControlsEnabled && !initializingApps,
                    onCheckedChange = { checked ->
                        if (checked && !AppSettings.isHttpInspectionAppPackagesInitialized(context)) {
                            initializingApps = true
                            scope.launch {
                                runCatching {
                                    val currentPackages = AppSettings.getHttpInspectionAppPackages(context)
                                    val packages = if (currentPackages.isEmpty()) {
                                        loadUserAppPackages(context)
                                    } else {
                                        currentPackages
                                    }
                                    check(packages.isNotEmpty()) { "没有可用于 HTTPS 检查的用户应用" }

                                    AppSettings.setHttpInspectionAppPackages(context, packages)
                                    AppSettings.setExcludedAppPackages(
                                        context,
                                        AppSettings.getExcludedAppPackages(context) - packages
                                    )
                                    AppSettings.setBlockedAppPackages(
                                        context,
                                        AppSettings.getBlockedAppPackages(context) - packages
                                    )
                                    AppSettings.setAppAllowlistPackages(
                                        context,
                                        AppSettings.getAppAllowlistPackages(context) - packages
                                    )
                                    if (AppSettings.getDnsResolutionMode(context) in setOf(
                                            DnsResolutionMode.SMART_PREDICTION,
                                            DnsResolutionMode.PARALLEL_RACE
                                        )) {
                                        AppSettings.setDnsResolutionMode(context, DnsResolutionMode.SINGLE)
                                    }
                                    AppSettings.setHttpInspectionEnabled(context, true)
                                    RuntimeDnsSettingsRefresher.refreshAppExclusionsIfRunning(context)
                                    enabled = true
                                }.onFailure { error ->
                                    Toast.makeText(
                                        context,
                                        localizedText(context, error.message ?: "无法初始化 HTTPS 检查应用"),
                                        Toast.LENGTH_LONG
                                    ).show()
                                }
                                initializingApps = false
                            }
                        } else {
                            if (checked && AppSettings.getDnsResolutionMode(context) in setOf(
                                    DnsResolutionMode.SMART_PREDICTION,
                                    DnsResolutionMode.PARALLEL_RACE
                                )) {
                                AppSettings.setDnsResolutionMode(context, DnsResolutionMode.SINGLE)
                            }
                            enabled = checked
                            AppSettings.setHttpInspectionEnabled(context, checked)
                            RuntimeDnsSettingsRefresher.refreshAppExclusionsIfRunning(context)
                        }
                    }
                )
                    },
                    {
                        SettingsNavigationItem(
                        title = localizedText("选择检查应用"),
                        subtitle = localizedText(if (selectedCount == 0) "选择需要检查 HTTP(S) 流量的应用" else "已选择 $selectedCount 个应用"),
                        enabled = httpsControlsEnabled,
                        onClick = onNavigateToApps
                        )
                    },
                    {
                        SettingsNavigationItem(
                        title = localizedText("CA证书设置"),
                        subtitle = localizedText(if (httpsReady) {
                            "根证书已验证；可查看、重新安装或重置"
                        } else {
                            "安装并验证 HTTPS 检查根证书"
                        }),
                        onClick = onNavigateToCaCertificateSettings
                        )
                    }
                )
            )
            SettingsGroupTitle(localizedText("协议与兼容性"))
            SettingsSurfaceGroup(
                content = listOf(
                    {
                SettingsSwitchItem(
                    title = localizedText("尝试检查 HTTP/3"),
                    subtitle = localizedText("阻断所选应用的 QUIC，促使其回退到可检查的 TCP；部分站点可能加载失败"),
                    checked = filterHttp3,
                    enabled = httpsControlsEnabled,
                    onCheckedChange = { checked ->
                        filterHttp3 = checked
                        AppSettings.setHttp3InspectionEnabled(context, checked)
                        RuntimeDnsSettingsRefresher.refreshAppExclusionsIfRunning(context)
                    }
                )
                    },
                    {
                SettingsSwitchItem(
                    title = localizedText("阻止检查应用使用加密 DNS"),
                    subtitle = localizedText("仅阻断所选应用的 DNS-over-TLS（DoT/TCP 853），防止绕过域名规则"),
                    checked = blockEncryptedDns,
                    enabled = httpsControlsEnabled,
                    onCheckedChange = { checked ->
                        blockEncryptedDns = checked
                        AppSettings.setEncryptedDnsBlockingEnabled(context, checked)
                        RuntimeDnsSettingsRefresher.refreshAppExclusionsIfRunning(context)
                    }
                )
                    },
                    {
                        SettingsNavigationItem(
                        title = localizedText("HTTPS 请求记录"),
                    subtitle = localizedText("查看 HTTPS 流量检查的逐请求结果和 HTTPS 检查自动旁路记录"),
                        onClick = onNavigateToRequestLogs
                        )
                    }
                )
            )
        }
    }

    if (showUsageNotice) {
        BackHandler(enabled = true) {}
        AlertDialog(
            onDismissRequest = {},
            title = { Text(localizedText(SettingsGuides.HTTP_INSPECTION.title)) },
            text = {
                Column {
                    if (supported) {
                        Text(
                            buildAnnotatedString {
                                withStyle(SpanStyle(color = androidx.compose.material3.MaterialTheme.colorScheme.error)) {
                                    append(
                                        localizedText("此功能不适合没有相关经验的用户。安装、卸载或重新安装 CA 证书需要一定操作能力，操作不当可能导致部分应用无法联网；仅在你能自行处理这些问题时使用。")
                                    )
                                }
                                append("\n\n")
                                append(
                                    localizedText("开启后，Go 隧道会接管流量，但仅检查明确选择的应用；其他应用直接转发。HTTPS 仅在应用信任 HTTPS 检查根证书且未使用证书固定或自定义校验时才能解密。")
                                )
                                append("\n\n")
                                append(
                                    localizedText("不兼容的连接会作为 HTTPS 检查自动旁路直接转发。HTTP/3（QUIC）默认直连；开启“尝试检查 HTTP/3”后，会阻断所选应用的 UDP 443，促使支持回退的客户端改用 TCP。")
                                )
                            }
                        )
                    } else {
                        Text(
                            localizedText("HTTP(S) 流量检查需要 Android 10 或更高版本，当前设备不满足运行条件，因此本页功能无法启用，谛听将继续使用 DNS-only 模式。DNS 解析、域名规则和其他基础功能不会受到影响，也不需要安装根证书。若以后升级到受支持的系统，请在启用前了解证书安装、应用信任和 HTTPS 解密的限制；配置不当可能导致部分应用无法联网，证书固定或自定义校验的连接也可能无法被检查。")
                        )
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    AppSettings.acknowledgeSettingsGuide(context, SettingsGuides.HTTP_INSPECTION.id)
                    showUsageNotice = false
                }) { Text(localizedText("我知道了")) }
            }
        )
    }

}
