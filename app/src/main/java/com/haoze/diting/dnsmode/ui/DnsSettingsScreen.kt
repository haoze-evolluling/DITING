package com.haoze.diting.dnsmode.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.BatterySaver
import androidx.compose.material.icons.filled.Block
import androidx.compose.material.icons.filled.DeleteSweep
import androidx.compose.material.icons.filled.Dns
import androidx.compose.material.icons.filled.Security
import androidx.compose.material.icons.filled.SwapHoriz
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material.icons.filled.VerifiedUser
import androidx.compose.material.icons.outlined.Lan
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.haoze.diting.SettingsRouteActivity
import com.haoze.diting.data.RuleDataset
import com.haoze.diting.dnsmode.model.DnsModeConfig
import com.haoze.diting.ui.Routes
import com.haoze.diting.ui.components.SettingsGroupTitle
import com.haoze.diting.ui.components.SettingsItem
import com.haoze.diting.ui.components.SettingsNavigationItem
import com.haoze.diting.ui.components.SettingsSurfaceGroup
import com.haoze.diting.ui.components.SettingsSwitchItem
import com.haoze.diting.ui.localizedText

@Composable
fun DnsSettingsScreen(
    config: DnsModeConfig,
    batteryOptimizationIgnored: Boolean,
    onRequestIgnoreBatteryOptimization: () -> Unit,
    onUpdateConfig: (DnsModeConfig) -> Unit,
    onResetStats: () -> Unit,
    onEditListenPort: () -> Unit,
    onSwitchToNormalMode: () -> Unit,
    onSelectMode: () -> Unit,
    modifier: Modifier = Modifier,
    contentBottomPadding: Dp = 108.dp
) {
    val context = LocalContext.current

    fun openRuleRoute(route: String) {
        context.startActivity(
            SettingsRouteActivity.createIntent(context, route, dataset = RuleDataset.DNS_MODE)
        )
    }

    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(bottom = contentBottomPadding),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            SettingsGroupTitle(localizedText("代理与解析设置"))
        }

        item {
            SettingsSurfaceGroup(
                content = listOf(
                    {
                        SettingsSwitchItem(
                            title = localizedText("DNS 缓存"),
                            subtitle = localizedText("启用本地 DNS 记录缓存，加速重复域名查询"),
                            checked = config.cacheEnabled,
                            onCheckedChange = { onUpdateConfig(config.copy(cacheEnabled = it)) }
                        )
                    },
                    {
                        SettingsNavigationItem(
                            title = localizedText("恶意域名过滤"),
                            subtitle = localizedText(
                                if (config.adBlockEnabled) "已开启 · 命中规则按拦截策略返回"
                                else "已关闭 · 使用独立的过滤规则库"
                            ),
                            leadingIcon = Icons.Default.Security,
                            onClick = { openRuleRoute(Routes.RULE_CONTROL) }
                        )
                    },
                    {
                        SettingsItem(
                            title = localizedText("本地监听端口"),
                            subtitle = localizedText("DNS 服务在本机监听的端口，默认 1053"),
                            leadingIcon = Icons.Outlined.Lan,
                            onClick = onEditListenPort
                        ) {
                            Text(
                                text = "${config.localListenPort}",
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                )
            )
        }

        item {
            SettingsGroupTitle(localizedText("规则管理"))
        }

        item {
            SettingsSurfaceGroup(
                content = listOf(
                    {
                        SettingsNavigationItem(
                            title = localizedText("黑名单"),
                            subtitle = localizedText("管理域名屏蔽规则，独立规则库"),
                            leadingIcon = Icons.Default.Block,
                            onClick = { openRuleRoute(Routes.BLACKLIST_MANAGEMENT) }
                        )
                    },
                    {
                        SettingsNavigationItem(
                            title = localizedText("白名单"),
                            subtitle = localizedText("管理域名放行规则，独立规则库"),
                            leadingIcon = Icons.Default.VerifiedUser,
                            onClick = { openRuleRoute(Routes.WHITELIST_MANAGEMENT) }
                        )
                    },
                    {
                        SettingsNavigationItem(
                            title = localizedText("Hosts 覆写"),
                            subtitle = localizedText("将指定域名解析到配置的 IP 或 CNAME"),
                            leadingIcon = Icons.Default.Dns,
                            onClick = { openRuleRoute(Routes.REWRITELIST_MANAGEMENT) }
                        )
                    }
                )
            )
        }

        item {
            SettingsGroupTitle(localizedText("数据与重置"))
        }

        item {
            SettingsSurfaceGroup(
                content = listOf {
                    SettingsNavigationItem(
                        title = localizedText("重置运行统计"),
                        subtitle = localizedText("清空本次运行的统计数据"),
                        leadingIcon = Icons.Default.DeleteSweep,
                        onClick = onResetStats
                    )
                }
            )
        }

        item {
            SettingsGroupTitle(localizedText("后台稳定性"))
        }

        item {
            SettingsSurfaceGroup(
                content = listOf {
                    SettingsNavigationItem(
                        title = localizedText("忽略电池优化"),
                        subtitle = if (batteryOptimizationIgnored) {
                            localizedText("已忽略电池优化")
                        } else {
                            localizedText("保持 DNS 服务在后台稳定运行")
                        },
                        leadingIcon = Icons.Default.BatterySaver,
                        enabled = !batteryOptimizationIgnored,
                        onClick = onRequestIgnoreBatteryOptimization
                    )
                }
            )
        }

        item {
            SettingsGroupTitle(localizedText("运行模式"))
        }

        item {
            SettingsSurfaceGroup(
                content = listOf(
                    {
                        SettingsNavigationItem(
                            title = localizedText("切换为普通模式"),
                            subtitle = localizedText("启用完整分流、黑白名单与应用网络管控"),
                            leadingIcon = Icons.Default.SwapHoriz,
                            onClick = onSwitchToNormalMode
                        )
                    },
                    {
                        SettingsNavigationItem(
                            title = localizedText("重新选择工作模式"),
                            subtitle = localizedText("浏览所有工作模式详情并重新选择"),
                            leadingIcon = Icons.Default.Tune,
                            onClick = onSelectMode
                        )
                    }
                )
            )
        }
    }
}

