package com.haoze.dnssr.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.unit.dp
import com.haoze.dnssr.ui.components.DnsProtocolBadge
import com.haoze.dnssr.ui.components.SettingsGroupTitle
import com.haoze.dnssr.ui.components.SettingsInfoText
import com.haoze.dnssr.ui.components.SettingsItem
import com.haoze.dnssr.ui.components.SettingsScaffold
import com.haoze.dnssr.ui.components.SettingsSurfaceGroup
import com.haoze.dnssr.vpn.DnsProvider
import com.haoze.dnssr.vpn.ProviderHealthEngine
import com.haoze.dnssr.vpn.ProviderHealthSnapshot
import com.haoze.dnssr.vpn.ProviderHealthStore
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

private val providerHealthTimeFormatter = SimpleDateFormat("HH:mm:ss", Locale.getDefault())

private data class ProviderHealthRow(
    val provider: DnsProvider,
    val health: ProviderHealthSnapshot?,
    val normalizedWeightPercent: Int?
)

@Composable
fun ProviderHealthScreen(
    onBack: () -> Unit
) {
    val context = LocalContext.current
    val scrollState = rememberScrollState()
    var rows by remember { mutableStateOf(emptyList<ProviderHealthRow>()) }

    fun reloadRows() {
        ProviderHealthEngine.flushActive(commit = true)
        val providers = DnsProvider.loadRuntimeProviders(context)
        val healthByProvider = ProviderHealthStore.loadAll(context)
        val raceProviderIds = DnsProvider.loadRaceProviderIds(context)
        val normalizedWeights = ProviderHealthStore.normalizeWeightsToPercent(
            providers
                .filter { it.id in raceProviderIds }
                .map { provider ->
                    provider.id to (healthByProvider[provider.id]?.predictionWeight ?: 1.0)
                }
        )
        rows = providers
            .map { provider ->
                ProviderHealthRow(
                    provider = provider,
                    health = healthByProvider[provider.id],
                    normalizedWeightPercent = normalizedWeights[provider.id]
                )
            }
            .sortedWith(
                compareByDescending<ProviderHealthRow> { it.normalizedWeightPercent ?: -1 }
                    .thenBy { it.provider.name }
            )
    }

    NavigationSettledEffect {
        reloadRows()
    }

    SettingsScaffold(
        title = localizedText("DNS 提供商健康情况"),
        onBack = onBack,
        actions = {
            RefreshAction(onRefresh = { reloadRows() })
        }
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .verticalScroll(scrollState),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            SettingsGroupTitle(localizedText("服务商健康"))
            SettingsSurfaceGroup(
                content = rows.map { row ->
                    { ProviderHealthItem(row = row) }
                }
            )
            SettingsInfoText(localizedText("权重按当前勾选的竞速服务商归一化为百分制，参与竞速的服务商合计为 100%。"))
        }
    }
}

@Composable
private fun RowScope.RefreshAction(onRefresh: () -> Unit) {
    IconButton(onClick = onRefresh) {
        Icon(
            imageVector = Icons.Default.Refresh,
            contentDescription = localizedText("刷新")
        )
    }
}

@Composable
private fun ProviderHealthItem(row: ProviderHealthRow) {
    val health = row.health
    val subtitle = if (health == null || health.attempts == 0) {
        localizedText("${row.provider.endpointLabel()}\n暂无运行数据")
    } else {
        val updatedAt = providerHealthTimeFormatter.format(Date(health.lastUpdatedAt))
        localizedText("${row.provider.endpointLabel()}\n" +
            "准确率 ${formatPercent(health.accuracy)} · 延迟 ${formatMs(health.ewmaMs)} · " +
            "样本 ${health.attempts} · 更新 $updatedAt")
    }
    SettingsItem(
        title = localizedText(row.provider.name),
        subtitle = subtitle
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            DnsProtocolBadge(protocol = row.provider.protocol)
            Text(
                text = localizedText(row.normalizedWeightPercent?.let { "权重 $it%" } ?: "未参与"),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

private fun formatPercent(value: Double): String {
    return String.format(Locale.getDefault(), "%.1f%%", value * 100.0)
}

private fun formatMs(value: Double): String {
    return "${value.toInt()} ms"
}
