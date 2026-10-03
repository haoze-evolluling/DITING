package com.haoze.diting.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.haoze.diting.ui.components.NetworkToolInfoRow
import com.haoze.diting.ui.components.NetworkToolResultHeader
import com.haoze.diting.ui.components.NetworkToolRunButton
import com.haoze.diting.ui.components.NetworkToolSectionLabel
import com.haoze.diting.ui.components.NetworkToolSegmentedRow
import com.haoze.diting.ui.components.NetworkToolStat
import com.haoze.diting.ui.components.NetworkToolStatBand
import com.haoze.diting.ui.components.SettingsGroupTitle
import com.haoze.diting.ui.components.SettingsInfoText
import com.haoze.diting.ui.components.SettingsSurfaceGroup
import com.haoze.diting.ui.components.SettingsSwitchItem
import com.haoze.diting.ui.components.formatLossPercent
import com.haoze.diting.ui.components.formatMsValue
import com.haoze.diting.vpn.NetworkPingTool

/**
 * Ping test section: target and count configuration -> start button ->
 * stats band and per-packet details.
 */
@Composable
internal fun PingSection(
    viewModel: NetworkToolsViewModel,
    contentBottomPadding: androidx.compose.ui.unit.Dp = 0.dp
) {
    val pingTarget by viewModel.pingTarget.collectAsStateWithLifecycle()
    val pingCount by viewModel.pingCount.collectAsStateWithLifecycle()
    val pingViaTunnel by viewModel.pingViaTunnel.collectAsStateWithLifecycle()
    val isPinging by viewModel.isPinging.collectAsStateWithLifecycle()
    val pingResult by viewModel.pingResult.collectAsStateWithLifecycle()

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = toolPageContentPadding(contentBottomPadding),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            SettingsSurfaceGroup(
                content = listOf(
                    {
                        ToolTargetField(
                            value = pingTarget,
                            onValueChange = viewModel::setPingTarget,
                            label = "输入 IP 或域名",
                            onDone = viewModel::runPing
                        )
                    },
                    {
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 16.dp, vertical = 12.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            NetworkToolSectionLabel("Ping 次数")
                            val countOptions = listOf("4 次", "10 次")
                            NetworkToolSegmentedRow(
                                options = countOptions,
                                selectedIndex = countOptions.indexOf("$pingCount 次").coerceAtLeast(0),
                                onSelect = { index -> viewModel.setPingCount(countOptions[index].substringBefore(" ").toInt()) }
                            )
                        }
                    },
                    {
                        SettingsSwitchItem(
                            title = localizedText("通过 Go 隧道解析"),
                            subtitle = localizedText("域名经运行中的 Go 隧道解析（应用覆写与过滤规则），探测仍走物理网络"),
                            checked = pingViaTunnel,
                            onCheckedChange = viewModel::setPingViaTunnel
                        )
                    }
                )
            )
        }
        item {
            NetworkToolRunButton(
                running = isPinging,
                runningLabel = "Ping 中...",
                idleLabel = "开始 Ping",
                onClick = viewModel::runPing,
                modifier = Modifier.padding(horizontal = 16.dp)
            )
        }
        val currentPingResult = pingResult
        if (currentPingResult != null) {
            item { SettingsGroupTitle("测试结果") }
            item {
                SettingsSurfaceGroup(
                    content = listOf {
                        PingResultContent(currentPingResult)
                    }
                )
            }
        }
        item {
            SettingsInfoText("结果只反映执行时刻的网络状态；部分目标会限制 ICMP 响应或 DNS 查询。")
        }
    }
}

@Composable
private fun PingResultContent(result: NetworkPingTool.Summary) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        NetworkToolResultHeader(
            success = result.success,
            title = if (result.success) "Ping 完成" else "Ping 失败",
            subtitle = localizedText(
                "发送 ${result.transmitted} · 接收 ${result.received} · 丢包率 ${formatLossPercent(result.lossPercent)}"
            )
        )
        if (result.avgMs != null) {
            NetworkToolStatBand(
                stats = listOf(
                    NetworkToolStat("最小", formatMsValue(result.minMs ?: result.avgMs)),
                    NetworkToolStat("平均", formatMsValue(result.avgMs)),
                    NetworkToolStat("最大", formatMsValue(result.maxMs ?: result.avgMs)),
                    NetworkToolStat("抖动", formatMsValue(result.jitterMs))
                )
            )
        }
        result.resolvedAddress?.let { address ->
            val target = listOfNotNull(address, result.addressFamily).joinToString(" · ")
            NetworkToolInfoRow(label = "目标地址", value = target)
        }
        result.message?.let { message ->
            Text(
                text = localizedText(message),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        if (result.replies.isNotEmpty()) {
            NetworkToolSectionLabel("逐包明细")
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                result.replies.forEach { reply ->
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = "#${reply.sequence}",
                            style = MaterialTheme.typography.labelMedium,
                            fontFamily = FontFamily.Monospace,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        if (reply.elapsedMs != null) {
                            Text(
                                text = buildString {
                                    append(formatMsValue(reply.elapsedMs))
                                    reply.ttl?.let { ttl -> append(" · TTL $ttl") }
                                },
                                style = MaterialTheme.typography.bodyMedium,
                                fontFamily = FontFamily.Monospace,
                                color = MaterialTheme.colorScheme.onSurface,
                                textAlign = TextAlign.End,
                                modifier = Modifier.weight(1f)
                            )
                        } else {
                            Text(
                                text = localizedText(reply.error ?: "超时或无响应"),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.error,
                                textAlign = TextAlign.End,
                                modifier = Modifier.weight(1f)
                            )
                        }
                    }
                }
            }
        }
    }
}
