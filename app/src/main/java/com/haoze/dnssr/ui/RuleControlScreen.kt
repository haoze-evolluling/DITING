package com.haoze.dnssr.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.haoze.dnssr.data.AppDatabase
import com.haoze.dnssr.ui.components.DomainRulesInspectionLinkageDialog
import com.haoze.dnssr.ui.components.DomainRulesLinkageKind
import com.haoze.dnssr.ui.components.SettingsGroupTitle
import com.haoze.dnssr.ui.components.SettingsInfoText
import com.haoze.dnssr.ui.components.SettingsNavigationGroup
import com.haoze.dnssr.ui.components.SettingsNavigationItemData
import com.haoze.dnssr.ui.components.SettingsScaffold
import com.haoze.dnssr.ui.components.SettingsSurfaceGroup
import com.haoze.dnssr.ui.components.SettingsNavigationItem
import com.haoze.dnssr.ui.components.SettingsSwitchItem
import com.haoze.dnssr.vpn.SubscriptionAutoUpdateSettings

@Composable
fun RuleControlScreen(
    onBack: () -> Unit,
    title: String = "规则控制",
    onNavigateToBlockResponseSettings: () -> Unit,
    onNavigateToSubscription: () -> Unit,
    onNavigateToAutoUpdateInterval: () -> Unit,
    onNavigateToMirrorTemplates: () -> Unit,
    onNavigateToHttpInspection: () -> Unit = {},
    onRuntimeDnsSettingsChanged: () -> Unit = {}
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val db = AppDatabase.getInstance(context)

    val subscriptions by db.subscriptionDao().observeAll().collectAsStateWithLifecycle(initialValue = emptyList())
    val mirrorTemplates by db.mirrorTemplateDao().observeAll().collectAsStateWithLifecycle(initialValue = emptyList())

    var domainRulesEnabled by remember { mutableStateOf(AppSettings.isDomainRulesEnabled(context)) }
    var addressRulesEnabled by remember { mutableStateOf(AppSettings.isAddressRulesEnabled(context)) }
    var httpsReady by remember { mutableStateOf(AppSettings.isHttpsInspectionReady(context)) }
    var httpInspectionEnabled by remember { mutableStateOf(AppSettings.isHttpInspectionEnabled(context)) }
    var inspectionAppsCount by remember { mutableIntStateOf(AppSettings.getHttpInspectionAppPackages(context).size) }
    var autoUpdateEnabled by remember { mutableStateOf(SubscriptionAutoUpdateSettings.isEnabled(context)) }
    var intervalHours by remember { mutableIntStateOf(SubscriptionAutoUpdateSettings.intervalHours(context)) }
    var pendingLinkage by remember { mutableStateOf<DomainRulesLinkageKind?>(null) }

    fun refreshState() {
        domainRulesEnabled = AppSettings.isDomainRulesEnabled(context)
        addressRulesEnabled = AppSettings.isAddressRulesEnabled(context)
        httpsReady = AppSettings.isHttpsInspectionReady(context)
        httpInspectionEnabled = AppSettings.isHttpInspectionEnabled(context)
        inspectionAppsCount = AppSettings.getHttpInspectionAppPackages(context).size
        autoUpdateEnabled = SubscriptionAutoUpdateSettings.isEnabled(context)
        intervalHours = SubscriptionAutoUpdateSettings.intervalHours(context)
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

    SettingsScaffold(
        title = localizedText(title),
        onBack = onBack
    ) { innerPadding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            item {
                SettingsInfoText(
                    text = localizedText("统一管理域名过滤、URL 规则及规则覆写的总控开关、拦截策略与在线规则订阅。黑名单、白名单与覆写名单可在功能中心中独立管理。"),
                    modifier = Modifier.padding(top = 8.dp)
                )
            }

            item {
                SettingsGroupTitle(localizedText("过滤与覆写控制"))
            }
            item {
                SettingsSurfaceGroup(
                    content = listOf(
                        {
                            SettingsSwitchItem(
                                title = localizedText("启用域名规则"),
                                subtitle = localizedText(
                                    if (domainRulesEnabled) "开启 DNS 阶段域名屏蔽、白名单放行及 IPv4/IPv6 覆写"
                                    else "已禁用 DNS 域名过滤，查询将直接放行"
                                ),
                                checked = domainRulesEnabled,
                                onCheckedChange = { checked ->
                                    if (!checked && httpInspectionEnabled) {
                                        // 联动约束：HTTPS 检查启用期间无法单独关闭域名规则
                                        pendingLinkage = DomainRulesLinkageKind.DISABLE_BOTH
                                    } else {
                                        domainRulesEnabled = checked
                                        AppSettings.setDomainRulesEnabled(context, checked)
                                        RuntimeDnsSettingsRefresher.refreshIfRunning(context, "domain_rules_switch")
                                        onRuntimeDnsSettingsChanged()
                                    }
                                }
                            )
                        },
                        {
                            val isAddressOperational = AppSettings.isAddressRulesFullyOperational(context)
                            val urlRuleSubtitle = when {
                                !httpsReady -> "未就绪 · 需先安装并验证 CA 根证书"
                                !httpInspectionEnabled -> "未就绪 · 需在 HTTPS 流量检查中开启"
                                inspectionAppsCount == 0 -> "未就绪 · 需在 HTTPS 流量检查中选择目标应用"
                                !addressRulesEnabled -> "已暂停 · 未启用解密 URL 过滤与重定向"
                                else -> "运行中 · 解密流量匹配 URL 屏蔽、放行及重定向"
                            }
                            SettingsNavigationItem(
                                title = localizedText("URL 规则与内容过滤"),
                                subtitle = localizedText(urlRuleSubtitle),
                                value = localizedText(if (isAddressOperational) "运行中" else "未就绪"),
                                onClick = onNavigateToHttpInspection
                            )
                        }
                    )
                )
            }

            item {
                SettingsGroupTitle(localizedText("拦截策略"))
            }
            item {
                val dynamicConfig = AppSettings.getDynamicBlockResponseConfig(context)
                SettingsNavigationGroup(
                    items = listOf(
                        SettingsNavigationItemData(
                            title = localizedText("拦截响应"),
                            subtitle = localizedText(if (dynamicConfig.enabled) {
                                "动态策略：先 NODATA，高频请求后 NXDOMAIN"
                            } else {
                                localizedText("当前：${localizedText(AppSettings.getBlockResponseMode(context).displayName)}")
                            }),
                            onClick = onNavigateToBlockResponseSettings
                        )
                    )
                )
            }

            item {
                SettingsGroupTitle(localizedText("订阅与更新"))
            }
            item {
                val autoUpdateSubtitle = if (autoUpdateEnabled) {
                    "已开启 · 每 $intervalHours 小时自动更新"
                } else {
                    "已关闭自动更新"
                }

                SettingsNavigationGroup(
                    items = listOf(
                        SettingsNavigationItemData(
                            title = localizedText("规则订阅"),
                            subtitle = localizedText("管理域名规则与 IPv4/IPv6 覆写订阅源及分组"),
                            value = localizedText("${subscriptions.size} 个"),
                            onClick = onNavigateToSubscription
                        ),
                        SettingsNavigationItemData(
                            title = localizedText("自动更新设置"),
                            subtitle = localizedText(autoUpdateSubtitle),
                            onClick = onNavigateToAutoUpdateInterval
                        ),
                        SettingsNavigationItemData(
                            title = localizedText("镜像站模板"),
                            subtitle = localizedText("维护订阅下载镜像，可在添加订阅时直接选择"),
                            value = localizedText("${mirrorTemplates.size} 个"),
                            onClick = onNavigateToMirrorTemplates
                        )
                    )
                )
            }
        }
    }

    pendingLinkage?.let { kind ->
        DomainRulesInspectionLinkageDialog(
            kind = kind,
            onConfirm = {
                pendingLinkage = null
                // 联动关闭：HTTPS 检查与域名规则一并关闭，并同步两组运行时刷新
                AppSettings.setHttpInspectionEnabled(context, false)
                httpInspectionEnabled = false
                domainRulesEnabled = false
                AppSettings.setDomainRulesEnabled(context, false)
                RuntimeDnsSettingsRefresher.refreshAppExclusionsIfRunning(context)
                RuntimeDnsSettingsRefresher.refreshIfRunning(context, "domain_rules_switch")
                onRuntimeDnsSettingsChanged()
            },
            onDismiss = { pendingLinkage = null }
        )
    }
}
