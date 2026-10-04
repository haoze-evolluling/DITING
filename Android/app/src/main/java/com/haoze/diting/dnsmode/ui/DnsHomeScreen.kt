package com.haoze.diting.dnsmode.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
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
import com.haoze.diting.util.formatDuration

@Composable
fun DnsHomeScreen(
    status: DnsServiceStatus,
    errorReason: String?,
    activeUpstream: DnsUpstreamServer,
    stats: DnsModeStats,
    onToggleService: () -> Unit,
    onNavigateToServers: () -> Unit,
    modifier: Modifier = Modifier,
    contentBottomPadding: Dp = 108.dp
) {
    val isBusy = status == DnsServiceStatus.STARTING || status == DnsServiceStatus.STOPPING
    val statusText = when (status) {
        DnsServiceStatus.RUNNING -> localizedText("DNS 服务器模式运行中")
        DnsServiceStatus.STARTING -> localizedText("正在启动服务...")
        DnsServiceStatus.STOPPING -> localizedText("正在停止服务...")
        DnsServiceStatus.ERROR -> localizedText("服务异常")
        DnsServiceStatus.STOPPED -> localizedText("DNS 服务器模式已停止")
    }
    val latencyText = if (status.isRunning) "${stats.latencyMs} ms" else "--"
    val uptimeText = if (status.isRunning) formatDuration(stats.uptimeSeconds) else "--"

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
                    onToggle = onToggleService,
                    busyLabel = "启动中",
                    runningLabel = "停止",
                    stoppedLabel = "开启"
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

                if (status == DnsServiceStatus.ERROR && errorReason != null) {
                    Text(
                        text = localizedText(errorReason),
                        style = MaterialTheme.typography.bodySmall,
                        textAlign = TextAlign.Center,
                        color = MaterialTheme.colorScheme.error,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 4.dp)
                    )
                }
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
                        SettingsItem(title = localizedText("总查询量")) {
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
                        SettingsItem(title = localizedText("已拦截")) {
                            Text(
                                text = stats.blockedCount.toString(),
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
                    },
                    {
                        SettingsItem(title = localizedText("运行时长")) {
                            Text(
                                text = uptimeText,
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                )
            )
        }

        item {
            SettingsInfoText(
                text = localizedText("DNS 服务器模式在本机提供局域网 DNS 解析服务，将其他设备的 DNS 指向本机即可使用；本机应用的查询不会自动经过该服务。")
            )
        }
    }
}

