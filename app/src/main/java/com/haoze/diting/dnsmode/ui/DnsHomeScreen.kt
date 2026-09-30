package com.haoze.diting.dnsmode.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.SwapHoriz
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material.icons.outlined.Dns
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.haoze.diting.dnsmode.model.DnsModeStats
import com.haoze.diting.dnsmode.model.DnsServiceStatus
import com.haoze.diting.dnsmode.model.DnsUpstreamServer
import com.haoze.diting.ui.PowerToggleButton
import com.haoze.diting.ui.components.SettingsGroupTitle
import com.haoze.diting.ui.components.SettingsInfoText
import com.haoze.diting.ui.components.SettingsItem
import com.haoze.diting.ui.components.SettingsNavigationItem
import com.haoze.diting.ui.components.SettingsSurfaceGroup
import com.haoze.diting.ui.localizedText

@Composable
fun DnsHomeScreen(
    status: DnsServiceStatus,
    activeUpstream: DnsUpstreamServer,
    stats: DnsModeStats,
    onToggleService: () -> Unit,
    onNavigateToServers: () -> Unit,
    onSwitchToNormalMode: () -> Unit,
    onSelectMode: () -> Unit,
    modifier: Modifier = Modifier,
    contentBottomPadding: Dp = 108.dp
) {
    val isBusy = status == DnsServiceStatus.STARTING || status == DnsServiceStatus.STOPPING
    val statusText = when (status) {
        DnsServiceStatus.RUNNING -> localizedText("DNS 代理运行中")
        DnsServiceStatus.STARTING -> localizedText("正在启动服务...")
        DnsServiceStatus.STOPPING -> localizedText("正在停止服务...")
        DnsServiceStatus.ERROR -> localizedText("服务异常")
        DnsServiceStatus.STOPPED -> localizedText("DNS 代理已停止")
    }
    val latencyText = if (status.isRunning) "${stats.latencyMs} ms" else "--"

    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(bottom = contentBottomPadding),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 16.dp, bottom = 4.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                PowerToggleButton(
                    isRunning = status.isRunning,
                    isBusy = isBusy,
                    enabled = !isBusy,
                    onToggle = onToggleService
                )

                Text(
                    text = statusText,
                    style = MaterialTheme.typography.bodyLarge,
                    textAlign = TextAlign.Center,
                    color = MaterialTheme.colorScheme.onSurface,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 12.dp)
                )
            }
        }

        item {
            SettingsGroupTitle(localizedText("当前上游"))
        }

        item {
            SettingsSurfaceGroup(
                content = listOf {
                    SettingsNavigationItem(
                        title = localizedText(activeUpstream.name),
                        subtitle = activeUpstream.endpointLabel(),
                        leadingIcon = Icons.Outlined.Dns,
                        onClick = onNavigateToServers
                    )
                }
            )
        }

        item {
            SettingsGroupTitle(localizedText("服务状态"))
        }

        item {
            SettingsSurfaceGroup(
                content = listOf(
                    {
                        SettingsItem(title = localizedText("总解析量")) {
                            Text(
                                text = stats.queryCount.toString(),
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    },
                    {
                        SettingsItem(title = localizedText("缓存命中")) {
                            Text(
                                text = stats.cacheHitCount.toString(),
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    },
                    {
                        SettingsItem(title = localizedText("平均时延")) {
                            Text(
                                text = latencyText,
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                )
            )
        }

        item {
            SettingsGroupTitle(localizedText("模式管理"))
        }

        item {
            SettingsSurfaceGroup(
                content = listOf(
                    {
                        SettingsNavigationItem(
                            title = localizedText("切换回普通模式"),
                            subtitle = localizedText("启用完整分流、黑白名单与应用网络管控"),
                            leadingIcon = Icons.Default.SwapHoriz,
                            onClick = onSwitchToNormalMode
                        )
                    },
                    {
                        SettingsNavigationItem(
                            title = localizedText("重新选择模式"),
                            subtitle = localizedText("浏览所有工作模式详情并重新选择"),
                            leadingIcon = Icons.Default.Tune,
                            onClick = onSelectMode
                        )
                    }
                )
            )
        }

        item {
            SettingsInfoText(
                text = localizedText("当前处于纯 DNS 模式，与普通模式（完整网络分流）在代码与运行时完全解耦。本模式专注于轻量、低功耗的上游 DNS 解析与域名防护。")
            )
        }
    }
}

