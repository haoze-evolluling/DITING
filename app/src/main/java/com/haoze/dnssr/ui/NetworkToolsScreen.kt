package com.haoze.dnssr.ui

import android.widget.Toast
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.haoze.dnssr.ui.components.SettingsActionButton
import com.haoze.dnssr.ui.components.SettingsCornerShape
import com.haoze.dnssr.ui.components.SettingsGroupTitle
import com.haoze.dnssr.ui.components.SettingsInfoText
import com.haoze.dnssr.ui.components.SettingsItem
import com.haoze.dnssr.ui.components.SettingsScaffold
import com.haoze.dnssr.ui.components.SettingsSurfaceGroup
import com.haoze.dnssr.vpn.DnsLookupTool
import com.haoze.dnssr.vpn.NetworkPingTool
import com.haoze.dnssr.vpn.NetworkSnapshot
import com.haoze.dnssr.vpn.NetworkTraceRouteTool
import java.util.Locale
import kotlin.math.roundToInt

/**
 * 统一的网络诊断模块：集中提供 DNS 查询测速、Ping 测试、DNS 解析查询与路由追踪。
 */
@Composable
fun NetworkToolsScreen(
    onBack: () -> Unit,
    title: String = "网络诊断",
    viewModel: NetworkToolsViewModel = viewModel(),
    speedTestViewModel: RaceModeSettingsViewModel = viewModel()
) {
    val context = LocalContext.current
    val toolMode by viewModel.toolMode.collectAsStateWithLifecycle()
    val networkSnapshot by viewModel.networkSnapshot.collectAsStateWithLifecycle()
    val message by viewModel.message.collectAsStateWithLifecycle()

    LaunchedEffect(message) {
        message?.let {
            context.showToast(it, Toast.LENGTH_SHORT)
            viewModel.clearMessage()
        }
    }

    NavigationSettledEffect {
        viewModel.activate()
    }

    SettingsScaffold(
        title = title,
        onBack = onBack
    ) { innerPadding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            item {
                ToggleRow(
                    options = NetworkToolMode.entries.map { it.label },
                    selectedIndex = NetworkToolMode.entries.indexOf(toolMode),
                    onSelect = { index -> viewModel.setToolMode(NetworkToolMode.entries[index]) },
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp)
                )
            }

            item {
                SettingsGroupTitle(localizedText("当前网络"))
            }
            item {
                NetworkInfoGroup(networkSnapshot)
            }

            when (toolMode) {
                NetworkToolMode.SPEED_TEST -> item { SpeedTestSection(speedTestViewModel) }
                NetworkToolMode.PING -> item { PingSection(viewModel) }
                NetworkToolMode.DNS_LOOKUP -> item { DnsLookupSection(viewModel) }
                NetworkToolMode.TRACEROUTE -> item { TracerouteSection(viewModel) }
            }

            item {
                SettingsInfoText(localizedText("结果只反映执行时刻的网络状态；部分目标会限制 ICMP 响应或 DNS 查询。"))
            }
        }
    }
}

@Composable
private fun ToggleRow(
    options: List<String>,
    selectedIndex: Int,
    onSelect: (Int) -> Unit,
    modifier: Modifier = Modifier
) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
        modifier = modifier.fillMaxWidth()
    ) {
        options.forEachIndexed { index, option ->
            FilterChip(
                selected = selectedIndex == index,
                onClick = { onSelect(index) },
                label = {
                    Text(
                        text = localizedText(option),
                        textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth()
                    )
                },
                modifier = Modifier.weight(1f)
            )
        }
    }
}

@Composable
private fun NetworkInfoGroup(snapshot: NetworkSnapshot?) {
    if (snapshot == null) {
        SettingsInfoText(localizedText("未获取到当前网络信息"))
        return
    }
    SettingsSurfaceGroup(
        content = listOf(
            {
                SettingsItem(
                    title = "网络类型",
                    subtitle = listOfNotNull(snapshot.networkType, snapshot.interfaceName).joinToString(" · ")
                )
            },
            {
                SettingsItem(
                    title = "IPv4 地址",
                    subtitle = snapshot.ipv4Addresses.joinToString(" / ").ifEmpty { "-" }
                )
            },
            {
                SettingsItem(
                    title = "IPv6 地址",
                    subtitle = snapshot.ipv6Addresses.joinToString(" / ").ifEmpty { "-" }
                )
            },
            {
                SettingsItem(
                    title = "网关",
                    subtitle = snapshot.gateway ?: "-"
                )
            },
            {
                SettingsItem(
                    title = "DNS 服务器",
                    subtitle = snapshot.dnsServers.joinToString(" / ").ifEmpty { "-" }
                )
            }
        )
    )
}

