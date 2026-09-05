package com.haoze.dnssr.ui

import android.widget.Toast
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
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
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.haoze.dnssr.ui.components.DnsProtocolBadge
import com.haoze.dnssr.ui.components.NetworkToolRunButton
import com.haoze.dnssr.ui.components.NetworkToolSectionLabel
import com.haoze.dnssr.ui.components.NetworkToolSegmentedRow
import com.haoze.dnssr.ui.components.SettingsCornerShape
import com.haoze.dnssr.ui.components.SettingsCheckboxItem
import com.haoze.dnssr.ui.components.SettingsGroupTitle
import com.haoze.dnssr.ui.components.SettingsInfoText
import com.haoze.dnssr.ui.components.SettingsLoadingContent
import com.haoze.dnssr.ui.components.SettingsSurfaceGroup
import com.haoze.dnssr.vpn.DnsLatencyTester
import com.haoze.dnssr.vpn.DnsProtocol
import com.haoze.dnssr.vpn.DnsProvider

private fun availableProtocols(providers: List<DnsProvider>): List<DnsProtocol> {
    val present = providers.map { it.protocol }.toSet()
    return DnsProtocol.MANAGED_PROTOCOLS.filter { it in present }
        .ifEmpty { DnsProtocol.MANAGED_PROTOCOLS }
}

/**
 * 网络诊断中的 DNS 查询测速分区：向选中的服务商发起真实查询并比较解析耗时。
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

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(top = 12.dp, bottom = 24.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            val focusManager = LocalFocusManager.current
            SettingsSurfaceGroup(
                content = listOf(
                    {
                        OutlinedTextField(
                            value = testDomain,
                            onValueChange = { value ->
                                viewModel.setTestDomain(value.filter { !it.isWhitespace() })
                            },
                            label = { Text(localizedText("用于测速的域名")) },
                            singleLine = true,
                            keyboardOptions = KeyboardOptions(
                                keyboardType = KeyboardType.Uri,
                                imeAction = ImeAction.Done
                            ),
                            keyboardActions = KeyboardActions(
                                onDone = {
                                    focusManager.clearFocus()
                                    viewModel.runLatencyTest()
                                }
                            ),
                            shape = SettingsCornerShape,
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 16.dp, vertical = 12.dp)
                        )
                    },
                    {
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 16.dp, vertical = 12.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            NetworkToolSectionLabel("协议")
                            val protocols = availableProtocols(providers)
                            NetworkToolSegmentedRow(
                                options = protocols.map { it.label },
                                selectedIndex = protocols.indexOf(selectedProtocol).coerceAtLeast(0),
                                onSelect = { index -> selectedProtocol = protocols[index] }
                            )
                        }
                    }
                )
            )
        }

        item { SettingsGroupTitle("测速服务商") }
        item {
            val visibleProviders = providers.filter { it.protocol == selectedProtocol }
            if (visibleProviders.isEmpty()) {
                SettingsInfoText("暂无 ${selectedProtocol.label} DNS 服务商。")
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
        }
        item {
            SettingsInfoText("可选择 1 个或多个服务商；这里的选择只用于 DNS 查询测速，不影响竞速模式。")
        }

        item {
            NetworkToolRunButton(
                running = isTesting,
                runningLabel = "测速中...",
                idleLabel = "测试查询耗时",
                enabled = selectedIds.isNotEmpty(),
                onClick = { viewModel.runLatencyTest() },
                modifier = Modifier.padding(horizontal = 16.dp)
            )
        }

        if (results.isNotEmpty()) {
            item { SettingsGroupTitle("查询耗时结果") }
            item {
                SettingsSurfaceGroup(
                    content = listOf {
                        SpeedTestResultList(results)
                    }
                )
            }
        }
        item {
            SettingsInfoText("测速结果按成功优先、平均耗时从低到高排序；结果只反映当前网络状态。")
        }
    }
}

/**
 * 测速结果列表：按名次展示服务商，最快的给出「最快」徽章，并绘制与最长耗时成比例的耗时条。
 */
@Composable
private fun SpeedTestResultList(results: List<DnsLatencyTester.Result>) {
    val maxLatency = results.filter { it.success }.maxOfOrNull { it.elapsedMs } ?: 0L
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        results.forEachIndexed { index, result ->
            SpeedTestResultRow(
                result = result,
                rank = index + 1,
                isFastest = index == 0 && result.success,
                maxLatency = maxLatency
            )
            if (index != results.lastIndex) {
                HorizontalDivider(
                    thickness = 0.5.dp,
                    color = MaterialTheme.colorScheme.outlineVariant
                )
            }
        }
    }
}

@Composable
private fun SpeedTestResultRow(
    result: DnsLatencyTester.Result,
    rank: Int,
    isFastest: Boolean,
    maxLatency: Long
) {
    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = "$rank",
                style = MaterialTheme.typography.titleMedium,
                fontFamily = FontFamily.Monospace,
                color = if (isFastest) {
                    MaterialTheme.colorScheme.primary
                } else {
                    MaterialTheme.colorScheme.onSurfaceVariant
                },
                modifier = Modifier.width(20.dp)
            )
            Text(
                text = localizedText(result.providerName),
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurface,
                modifier = Modifier.weight(1f)
            )
            DnsProtocolBadge(protocol = result.protocol)
            if (isFastest) {
                Surface(
                    shape = RoundedCornerShape(6.dp),
                    color = MaterialTheme.colorScheme.primaryContainer,
                    contentColor = MaterialTheme.colorScheme.onPrimaryContainer
                ) {
                    Text(
                        text = localizedText("最快"),
                        style = MaterialTheme.typography.labelSmall,
                        modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp)
                    )
                }
            }
        }
        if (result.success) {
            Text(
                text = "${result.elapsedMs} ms",
                style = MaterialTheme.typography.titleMedium,
                fontFamily = FontFamily.Monospace,
                color = MaterialTheme.colorScheme.primary
            )
            LinearProgressIndicator(
                progress = { (result.elapsedMs.toFloat() / maxLatency.coerceAtLeast(1L)).coerceIn(0f, 1f) },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(6.dp)
            )
            Text(
                text = buildString {
                    append(localizedText("成功率 ${result.successCount}/${result.attempts}"))
                    if (result.elapsedSamplesMs.size > 1) {
                        append(" · ")
                        append(localizedText("样本 "))
                        append(result.elapsedSamplesMs.joinToString(" / ") { "$it ms" })
                    }
                },
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        } else {
            Text(
                text = localizedText("全部失败（${result.attempts} 次）"),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.error
            )
            result.message?.let { message ->
                Text(
                    text = localizedText(message),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error
                )
            }
        }
    }
}
