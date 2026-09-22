package com.haoze.diting.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.haoze.diting.ui.components.NetworkToolInfoRow
import com.haoze.diting.ui.components.NetworkToolResultHeader
import com.haoze.diting.ui.components.NetworkToolRunButton
import com.haoze.diting.ui.components.NetworkToolSectionLabel
import com.haoze.diting.ui.components.NetworkToolSegmentedRow
import com.haoze.diting.ui.components.SettingsGroupTitle
import com.haoze.diting.ui.components.SettingsInfoText
import com.haoze.diting.ui.components.SettingsSurfaceGroup
import com.haoze.diting.ui.components.SettingsSwitchItem
import com.haoze.diting.ui.components.formatMsValue
import com.haoze.diting.vpn.NetworkTraceRouteTool

/**
 * Traceroute section: target and hop count configuration -> start button ->
 * per-hop timeline.
 */
@Composable
internal fun TracerouteSection(
    viewModel: NetworkToolsViewModel,
    contentBottomPadding: androidx.compose.ui.unit.Dp = 0.dp
) {
    val context = LocalContext.current
    val traceTarget by viewModel.traceTarget.collectAsStateWithLifecycle()
    val traceViaTunnel by viewModel.traceViaTunnel.collectAsStateWithLifecycle()
    val traceMaxHops by viewModel.traceMaxHops.collectAsStateWithLifecycle()
    val isTracing by viewModel.isTracing.collectAsStateWithLifecycle()
    val traceHops by viewModel.traceHops.collectAsStateWithLifecycle()
    val traceResult by viewModel.traceResult.collectAsStateWithLifecycle()

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
                            value = traceTarget,
                            onValueChange = viewModel::setTraceTarget,
                            label = "输入 IP 或域名",
                            onDone = viewModel::runTraceRoute
                        )
                    },
                    {
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 16.dp, vertical = 12.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            NetworkToolSectionLabel("最大跳数")
                            val hopOptions = listOf("15 跳", "30 跳")
                            NetworkToolSegmentedRow(
                                options = hopOptions,
                                selectedIndex = hopOptions.indexOf("$traceMaxHops 跳").coerceAtLeast(0),
                                onSelect = { index ->
                                    viewModel.setTraceMaxHops(hopOptions[index].substringBefore(" ").toInt())
                                }
                            )
                        }
                    },
                    {
                        SettingsSwitchItem(
                            title = localizedText("通过 Go 隧道解析"),
                            subtitle = localizedText("域名经运行中的 Go 隧道解析（应用覆写与过滤规则），探测仍走物理网络"),
                            checked = traceViaTunnel,
                            onCheckedChange = viewModel::setTraceViaTunnel
                        )
                    }
                )
            )
        }
        item {
            NetworkToolRunButton(
                running = isTracing,
                runningLabel = "追踪中...",
                idleLabel = "开始追踪",
                onClick = viewModel::runTraceRoute,
                modifier = Modifier.padding(horizontal = 16.dp)
            )
        }
        if (traceResult != null || traceHops.isNotEmpty()) {
            item { SettingsGroupTitle("测试结果") }
            item {
                SettingsSurfaceGroup(
                    content = listOf {
                        TraceResultContent(
                            result = traceResult,
                            hops = traceHops,
                            onCopyAddress = { address ->
                                context.copyToClipboard("Hop", address)
                                context.showToast(localizedText(context, "已复制到剪贴板"))
                            }
                        )
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
private fun TraceResultContent(
    result: NetworkTraceRouteTool.Progress?,
    hops: List<NetworkTraceRouteTool.Hop>,
    onCopyAddress: (String) -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        result?.let {
            NetworkToolResultHeader(
                success = it.success,
                title = if (it.success) "追踪完成" else "追踪失败",
                subtitle = it.message?.let { message -> localizedText(message) }
            )
            it.resolvedAddress?.let { address ->
                val target = listOfNotNull(address, it.addressFamily).joinToString(" · ")
                NetworkToolInfoRow(label = "目标地址", value = target)
            }
        }
        if (hops.isNotEmpty()) {
            Column {
                hops.forEachIndexed { index, hop ->
                    TraceHopRow(
                        hop = hop,
                        isFirst = index == 0,
                        isLast = index == hops.lastIndex,
                        onCopyAddress = onCopyAddress
                    )
                }
            }
        }
    }
}

@Composable
private fun TraceHopRow(
    hop: NetworkTraceRouteTool.Hop,
    isFirst: Boolean,
    isLast: Boolean,
    onCopyAddress: (String) -> Unit
) {
    val responded = hop.responded && hop.address != null
    val accentColor = when {
        hop.isDestination -> MaterialTheme.colorScheme.primary
        responded -> MaterialTheme.colorScheme.onSurface
        else -> MaterialTheme.colorScheme.error
    }
    val lineColor = MaterialTheme.colorScheme.outlineVariant
    val dotColor = if (responded || hop.isDestination) {
        MaterialTheme.colorScheme.primary
    } else {
        MaterialTheme.colorScheme.error
    }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(IntrinsicSize.Max)
    ) {
        Canvas(
            modifier = Modifier
                .width(20.dp)
                .fillMaxHeight()
        ) {
            val centerX = size.width / 2f
            val centerY = size.height / 2f
            val radius = 3.dp.toPx()
            val strokeWidth = 1.5.dp.toPx()
            if (!isFirst) {
                drawLine(
                    color = lineColor,
                    start = Offset(centerX, 0f),
                    end = Offset(centerX, centerY - radius - 2.dp.toPx()),
                    strokeWidth = strokeWidth
                )
            }
            if (!isLast) {
                drawLine(
                    color = lineColor,
                    start = Offset(centerX, centerY + radius + 2.dp.toPx()),
                    end = Offset(centerX, size.height),
                    strokeWidth = strokeWidth
                )
            }
            if (responded) {
                drawCircle(color = dotColor, radius = radius, center = Offset(centerX, centerY))
            } else {
                drawCircle(
                    color = dotColor,
                    radius = radius,
                    center = Offset(centerX, centerY),
                    style = Stroke(width = strokeWidth)
                )
            }
        }
        Row(
            modifier = Modifier
                .weight(1f)
                .clickable(enabled = responded) { onCopyAddress(hop.address ?: return@clickable) }
                .padding(vertical = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = "#${hop.index}",
                style = MaterialTheme.typography.labelMedium,
                fontFamily = FontFamily.Monospace,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Row(
                modifier = Modifier.weight(1f),
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                if (responded) {
                    Text(
                        text = hop.address,
                        style = MaterialTheme.typography.bodyMedium,
                        fontFamily = FontFamily.Monospace,
                        color = accentColor
                    )
                    if (hop.isDestination) {
                        Surface(
                            shape = RoundedCornerShape(6.dp),
                            color = MaterialTheme.colorScheme.primaryContainer,
                            contentColor = MaterialTheme.colorScheme.onPrimaryContainer
                        ) {
                            Text(
                                text = localizedText("目标"),
                                style = MaterialTheme.typography.labelSmall,
                                modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp)
                            )
                        }
                    }
                } else {
                    Text(
                        text = localizedText(hop.error ?: "超时或无响应"),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error
                    )
                }
            }
            hop.elapsedMs?.let { elapsed ->
                Text(
                    text = formatMsValue(elapsed),
                    style = MaterialTheme.typography.bodyMedium,
                    fontFamily = FontFamily.Monospace,
                    color = if (responded) {
                        MaterialTheme.colorScheme.primary
                    } else {
                        MaterialTheme.colorScheme.error
                    }
                )
            }
        }
    }
}
