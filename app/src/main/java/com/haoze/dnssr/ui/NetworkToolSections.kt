package com.haoze.dnssr.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.haoze.dnssr.ui.components.NetworkToolCopyValueRow
import com.haoze.dnssr.ui.components.NetworkToolInfoRow
import com.haoze.dnssr.ui.components.NetworkToolResultHeader
import com.haoze.dnssr.ui.components.NetworkToolRunButton
import com.haoze.dnssr.ui.components.NetworkToolSectionLabel
import com.haoze.dnssr.ui.components.NetworkToolSegmentedRow
import com.haoze.dnssr.ui.components.NetworkToolStat
import com.haoze.dnssr.ui.components.NetworkToolStatBand
import com.haoze.dnssr.ui.components.SettingsCornerShape
import com.haoze.dnssr.ui.components.SettingsGroupTitle
import com.haoze.dnssr.ui.components.SettingsInfoText
import com.haoze.dnssr.ui.components.SettingsSurfaceGroup
import com.haoze.dnssr.ui.components.formatLossPercent
import com.haoze.dnssr.ui.components.formatMsValue
import com.haoze.dnssr.vpn.DnsLookupTool
import com.haoze.dnssr.vpn.NetworkPingTool
import com.haoze.dnssr.vpn.NetworkTraceRouteTool

private val ToolPageContentPadding = PaddingValues(top = 12.dp, bottom = 24.dp)

/**
 * Ping 测试分区：目标与次数配置 → 开始按钮 → 统计带与逐包明细。
 */
