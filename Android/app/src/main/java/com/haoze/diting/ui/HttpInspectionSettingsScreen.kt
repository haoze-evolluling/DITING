package com.haoze.diting.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.haoze.diting.ui.components.DomainRulesInspectionLinkageDialog
import com.haoze.diting.ui.components.DomainRulesLinkageKind
import com.haoze.diting.ui.components.SettingsGroupTitle
import com.haoze.diting.ui.components.SettingsNavigationItem
import com.haoze.diting.ui.components.SettingsScaffold
import com.haoze.diting.ui.components.SettingsSurfaceGroup
import com.haoze.diting.ui.components.SettingsSwitchItem
import com.haoze.diting.ui.settings.AppRulesSettingsStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
fun HttpInspectionSettingsScreen(
    onBack: () -> Unit,
    onNavigateToRequestLogs: () -> Unit,
    onNavigateToApps: () -> Unit,
    onNavigateToCaCertificateSettings: () -> Unit
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val scope = rememberCoroutineScope()

    var httpsReady by remember { mutableStateOf(AppRulesSettingsStore.isHttpsInspectionReady(context)) }
    var enabled by remember {
        mutableStateOf(
            AppRulesSettingsStore.isHttpInspectionEnabled(context) && httpsReady
        )
    }
    var addressRulesEnabled by remember { mutableStateOf(AppRulesSettingsStore.isAddressRulesEnabled(context)) }
    var filterHttp3 by remember { mutableStateOf(AppRulesSettingsStore.isHttp3InspectionEnabled(context)) }
    var blockEncryptedDns by remember { mutableStateOf(AppRulesSettingsStore.isEncryptedDnsBlockingEnabled(context)) }
    var pendingLinkage by remember { mutableStateOf<DomainRulesLinkageKind?>(null) }
    val scrollState = rememberScrollState()

    fun refreshState() {
        scope.launch {
            val ready = withContext(Dispatchers.IO) {
                AppRulesSettingsStore.checkAndUpdateHttpsInspectionReady(context)
            }
            httpsReady = ready
            enabled = AppRulesSettingsStore.isHttpInspectionEnabled(context) && ready
            addressRulesEnabled = AppRulesSettingsStore.isAddressRulesEnabled(context)
            filterHttp3 = AppRulesSettingsStore.isHttp3InspectionEnabled(context)
            blockEncryptedDns = AppRulesSettingsStore.isEncryptedDnsBlockingEnabled(context)
        }
    }

    LaunchedEffect(Unit) {
        refreshState()
    }

    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                refreshState()
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
        }
    }

    val httpsControlsEnabled = httpsReady
    val protocolControlsEnabled = httpsReady && enabled

    SettingsScaffold(
        title = localizedText("HTTPS 流量检查"),
        onBack = onBack
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .verticalScroll(scrollState),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            SettingsGroupTitle(localizedText("检查范围"))
            val selectedCount = AppRulesSettingsStore.getHttpInspectionAppPackages(context).size
            SettingsSurfaceGroup(
                content = listOf(
                    {
                        SettingsSwitchItem(
                            title = localizedText("启用 HTTPS 检查"),
                            subtitle = localizedText(when {
                                !httpsReady -> "需先安装并验证 CA 根证书"
                                selectedCount == 0 -> "未选择目标应用，仅保留 DNS 过滤"
                                else -> "已选 $selectedCount 个应用，其余直接转发"
                            }),
                            checked = enabled && httpsReady,
                            enabled = httpsControlsEnabled,
                            onCheckedChange = { checked ->
                                if (checked && !AppRulesSettingsStore.isDomainRulesEnabled(context)) {
                                    // Coupling constraint: when domain rules are off, enabling inspection requires confirming both are enabled
                                    pendingLinkage = DomainRulesLinkageKind.ENABLE_BOTH
                                } else {
                                    enabled = checked
                                    AppRulesSettingsStore.setHttpInspectionEnabled(context, checked)
                                    RuntimeDnsSettingsRefresher.refreshAppExclusionsIfRunning(context)
                                }
                            }
                        )
                    },
                    {
                        SettingsNavigationItem(
                            title = localizedText("目标应用"),
                            subtitle = localizedText(
                                if (!httpsReady) "需先安装并验证 CA 根证书"
                                else if (selectedCount == 0) "未选择任何应用"
                                else "已选择 $selectedCount 个应用"
                            ),
                            enabled = httpsControlsEnabled,
                            onClick = onNavigateToApps
                        )
                    },
                    {
                        SettingsNavigationItem(
                            title = localizedText("CA 证书"),
                            subtitle = localizedText(if (httpsReady) {
                                "证书已就绪，可查看或重置"
                            } else {
                                "未安装或未验证，点击配置"
                            }),
                            onClick = onNavigateToCaCertificateSettings
                        )
                    }
                )
            )
            SettingsGroupTitle(localizedText("解密内容过滤"))
            SettingsSurfaceGroup(
                content = listOf(
                    {
                        val addressSubtitle = when {
                            !httpsReady -> "需先安装并验证 CA 根证书"
                            !enabled -> "需先启用 HTTPS 检查"
                            !addressRulesEnabled -> "已暂停 · 解密请求直接放行，不应用 URL 规则及 CNAME 重定向"
                            else -> "开启解密流量下的 URL 屏蔽、放行及 CNAME 重定向"
                        }
                        SettingsSwitchItem(
                            title = localizedText("启用 URL 规则与重定向"),
                            subtitle = localizedText(addressSubtitle),
                            checked = addressRulesEnabled && enabled && httpsReady,
                            enabled = protocolControlsEnabled,
                            onCheckedChange = { checked ->
                                addressRulesEnabled = checked
                                AppRulesSettingsStore.setAddressRulesEnabled(context, checked)
                                RuntimeDnsSettingsRefresher.syncHttpsRequestRulesIfRunning(context)
                            }
                        )
                    }
                )
            )
            SettingsGroupTitle(localizedText("协议与兼容性"))
            SettingsSurfaceGroup(
                content = listOf(
                    {
                        SettingsSwitchItem(
                            title = localizedText("拦截 HTTP/3 (QUIC)"),
                            subtitle = localizedText(when {
                                !httpsReady -> "需先安装并验证 CA 根证书"
                                !enabled -> "需先启用 HTTPS 检查"
                                else -> "阻断 QUIC 促使回退至 TCP 以便解密；若异常请关闭"
                            }),
                            checked = filterHttp3,
                            enabled = protocolControlsEnabled,
                            onCheckedChange = { checked ->
                                filterHttp3 = checked
                                AppRulesSettingsStore.setHttp3InspectionEnabled(context, checked)
                                RuntimeDnsSettingsRefresher.refreshAppExclusionsIfRunning(context)
                            }
                        )
                    },
                    {
                        SettingsSwitchItem(
                            title = localizedText("阻断加密 DNS (DoT)"),
                            subtitle = localizedText(when {
                                !httpsReady -> "需先安装并验证 CA 根证书"
                                !enabled -> "需先启用 HTTPS 检查"
                                else -> "阻断 TCP 853 端口，防止绕过域名规则"
                            }),
                            checked = blockEncryptedDns,
                            enabled = protocolControlsEnabled,
                            onCheckedChange = { checked ->
                                blockEncryptedDns = checked
                                AppRulesSettingsStore.setEncryptedDnsBlockingEnabled(context, checked)
                                RuntimeDnsSettingsRefresher.refreshAppExclusionsIfRunning(context)
                            }
                        )
                    },
                    {
                        SettingsNavigationItem(
                            title = localizedText("请求日志"),
                            subtitle = localizedText("查看解密明细与自动旁路记录"),
                            onClick = onNavigateToRequestLogs
                        )
                    }
                )
            )
        }
    }

    pendingLinkage?.let { kind ->
        DomainRulesInspectionLinkageDialog(
            kind = kind,
            onConfirm = {
                pendingLinkage = null
                // Coupled enable: first enable the domain rule master switch and refresh the runtime snapshot, then enable HTTPS inspection
                AppRulesSettingsStore.setDomainRulesEnabled(context, true)
                enabled = true
                AppRulesSettingsStore.setHttpInspectionEnabled(context, true)
                RuntimeDnsSettingsRefresher.refreshIfRunning(context, "https_inspection_linkage")
                RuntimeDnsSettingsRefresher.refreshAppExclusionsIfRunning(context)
            },
            onDismiss = { pendingLinkage = null }
        )
    }
}
