package com.haoze.diting.express.ui

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
import com.haoze.diting.data.RuleDataset
import com.haoze.diting.data.RuleDatabases
import com.haoze.diting.ui.RuntimeDnsSettingsRefresher
import com.haoze.diting.ui.components.SettingsGroupTitle
import com.haoze.diting.ui.components.SettingsInfoText
import com.haoze.diting.ui.components.SettingsNavigationGroup
import com.haoze.diting.ui.components.SettingsNavigationItemData
import com.haoze.diting.ui.components.SettingsScaffold
import com.haoze.diting.ui.components.SettingsSurfaceGroup
import com.haoze.diting.ui.components.SettingsSwitchItem
import com.haoze.diting.ui.localizedText
import com.haoze.diting.ui.settings.RuleSettingsAccess

/**
 * Dedicated Rule Control Screen for Express Mode.
 *
 * Physically omits full-tunnel capabilities:
 * - URL request rules and HTTPS inspection navigation (URL 规则与内容过滤)
 * - HTTPS inspection linkage dialog when toggling master rule switch
 * - IPv4/IPv6 rewrite list mentions
 */
@Composable
fun ExpressRuleControlScreen(
    onBack: () -> Unit,
    title: String = "规则控制",
    onNavigateToBlockResponseSettings: () -> Unit,
    onNavigateToSubscription: () -> Unit,
    onNavigateToAutoUpdateInterval: () -> Unit,
    onNavigateToMirrorTemplates: () -> Unit,
    dataset: RuleDataset = RuleDataset.NORMAL,
    onRuntimeDnsSettingsChanged: () -> Unit = {}
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val settings = RuleSettingsAccess(dataset)
    val dataSources = RuleDatabases.forDataset(context, dataset)

    val subscriptions by dataSources.subscriptionDao().observeAll().collectAsStateWithLifecycle(initialValue = emptyList())
    val mirrorTemplates by dataSources.mirrorTemplateDao().observeAll().collectAsStateWithLifecycle(initialValue = emptyList())

    var domainRulesEnabled by remember { mutableStateOf(settings.isMasterEnabled(context)) }
    var autoUpdateEnabled by remember { mutableStateOf(settings.autoUpdateEnabled(context)) }
    var intervalHours by remember { mutableIntStateOf(settings.autoUpdateIntervalHours(context)) }

    fun refreshState() {
        domainRulesEnabled = settings.isMasterEnabled(context)
        autoUpdateEnabled = settings.autoUpdateEnabled(context)
        intervalHours = settings.autoUpdateIntervalHours(context)
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
                    text = localizedText("统一管理极速模式域名过滤的总控开关、拦截策略与在线规则订阅。黑名单与白名单可在功能中心中独立管理。"),
                    modifier = Modifier.padding(top = 8.dp)
                )
            }

            item {
                SettingsGroupTitle(localizedText("过滤控制"))
            }
            item {
                SettingsSurfaceGroup(
                    content = listOf {
                        SettingsSwitchItem(
                            title = localizedText("启用域名规则"),
                            subtitle = localizedText(
                                if (domainRulesEnabled) "开启 DNS 阶段域名屏蔽与白名单放行"
                                else "已禁用 DNS 域名过滤，查询将直接放行"
                            ),
                            checked = domainRulesEnabled,
                            onCheckedChange = { checked ->
                                domainRulesEnabled = checked
                                settings.setMasterEnabled(context, checked)
                                RuntimeDnsSettingsRefresher.refreshIfRunning(context, "domain_rules_switch", dataset)
                                onRuntimeDnsSettingsChanged()
                            }
                        )
                    }
                )
            }

            item {
                SettingsGroupTitle(localizedText("拦截策略"))
            }
            item {
                val dynamicConfig = settings.dynamicBlockResponseConfig(context)
                SettingsNavigationGroup(
                    items = listOf(
                        SettingsNavigationItemData(
                            title = localizedText("拦截响应"),
                            subtitle = localizedText(if (dynamicConfig.enabled) {
                                "动态策略：先 NODATA，高频请求后 NXDOMAIN"
                            } else {
                                localizedText("当前：${localizedText(settings.blockResponseMode(context).displayName)}")
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
                            subtitle = localizedText("管理域名规则订阅源及分组"),
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
}