@Composable
private fun PingSection(viewModel: NetworkToolsViewModel) {
    val pingTarget by viewModel.pingTarget.collectAsStateWithLifecycle()
    val pingCount by viewModel.pingCount.collectAsStateWithLifecycle()
    val isPinging by viewModel.isPinging.collectAsStateWithLifecycle()
    val pingResult by viewModel.pingResult.collectAsStateWithLifecycle()

    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        SettingsGroupTitle(localizedText("Ping 测试"))
        SettingsSurfaceGroup(
            content = listOf {
                OutlinedTextField(
                    value = pingTarget,
                    onValueChange = viewModel::setPingTarget,
                    label = { Text(localizedText("输入 IP 或域名")) },
                    keyboardOptions = KeyboardOptions(
                        keyboardType = KeyboardType.Uri,
                        imeAction = ImeAction.Done
                    ),
                    shape = SettingsCornerShape,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 12.dp)
                )
            }
        )
        SettingsInfoText(localizedText("通过 ICMP 测量目标 IP 或域名的连通性，输出时延、丢包率与 TTL 等信息。"))
        SettingsGroupTitle(localizedText("Ping 次数"))
        val countOptions = listOf(4, 10)
        ToggleRow(
            options = countOptions.map { "$it 次" },
            selectedIndex = countOptions.indexOf(pingCount).coerceAtLeast(0),
            onSelect = { index -> viewModel.setPingCount(countOptions[index]) },
            modifier = Modifier.padding(horizontal = 16.dp)
        )
        SettingsGroupTitle(localizedText("测试结果"))
        SettingsSurfaceGroup(
            content = listOf {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 12.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    SettingsActionButton(
                        onClick = viewModel::runPing,
                        enabled = !isPinging,
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(text = localizedText(if (isPinging) "Ping 中..." else "开始 Ping"))
                    }
                    pingResult?.let { result ->
                        PingResultContent(result)
                    }
                }
            }
        )
    }
}

@Composable
private fun DnsLookupSection(viewModel: NetworkToolsViewModel) {
    val dnsHost by viewModel.dnsHost.collectAsStateWithLifecycle()
    val dnsRecordType by viewModel.dnsRecordType.collectAsStateWithLifecycle()
    val dnsServerMode by viewModel.dnsServerMode.collectAsStateWithLifecycle()
    val customDnsServer by viewModel.customDnsServer.collectAsStateWithLifecycle()
    val isDnsLookingUp by viewModel.isDnsLookingUp.collectAsStateWithLifecycle()
    val dnsResult by viewModel.dnsResult.collectAsStateWithLifecycle()

    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        SettingsGroupTitle(localizedText("DNS 解析查询"))
        SettingsSurfaceGroup(
            content = listOf {
                OutlinedTextField(
                    value = dnsHost,
                    onValueChange = viewModel::setDnsHost,
                    label = { Text(localizedText("输入要解析的域名")) },
                    keyboardOptions = KeyboardOptions(
                        keyboardType = KeyboardType.Uri,
                        imeAction = ImeAction.Done
                    ),
                    shape = SettingsCornerShape,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 12.dp)
                )
            }
        )
        SettingsInfoText(localizedText("向指定 DNS 服务器查询域名的 A / AAAA 记录，展示解析 IP、TTL 与记录明细。"))
        SettingsGroupTitle(localizedText("记录类型"))
        val types = DnsLookupTool.RecordType.entries.toList()
        ToggleRow(
            options = types.map { it.label },
            selectedIndex = types.indexOf(dnsRecordType).coerceAtLeast(0),
            onSelect = { index -> viewModel.setDnsRecordType(types[index]) },
            modifier = Modifier.padding(horizontal = 16.dp)
        )
        SettingsGroupTitle(localizedText("DNS 服务器"))
        val modes = DnsServerMode.entries.toList()
        ToggleRow(
            options = modes.map { it.label },
            selectedIndex = modes.indexOf(dnsServerMode).coerceAtLeast(0),
            onSelect = { index -> viewModel.setDnsServerMode(modes[index]) },
            modifier = Modifier.padding(horizontal = 16.dp)
        )
        if (dnsServerMode == DnsServerMode.CUSTOM) {
            SettingsSurfaceGroup(
                content = listOf {
                    OutlinedTextField(
                        value = customDnsServer,
                        onValueChange = viewModel::setCustomDnsServer,
                        label = { Text(localizedText("自定义 DNS 服务器 IP")) },
                        keyboardOptions = KeyboardOptions(
                            keyboardType = KeyboardType.Uri,
                            imeAction = ImeAction.Done
                        ),
                        shape = SettingsCornerShape,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 12.dp)
                    )
                }
            )
        }
        SettingsGroupTitle(localizedText("解析结果"))
        SettingsSurfaceGroup(
            content = listOf {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 12.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    SettingsActionButton(
                        onClick = viewModel::runDnsLookup,
                        enabled = !isDnsLookingUp,
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(text = localizedText(if (isDnsLookingUp) "查询中..." else "开始查询"))
                    }
                    dnsResult?.let { result ->
                        DnsResultContent(result)
                    }
                }
            }
        )
    }
}

