package com.haoze.diting.dnsmode.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DeleteSweep
import androidx.compose.material.icons.filled.SwapHoriz
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material.icons.outlined.Lan
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.haoze.diting.dnsmode.model.DnsModeConfig
import com.haoze.diting.ui.components.SettingsGroupTitle
import com.haoze.diting.ui.components.SettingsItem
import com.haoze.diting.ui.components.SettingsNavigationItem
import com.haoze.diting.ui.components.SettingsSurfaceGroup
import com.haoze.diting.ui.components.SettingsSwitchItem
import com.haoze.diting.ui.localizedText

@Composable
fun DnsSettingsScreen(
    config: DnsModeConfig,
    onUpdateConfig: (DnsModeConfig) -> Unit,
    onResetStats: () -> Unit,
    onSwitchToNormalMode: () -> Unit,
    onSelectMode: () -> Unit,
    modifier: Modifier = Modifier,
    contentBottomPadding: Dp = 108.dp
) {
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
                        SettingsSwitchItem(
                            title = localizedText("恶意域名过滤"),
                            subtitle = localizedText("与普通模式共用屏蔽规则，命中后按拦截策略返回"),
                            checked = config.adBlockEnabled,
                            onCheckedChange = { onUpdateConfig(config.copy(adBlockEnabled = it)) }
                        )
                    },
                    {
                        SettingsItem(
                            title = localizedText("本地监听端口"),
                            leadingIcon = Icons.Outlined.Lan
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
            SettingsGroupTitle(localizedText("数据与重置"))
        }

        item {
            SettingsSurfaceGroup(
                content = listOf {
                    SettingsNavigationItem(
                        title = localizedText("重置运行统计"),
                        subtitle = localizedText("清空当前会话的全部统计数据"),
                        leadingIcon = Icons.Default.DeleteSweep,
                        onClick = onResetStats
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

