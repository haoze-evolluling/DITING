package com.haoze.dnssr.ui

import android.widget.Toast
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import com.haoze.dnssr.ui.components.AppAlertDialog as AlertDialog
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
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
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.haoze.dnssr.ui.components.DomainRulesInspectionLinkageDialog
import com.haoze.dnssr.ui.components.DomainRulesLinkageKind
import com.haoze.dnssr.ui.components.SettingsCornerShape
import com.haoze.dnssr.ui.components.SettingsGroupTitle
import com.haoze.dnssr.ui.components.SettingsInfoText
import com.haoze.dnssr.ui.components.SettingsNavigationGroup
import com.haoze.dnssr.ui.components.SettingsNavigationItemData
import com.haoze.dnssr.ui.components.SettingsScaffold
import com.haoze.dnssr.ui.components.SettingsSurfaceGroup
import com.haoze.dnssr.ui.components.SettingsSwitchItem
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import com.haoze.dnssr.data.entity.RewriteTargetType
import com.haoze.dnssr.data.entity.RuleScope

@Composable
fun RuleManagementScreen(
    onBack: () -> Unit,
    ruleScope: RuleScope = RuleScope.DNS,
    title: String = "域名规则",
    onNavigateToRewriteRuleList: () -> Unit,
    onNavigateToSubscription: () -> Unit,
    onNavigateToMirrorTemplates: () -> Unit,
    onNavigateToAutoUpdateInterval: () -> Unit,
    onNavigateToBlockResponseSettings: () -> Unit,
    onRuntimeDnsSettingsChanged: () -> Unit = {},
    addressOnly: Boolean = false,
    viewModel: RuleManagementViewModel = viewModel()
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val lifecycleOwner = LocalLifecycleOwner.current
    val rewriteRuleCount by viewModel.rewriteRuleCount.collectAsStateWithLifecycle()
    val mirrorTemplates by viewModel.mirrorTemplates.collectAsStateWithLifecycle(initialValue = emptyList())
    var domainRulesEnabled by remember { mutableStateOf(AppSettings.isDomainRulesEnabled(context)) }
    var addressRulesEnabled by remember { mutableStateOf(AppSettings.isAddressRulesEnabled(context)) }
    var httpsReady by remember { mutableStateOf(AppSettings.isHttpsInspectionReady(context)) }
    var httpInspectionEnabled by remember { mutableStateOf(AppSettings.isHttpInspectionEnabled(context)) }
    var inspectionAppsCount by remember { mutableIntStateOf(AppSettings.getHttpInspectionAppPackages(context).size) }

    var showClearAllRulesDialog by remember { mutableStateOf(false) }
    var pendingLinkage by remember { mutableStateOf<DomainRulesLinkageKind?>(null) }

    NavigationSettledEffect(ruleScope to addressOnly) {
        viewModel.activate(ruleScope, addressOnly)
    }

    fun refreshState() {
        domainRulesEnabled = AppSettings.isDomainRulesEnabled(context)
        addressRulesEnabled = AppSettings.isAddressRulesEnabled(context)
        httpsReady = AppSettings.isHttpsInspectionReady(context)
        httpInspectionEnabled = AppSettings.isHttpInspectionEnabled(context)
        inspectionAppsCount = AppSettings.getHttpInspectionAppPackages(context).size
        viewModel.loadRuleCount()
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
                    text = localizedText(
                        if (addressOnly && !addressRulesEnabled) {
                            "地址规则已关闭，所有地址规则功能均被禁用。屏蔽、放行与覆写请前往功能中心「黑名单」、「白名单」与「覆写名单」。"
                        } else if (addressOnly) {
                            "仅在 HTTPS 流量检查可解密的 HTTP(S) 请求中生效。屏蔽、放行与覆写请前往功能中心「黑名单」、「白名单」与「覆写名单」。"
                        } else if (!domainRulesEnabled) {
                            "域名规则已关闭，所有域名功能均被禁用。屏蔽、放行与覆写请前往功能中心「黑名单」、「白名单」与「覆写名单」。"
                        } else {
                            "统一管理拦截响应策略与规则订阅，DNS 与 HTTPS 检查共用。屏蔽、放行与覆写请前往功能中心「黑名单」、「白名单」与「覆写名单」。"
                        }
                    ),
                    modifier = Modifier.padding(top = 8.dp)
                )
            }

            if (addressOnly) item {
                SettingsSurfaceGroup(
                    content = listOf {
                        val addressSubtitle = when {
                            !addressRulesEnabled -> "已禁用所有地址规则功能，HTTP(S) 请求将直接放行"
                            !httpsReady -> "已开启（未就绪 · 需先安装并验证 CA 根证书）"
                            !httpInspectionEnabled -> "已开启（未就绪 · 需在 HTTPS 流量检查中开启检查）"
                            inspectionAppsCount == 0 -> "已开启（未就绪 · 需在 HTTPS 流量检查中选择目标应用）"
                            else -> "开启 HTTPS 流量解密下的 URL 屏蔽、放行及 CNAME 覆写"
                        }
                        SettingsSwitchItem(
                            title = localizedText("启用地址规则"),
                            subtitle = localizedText(addressSubtitle),
                            checked = addressRulesEnabled,
                            onCheckedChange = { checked ->
                                addressRulesEnabled = checked
                                AppSettings.setAddressRulesEnabled(context, checked)
                                RuntimeDnsSettingsRefresher.syncHttpsRequestRulesIfRunning(context)
                                onRuntimeDnsSettingsChanged()
                            }
                        )
                    }
                )
            }

            if (!addressOnly) item {
                SettingsSurfaceGroup(
                    content = listOf {
                        SettingsSwitchItem(
                            title = localizedText("启用域名规则"),
                            subtitle = localizedText(
                                if (domainRulesEnabled) "开启域名屏蔽及 IPv4/IPv6 覆写功能"
                                else "已禁用所有域名规则功能，查询将直接放行"
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
                    }
                )
            }

            if (!addressOnly) item {
                SettingsGroupTitle(localizedText("拦截策略"))
            }
            if (!addressOnly) item {
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

            if (!addressOnly) item {
                SettingsGroupTitle(localizedText("订阅与更新"))
            }
            if (!addressOnly) item {
                SettingsNavigationGroup(
                    items = listOf(
                        SettingsNavigationItemData(
                            title = localizedText("规则订阅"),
                            subtitle = localizedText("管理域名规则与 IPv4/IPv6 覆写订阅"),
                            onClick = onNavigateToSubscription
                        ),
                        SettingsNavigationItemData(
                            title = localizedText("自动更新设置"),
                            subtitle = localizedText("设置规则订阅的自动更新开关和频率"),
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

            if (!addressOnly) item {
                SettingsGroupTitle(localizedText("维护工具"))
            }
            if (!addressOnly) item {
                SettingsNavigationGroup(
                    items = listOf(
                        SettingsNavigationItemData(
                            title = localizedText("清理全部域名规则"),
                            subtitle = localizedText("清除全部域名屏蔽、放行、覆写规则及对应订阅，不影响地址规则"),
                            onClick = { showClearAllRulesDialog = true }
                        )
                    )
                )
            }
            if (addressOnly) item {
                SettingsGroupTitle(localizedText("维护工具"))
                SettingsNavigationGroup(
                    items = listOf(
                        SettingsNavigationItemData(
                            title = localizedText("清理全部地址规则"),
                            subtitle = localizedText("清除全部 URL 屏蔽和放行规则，不影响域名规则"),
                            onClick = { showClearAllRulesDialog = true }
                        )
                    )
                )
            }
        }
    }

    if (showClearAllRulesDialog) {
        ConfirmDialog(
            title = localizedText(if (addressOnly) "删除全部地址规则" else "删除全部域名规则"),
            text = localizedText(if (addressOnly) "确定要删除全部地址规则吗？URL 屏蔽和放行规则都会被移除，域名规则不受影响。" else "确定要删除全部域名规则吗？域名屏蔽、白名单、IPv4/IPv6 覆写规则及对应订阅都会被移除，地址规则不受影响。"),
            onConfirm = {
                showClearAllRulesDialog = false
                scope.launch(Dispatchers.IO) {
                    if (addressOnly) clearAllAddressRules(context) else clearAllDomainRules(context)
                    withContext(Dispatchers.Main) {
                        viewModel.loadRuleCount()
                        onRuntimeDnsSettingsChanged()
                        context.showToast(if (addressOnly) "已删除全部地址规则" else "已删除全部域名规则", Toast.LENGTH_SHORT)
                    }
                }
            },
            onDismiss = { showClearAllRulesDialog = false }
        )
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