@Composable
private fun TracerouteSection(viewModel: NetworkToolsViewModel) {
    val traceTarget by viewModel.traceTarget.collectAsStateWithLifecycle()
    val traceMaxHops by viewModel.traceMaxHops.collectAsStateWithLifecycle()
    val isTracing by viewModel.isTracing.collectAsStateWithLifecycle()
    val traceHops by viewModel.traceHops.collectAsStateWithLifecycle()
    val traceResult by viewModel.traceResult.collectAsStateWithLifecycle()

    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        SettingsGroupTitle(localizedText("路由追踪"))
        SettingsSurfaceGroup(
            content = listOf {
                OutlinedTextField(
                    value = traceTarget,
                    onValueChange = viewModel::setTraceTarget,
                    label = { Text(localizedText("输入 IP 或域名")) },
                    keyboardOptions = KeyboardOptions(
                        keyboardType = KeyboardType.Uri,
                        imeAction = ImeAction.Done
                    ),
                    shape = SettingsCornerShape,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 12.dp)
                )
            }
        )
        SettingsInfoText(localizedText("通过递增 TTL 逐跳探测到达目标的路径，展示每一跳路由地址与响应时延。"))
        SettingsGroupTitle(localizedText("最大跳数"))
        val hopOptions = listOf(15, 30)
        ToggleRow(
            options = hopOptions.map { "$it 跳" },
            selectedIndex = hopOptions.indexOf(traceMaxHops).coerceAtLeast(0),
            onSelect = { index -> viewModel.setTraceMaxHops(hopOptions[index]) },
            modifier = Modifier.padding(horizontal = 16.dp)
        )
        SettingsGroupTitle(localizedText("测试结果"))
        SettingsSurfaceGroup(
            content = listOf {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 12.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    SettingsActionButton(
                        onClick = viewModel::runTraceRoute,
                        enabled = !isTracing,
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(text = localizedText(if (isTracing) "追踪中..." else "开始追踪"))
                    }
                    traceResult?.let { result ->
                        TraceSummaryContent(result)
                    }
                    val hops = if (isTracing) traceHops else (traceResult?.hops ?: traceHops)
                    hops.forEach { hop ->
                        TraceHopRow(hop)
                    }
                }
            }
        )
    }
}

@Composable
private fun TraceSummaryContent(result: NetworkTraceRouteTool.Progress) {
    val statusColor = if (result.success) {
        MaterialTheme.colorScheme.primary
    } else {
        MaterialTheme.colorScheme.error
    }
    result.resolvedAddress?.let { address ->
        val target = listOfNotNull(address, result.addressFamily).joinToString(" · ")
        ResultInfoRow(label = localizedText("目标地址"), value = localizedText("解析到 $target"))
    }
    result.message?.let { message ->
        Text(
            text = localizedText(message),
            style = MaterialTheme.typography.bodySmall,
            color = statusColor
        )
    }
}