@Composable
internal fun PingSection(viewModel: NetworkToolsViewModel) {
    val pingTarget by viewModel.pingTarget.collectAsStateWithLifecycle()
    val pingCount by viewModel.pingCount.collectAsStateWithLifecycle()
    val isPinging by viewModel.isPinging.collectAsStateWithLifecycle()
    val pingResult by viewModel.pingResult.collectAsStateWithLifecycle()

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = ToolPageContentPadding,
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

/**
 * DNS 解析查询分区：域名、记录类型与服务器配置 → 开始按钮 → 解析结果与记录明细。
 */
@Composable
internal fun DnsLookupSection(viewModel: NetworkToolsViewModel) {
    val context = LocalContext.current
    val dnsHost by viewModel.dnsHost.collectAsStateWithLifecycle()
    val dnsRecordType by viewModel.dnsRecordType.collectAsStateWithLifecycle()
    val dnsServerMode by viewModel.dnsServerMode.collectAsStateWithLifecycle()
    val customDnsServer by viewModel.customDnsServer.collectAsStateWithLifecycle()
    val isDnsLookingUp by viewModel.isDnsLookingUp.collectAsStateWithLifecycle()
    val dnsResult by viewModel.dnsResult.collectAsStateWithLifecycle()

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = ToolPageContentPadding,
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            val configItems: List<@Composable () -> Unit> = listOf<@Composable () -> Unit>(
                {
                    ToolTargetField(
                        value = dnsHost,
                        onValueChange = viewModel::setDnsHost,
                        label = "输入要解析的域名",
                        onDone = viewModel::runDnsLookup
                    )
                },
                {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 12.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        NetworkToolSectionLabel("记录类型")
                        val types = DnsLookupTool.RecordType.entries.toList()
                        NetworkToolSegmentedRow(
                            options = types.map { it.label },
                            selectedIndex = types.indexOf(dnsRecordType).coerceAtLeast(0),
                            onSelect = { index -> viewModel.setDnsRecordType(types[index]) }
                        )
                    }
                },
                {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 12.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        NetworkToolSectionLabel("DNS 服务器")
                        val modes = DnsServerMode.entries.toList()
                        NetworkToolSegmentedRow(
                            options = modes.map { it.label },
                            selectedIndex = modes.indexOf(dnsServerMode).coerceAtLeast(0),
                            onSelect = { index -> viewModel.setDnsServerMode(modes[index]) }
                        )
                    }
                }
            ) + if (dnsServerMode == DnsServerMode.CUSTOM) {
                listOf<@Composable () -> Unit>(
                    {
                        ToolTargetField(
                            value = customDnsServer,
                            onValueChange = viewModel::setCustomDnsServer,
                            label = "自定义 DNS 服务器 IP",
                            onDone = viewModel::runDnsLookup
                        )
                    }
                )
            } else {
                emptyList<@Composable () -> Unit>()
            }
            SettingsSurfaceGroup(content = configItems)
        }
        item {
            NetworkToolRunButton(
                running = isDnsLookingUp,
                runningLabel = "查询中...",
                idleLabel = "开始查询",
                onClick = viewModel::runDnsLookup,
                modifier = Modifier.padding(horizontal = 16.dp)
            )
        }
        val currentDnsResult = dnsResult
        if (currentDnsResult != null) {
            item { SettingsGroupTitle("解析结果") }
            item {
                SettingsSurfaceGroup(
                    content = listOf {
                        DnsResultContent(currentDnsResult) { value ->
                            context.copyToClipboard("DNS", value)
                            context.showToast(localizedText(context, "已复制到剪贴板"))
                        }
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
private fun DnsResultContent(
    result: DnsLookupTool.Result,
    onCopyValue: (String) -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        NetworkToolResultHeader(
            success = result.success,
            title = if (result.success) "查询成功" else "查询失败"
        )
        if (result.server.isNotEmpty()) {
            NetworkToolInfoRow(label = "DNS 服务器", value = result.server)
        }
        NetworkToolInfoRow(label = "耗时", value = "${result.elapsedMs} ms")
        result.rcodeLabel?.let { rcode ->
            NetworkToolInfoRow(label = "响应状态", value = rcode)
        }
        if (result.resolvedAddresses.isNotEmpty()) {
            NetworkToolSectionLabel("解析 IP")
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                result.resolvedAddresses.forEach { address ->
                    NetworkToolCopyValueRow(
                        value = address,
                        copyLabel = "复制",
                        onCopy = { onCopyValue(address) }
                    )
                }
            }
        }
        result.message?.let { message ->
            Text(
                text = localizedText(message),
                style = MaterialTheme.typography.bodySmall,
                color = if (result.success) {
                    MaterialTheme.colorScheme.onSurfaceVariant
                } else {
                    MaterialTheme.colorScheme.error
                }
            )
        }
        if (result.records.isNotEmpty()) {
            NetworkToolSectionLabel("记录明细（${result.records.size} 条）")
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                result.records.forEach { record ->
                    DnsRecordItem(record = record, queryName = result.queryName)
                }
            }
        }
    }
}

@Composable
private fun DnsRecordItem(record: DnsLookupTool.Record, queryName: String) {
    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(2.dp)
    ) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Surface(
                shape = RoundedCornerShape(6.dp),
                color = MaterialTheme.colorScheme.primaryContainer,
                contentColor = MaterialTheme.colorScheme.onPrimaryContainer
            ) {
                Text(
                    text = record.typeLabel,
                    style = MaterialTheme.typography.labelSmall,
                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp)
                )
            }
            Text(
                text = "TTL ${record.ttlSeconds}s",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        Text(
            text = record.value,
            style = MaterialTheme.typography.bodyMedium,
            fontFamily = FontFamily.Monospace
        )
        if (record.name.isNotBlank() && !record.name.equals(queryName, ignoreCase = true)) {
            Text(
                text = record.name,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

/**
 * 路由追踪分区：目标与跳数配置 → 开始按钮 → 逐跳时间轴。
 */
@Composable
internal fun TracerouteSection(viewModel: NetworkToolsViewModel) {
    val context = LocalContext.current
    val traceTarget by viewModel.traceTarget.collectAsStateWithLifecycle()
    val traceMaxHops by viewModel.traceMaxHops.collectAsStateWithLifecycle()
    val isTracing by viewModel.isTracing.collectAsStateWithLifecycle()
    val traceHops by viewModel.traceHops.collectAsStateWithLifecycle()
    val traceResult by viewModel.traceResult.collectAsStateWithLifecycle()

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = ToolPageContentPadding,
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
                        text = hop.address ?: "",
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

@Composable
private fun ToolTargetField(
    value: String,
    onValueChange: (String) -> Unit,
    label: String,
    onDone: () -> Unit
) {
    val focusManager = LocalFocusManager.current
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        label = { Text(localizedText(label)) },
        singleLine = true,
        keyboardOptions = KeyboardOptions(
            keyboardType = KeyboardType.Uri,
            imeAction = ImeAction.Done
        ),
        keyboardActions = KeyboardActions(
            onDone = {
                focusManager.clearFocus()
                onDone()
            }
        ),
        shape = SettingsCornerShape,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp)
    )
}
