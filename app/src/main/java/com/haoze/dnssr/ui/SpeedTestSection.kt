package com.haoze.dnssr.ui

import android.widget.Toast
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.haoze.dnssr.ui.components.DnsProtocolBadge
import com.haoze.dnssr.ui.components.SettingsActionButton
import com.haoze.dnssr.ui.components.SettingsCheckboxItem
import com.haoze.dnssr.ui.components.SettingsCornerShape
import com.haoze.dnssr.ui.components.SettingsGroupTitle
import com.haoze.dnssr.ui.components.SettingsInfoText
import com.haoze.dnssr.ui.components.SettingsLoadingContent
import com.haoze.dnssr.ui.components.SettingsSurfaceGroup
import com.haoze.dnssr.vpn.DnsLatencyTester
import com.haoze.dnssr.vpn.DnsProtocol
import com.haoze.dnssr.vpn.DnsProvider


@Composable
private fun ProtocolToggleRow(
    selectedProtocol: DnsProtocol,
    onSelect: (DnsProtocol) -> Unit,
    protocols: List<DnsProtocol>,
    modifier: Modifier = Modifier
) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
        modifier = modifier.fillMaxWidth()
    ) {
        protocols.forEach { option ->
            FilterChip(
                selected = selectedProtocol == option,
                onClick = { onSelect(option) },
                label = {
                    Text(
                        text = option.label,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth()
                    )
                },
                modifier = Modifier.weight(1f)
            )
        }
    }
}

private fun availableProtocols(providers: List<DnsProvider>): List<DnsProtocol> {
    val present = providers.map { it.protocol }.toSet()
    return DnsProtocol.MANAGED_PROTOCOLS.filter { it in present }
        .ifEmpty { DnsProtocol.MANAGED_PROTOCOLS }
}


/**
 * 网络诊断中的 DNS 查询测速区块：向选中的服务商发起真实查询并比较解析耗时。
 * 服务商选择、测速域名等设置与原查询测速页保持一致，由 [RaceModeSettingsViewModel] 承载。
 */
@Composable
internal fun SpeedTestSection(viewModel: RaceModeSettingsViewModel) {
    val context = LocalContext.current
    val providers by viewModel.providers.collectAsStateWithLifecycle()
    val selectedIds by viewModel.latencyTestSelectedIds.collectAsStateWithLifecycle()
    val testDomain by viewModel.testDomain.collectAsStateWithLifecycle()
    val isTesting by viewModel.isTesting.collectAsStateWithLifecycle()
    val results by viewModel.results.collectAsStateWithLifecycle()
    val message by viewModel.message.collectAsStateWithLifecycle()
    val initialLoading by viewModel.initialLoading.collectAsStateWithLifecycle()
    var selectedProtocol by remember { mutableStateOf(DnsProtocol.DNS) }

    LaunchedEffect(message) {
        message?.let {
            context.showToast(it, Toast.LENGTH_SHORT)
            viewModel.clearMessage()
        }
    }

    NavigationSettledEffect {
        viewModel.activate()
    }

    LaunchedEffect(providers) {
        val protocols = availableProtocols(providers)
        if (selectedProtocol !in protocols) {
            selectedProtocol = protocols.firstOrNull() ?: DnsProtocol.DNS
        }
    }

    if (initialLoading) {
        SettingsLoadingContent(modifier = Modifier.fillMaxWidth())
        return
    }

    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        SettingsGroupTitle(localizedText("测速域名"))
        SettingsSurfaceGroup(
            content = listOf {
                OutlinedTextField(
                    value = testDomain,
                    onValueChange = { value ->
                        viewModel.setTestDomain(value.filter { !it.isWhitespace() })
                    },
                    label = { Text(localizedText("用于测速的域名")) },
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
        SettingsInfoText(localizedText("会向已选择的测速服务商查询这个域名，每个服务商连续测 3 次并按成功样本取平均值。"))

        ProtocolToggleRow(
            selectedProtocol = selectedProtocol,
            onSelect = { selectedProtocol = it },
            protocols = availableProtocols(providers),
            modifier = Modifier.padding(horizontal = 16.dp)
        )
        SettingsGroupTitle(localizedText("测速服务商"))
        val visibleProviders = providers.filter { it.protocol == selectedProtocol }
        if (visibleProviders.isEmpty()) {
            SettingsInfoText(localizedText("暂无 ${selectedProtocol.label} DNS 服务商。"))
        } else {
            SettingsSurfaceGroup(
                content = visibleProviders.map { provider ->
                    {
                        SettingsCheckboxItem(
                            title = localizedText(provider.name),
                            subtitle = provider.endpointLabel(),
                            checked = provider.id in selectedIds,
                            onCheckedChange = { viewModel.toggleLatencyTestProvider(provider.id) }
                        )
                    }
                }
            )
        }
        SettingsInfoText(localizedText("可选择 1 个或多个服务商；这里的选择只用于 DNS 查询测速，不影响竞速模式。"))

        SettingsGroupTitle(localizedText("查询耗时结果"))
        SettingsSurfaceGroup(
            content = listOf {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 12.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    SettingsActionButton(
                        onClick = { viewModel.runLatencyTest() },
                        enabled = !isTesting && selectedIds.isNotEmpty(),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(text = localizedText(if (isTesting) "测速中..." else "测试查询耗时"))
                    }

                    results.forEach { result ->
                        LatencyResultItem(result = result)
                    }
                }
            }
        )
        SettingsInfoText(localizedText("测速结果按成功优先、平均耗时从低到高排序；结果只反映当前网络状态。"))
    }
}

@Composable
private fun LatencyResultItem(result: DnsLatencyTester.Result) {
    val color = if (result.success) {
        MaterialTheme.colorScheme.primary
    } else {
        MaterialTheme.colorScheme.error
    }
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
                text = result.providerName,
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.weight(1f)
            )
            DnsProtocolBadge(protocol = result.protocol)
        }
        if (result.success) {
            Text(
                text = localizedText(buildString {
                    append("平均 ${result.elapsedMs} ms")
                    append(" · ${result.successCount}/${result.attempts} 次成功")
                    if (result.elapsedSamplesMs.size > 1) {
                        append(" · 样本 ")
                        append(result.elapsedSamplesMs.joinToString(" / ") { "$it ms" })
                    }
                }),
                style = MaterialTheme.typography.bodySmall,
                color = color
            )
        } else {
            Text(
                text = localizedText("全部失败（${result.attempts} 次）"),
                style = MaterialTheme.typography.bodySmall,
                color = color
            )
            result.message?.let { message ->
                Text(
                    text = localizedText(message),
                    style = MaterialTheme.typography.bodySmall,
                    color = color
                )
            }
        }
    }
}
