package com.haoze.diting.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.haoze.diting.ui.components.NetworkToolCopyValueRow
import com.haoze.diting.ui.components.NetworkToolInfoRow
import com.haoze.diting.ui.components.NetworkToolResultHeader
import com.haoze.diting.ui.components.NetworkToolRunButton
import com.haoze.diting.ui.components.NetworkToolSectionLabel
import com.haoze.diting.ui.components.NetworkToolSegmentedRow
import com.haoze.diting.ui.components.SettingsGroupTitle
import com.haoze.diting.ui.components.SettingsInfoText
import com.haoze.diting.ui.components.SettingsSurfaceGroup
import com.haoze.diting.ui.components.SettingsSwitchItem
import com.haoze.diting.vpn.DnsLookupTool

/**
 * DNS lookup section: domain, record type, and server configuration ->
 * start button -> resolution results and record details.
 */
@Composable
internal fun DnsLookupSection(
    viewModel: NetworkToolsViewModel,
    contentBottomPadding: androidx.compose.ui.unit.Dp = 0.dp
) {
    val context = LocalContext.current
    val dnsHost by viewModel.dnsHost.collectAsStateWithLifecycle()
    val dnsRecordType by viewModel.dnsRecordType.collectAsStateWithLifecycle()
    val dnsLookupViaTunnel by viewModel.dnsLookupViaTunnel.collectAsStateWithLifecycle()
    val dnsServerMode by viewModel.dnsServerMode.collectAsStateWithLifecycle()
    val customDnsServer by viewModel.customDnsServer.collectAsStateWithLifecycle()
    val isDnsLookingUp by viewModel.isDnsLookingUp.collectAsStateWithLifecycle()
    val dnsResult by viewModel.dnsResult.collectAsStateWithLifecycle()

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = toolPageContentPadding(contentBottomPadding),
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
                    SettingsSwitchItem(
                        title = localizedText("通过 Go 隧道解析"),
                        subtitle = localizedText("经运行中的 Go 隧道解析（应用覆写与过滤规则），忽略下方服务器选择"),
                        checked = dnsLookupViaTunnel,
                        onCheckedChange = viewModel::setDnsLookupViaTunnel
                    )
                }
            ) + if (!dnsLookupViaTunnel) {
                listOf<@Composable () -> Unit>(
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