@Composable
private fun TraceHopRow(hop: NetworkTraceRouteTool.Hop) {
    val color = when {
        hop.isDestination -> MaterialTheme.colorScheme.primary
        hop.responded -> MaterialTheme.colorScheme.onSurface
        else -> MaterialTheme.colorScheme.error
    }
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = "#${hop.index}",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        if (hop.responded && hop.address != null) {
            Text(
                text = buildString {
                    append(hop.address)
                    if (hop.isDestination) {
                        append(" · ")
                        append(localizedText("目标"))
                    }
                    hop.elapsedMs?.let { elapsed ->
                        append(" · ")
                        append(formatMsValue(elapsed))
                    }
                },
                style = MaterialTheme.typography.bodySmall,
                color = color,
                textAlign = TextAlign.End,
                modifier = Modifier.weight(1f)
            )
        } else {
            Text(
                text = localizedText(hop.error ?: "超时或无响应"),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.error,
                textAlign = TextAlign.End,
                modifier = Modifier.weight(1f)
            )
        }
    }
}

@Composable
private fun PingResultContent(result: NetworkPingTool.Summary) {
    val statusColor = if (result.success) {
        MaterialTheme.colorScheme.primary
    } else {
        MaterialTheme.colorScheme.error
    }
    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        result.resolvedAddress?.let { address ->
            val target = listOfNotNull(address, result.addressFamily).joinToString(" · ")
            ResultInfoRow(label = localizedText("目标地址"), value = localizedText("解析到 $target"))
        }
        Text(
            text = localizedText("发送 ${result.transmitted} · 接收 ${result.received} · 丢包率 ${formatLossPercent(result.lossPercent)}"),
            style = MaterialTheme.typography.bodySmall,
            color = statusColor
        )
        if (result.avgMs != null) {
            Text(
                text = localizedText(buildString {
                    append("最小 ")
                    append(formatMsValue(result.minMs ?: result.avgMs))
                    append(" · 平均 ")
                    append(formatMsValue(result.avgMs))
                    append(" · 最大 ")
                    append(formatMsValue(result.maxMs ?: result.avgMs))
                    result.jitterMs?.let { jitter ->
                        append(" · 抖动 ")
                        append(formatMsValue(jitter))
                    }
                }),
                style = MaterialTheme.typography.bodySmall,
                color = statusColor
            )
        }
        result.message?.let { message ->
            Text(
                text = localizedText(message),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        result.replies.forEach { reply ->
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "#${reply.sequence}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                if (reply.elapsedMs != null) {
                    Text(
                        text = buildString {
                            append(formatMsValue(reply.elapsedMs))
                            reply.ttl?.let { ttl -> append(" · TTL $ttl") }
                        },
                        style = MaterialTheme.typography.bodySmall,
                        color = statusColor,
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

@Composable
private fun DnsResultContent(result: DnsLookupTool.Result) {
    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        if (result.server.isNotEmpty()) {
            ResultInfoRow(label = localizedText("DNS 服务器"), value = result.server)
        }
        ResultInfoRow(label = localizedText("耗时"), value = "${result.elapsedMs} ms")
        result.rcodeLabel?.let { rcode ->
            ResultInfoRow(label = localizedText("响应状态"), value = rcode)
        }
        if (result.resolvedAddresses.isNotEmpty()) {
            ResultInfoRow(
                label = localizedText("解析 IP"),
                value = result.resolvedAddresses.joinToString("\n"),
                valueColor = MaterialTheme.colorScheme.primary
            )
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
            Text(
                text = localizedText("记录明细（${result.records.size} 条）"),
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            result.records.forEach { record ->
                DnsRecordItem(record = record, queryName = result.queryName)
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
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = record.typeLabel,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.primary
            )
            Text(
                text = "TTL ${record.ttlSeconds}s",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        Text(
            text = record.value,
            style = MaterialTheme.typography.bodyMedium
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

@Composable
private fun ResultInfoRow(
    label: String,
    value: String,
    valueColor: Color = MaterialTheme.colorScheme.onSurface
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Text(
            text = value,
            style = MaterialTheme.typography.bodyMedium,
            color = valueColor,
            modifier = Modifier.weight(1f)
        )
    }
}

private fun formatMsValue(value: Double?): String {
    if (value == null) return "-"
    return if (value >= 100) {
        "${value.roundToInt()} ms"
    } else {
        String.format(Locale.US, "%.1f ms", value)
    }
}

private fun formatLossPercent(loss: Double): String {
    return if (loss % 1.0 == 0.0) {
        "${loss.toInt()}%"
    } else {
        String.format(Locale.US, "%.1f%%", loss)
    }
}
