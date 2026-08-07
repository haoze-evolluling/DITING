package com.haoze.dnssr.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.haoze.dnssr.data.RaceStats
import com.haoze.dnssr.data.RaceStatsRange
import com.haoze.dnssr.data.RaceStrategyStats
import com.haoze.dnssr.data.RaceWinnerStats
import com.haoze.dnssr.data.SmartSelectionStats
import com.haoze.dnssr.ui.components.SettingsGroup
import com.haoze.dnssr.ui.components.SettingsCornerShape
import com.haoze.dnssr.ui.components.SettingsGroupTitle
import com.haoze.dnssr.ui.components.SettingsInfoText
import com.haoze.dnssr.ui.components.SettingsItem
import com.haoze.dnssr.ui.components.SettingsScaffold
import com.haoze.dnssr.ui.components.SettingsSurfaceGroup
import com.haoze.dnssr.ui.components.DnsProtocolBadge
import com.haoze.dnssr.vpn.DnsProtocol
import com.haoze.dnssr.vpn.DnsProvider
import java.util.Locale

@Composable
fun RaceStatsScreen(
    onBack: () -> Unit,
    viewModel: RaceStatsViewModel = viewModel()
) {
    val range by viewModel.range.collectAsStateWithLifecycle()
    val stats by viewModel.stats.collectAsStateWithLifecycle()
    val loading by viewModel.loading.collectAsStateWithLifecycle()

    LaunchedEffect(Unit) {
        viewModel.activate()
    }

    SettingsScaffold(
        title = localizedText("竞速统计"),
        onBack = onBack,
        actions = {
            IconButton(onClick = { viewModel.refresh() }) {
                Icon(
                    imageVector = Icons.Default.Refresh,
                    contentDescription = localizedText("刷新")
                )
            }
        }
    ) { innerPadding ->
        RaceStatsContent(
            stats = stats,
            range = range,
            loading = loading,
            onRangeClick = viewModel::setRange,
            modifier = Modifier.padding(innerPadding)
        )
    }
}

@Composable
private fun RaceStatsContent(
    stats: RaceStats,
    range: RaceStatsRange,
    loading: Boolean,
    onRangeClick: (RaceStatsRange) -> Unit,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val providerById = remember(context) {
        DnsProvider.loadRuntimeProviders(context).associateBy { it.id }
    }

    LazyColumn(
        modifier = modifier.fillMaxSize(),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            SettingsGroupTitle(localizedText("时间范围"))
            SettingsGroup {
                RangeSelector(
                    selected = range,
                    onRangeClick = onRangeClick
                )
            }
            SettingsInfoText(localizedText("缓存命中的 DNS 请求不会触发实际竞速，因此不计入这里的统计。"))
        }

        if (stats.strategyStats.isEmpty()) {
            item {
                SettingsGroupTitle(localizedText("统计"))
                SettingsSurfaceGroup(content = listOf {
                    SettingsItem(
                        title = localizedText(if (loading) "正在加载" else "暂无竞速数据"),
                        subtitle = localizedText("启用智能选择或最快响应并产生真实 DNS 查询后，这里会显示各策略的表现。")
                    )
                })
            }
            return@LazyColumn
        }

        item {
            SettingsGroupTitle(localizedText("策略概览"))
            SettingsSurfaceGroup(
                content = stats.strategyStats.map { item -> { StrategyStatsItem(item) } }
            )
        }

        item {
            SettingsGroupTitle(localizedText("服务商胜出排行"))
            val winners = stats.winnerStats.take(MAX_PROVIDER_ROWS)
            if (winners.isEmpty()) {
                SettingsSurfaceGroup(content = listOf { SettingsItem(title = localizedText("暂无胜出记录")) })
            } else {
                SettingsSurfaceGroup(
                    content = winners.map { item ->
                        { WinnerStatsItem(item = item, provider = providerById[item.providerId]) }
                    }
                )
            }
        }

        item {
            SettingsGroupTitle(localizedText("智能选择首选"))
            val selections = stats.smartSelectionStats.take(MAX_PROVIDER_ROWS)
            if (selections.isEmpty()) {
                SettingsSurfaceGroup(content = listOf {
                    SettingsItem(
                        title = localizedText("暂无智能选择记录"),
                        subtitle = localizedText("智能选择产生查询后，会统计首选服务商的命中情况。")
                    )
                })
            } else {
                SettingsSurfaceGroup(
                    content = selections.map { item ->
                        { SmartSelectionItem(item = item, provider = providerById[item.providerId]) }
                    }
                )
            }
        }
    }
}

@Composable
private fun RangeSelector(
    selected: RaceStatsRange,
    onRangeClick: (RaceStatsRange) -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        RaceStatsRange.values().forEach { range ->
            val selectedColor = MaterialTheme.colorScheme.primary
            TextButton(
                onClick = { onRangeClick(range) },
                shape = SettingsCornerShape,
                colors = ButtonDefaults.textButtonColors(
                    containerColor = if (range == selected) selectedColor.copy(alpha = 0.12f) else Color.Transparent,
                    contentColor = if (range == selected) selectedColor else MaterialTheme.colorScheme.onSurfaceVariant
                )
            ) {
                Text(text = localizedText(range.displayName))
            }
        }
    }
}

@Composable
private fun StrategyStatsItem(item: RaceStrategyStats) {
    val subtitle = buildString {
        append("成功 ${formatPercent(item.successRate)}")
        append(" · 平均 ${formatMs(item.avgElapsedMs)}")
        if (item.strategy == RaceModeStrategy.SMART_PREDICTION.storageValue) {
            append(" · 首选命中 ${formatPercent(item.primaryWinRate)}")
            append(" · 兜底 ${item.fallbackUses} 次")
        }
    }
    SettingsItem(
        title = localizedText(item.displayName),
        subtitle = localizedText(subtitle)
    ) {
        Text(
            text = localizedText("${item.requests} 次"),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
private fun WinnerStatsItem(
    item: RaceWinnerStats,
    provider: DnsProvider?
) {
    val strategy = RaceModeStrategy.fromStorageValue(item.strategy)
    SettingsItem(
        title = provider?.name ?: item.providerName,
        subtitle = localizedText(strategy.displayName) + " · " + localizedText("平均胜出耗时 ${formatMs(item.avgWinnerElapsedMs)}")
    ) {
        ProviderStatsTrailing(
            protocol = provider?.protocol,
            value = localizedText("${item.wins} 次")
        )
    }
}

@Composable
private fun SmartSelectionItem(
    item: SmartSelectionStats,
    provider: DnsProvider?
) {
    SettingsItem(
        title = provider?.name ?: item.providerName,
        subtitle = localizedText("首选命中 ${formatPercent(item.selectedSuccessRate)} · 平均首选耗时 ${formatMs(item.avgSelectedElapsedMs)}")
    ) {
        ProviderStatsTrailing(
            protocol = provider?.protocol,
            value = localizedText("${item.selectedCount} 次")
        )
    }
}

@Composable
private fun ProviderStatsTrailing(
    protocol: DnsProtocol?,
    value: String
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        protocol?.let {
            DnsProtocolBadge(protocol = it)
        }
        Text(
            text = value,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

private fun formatPercent(value: Double): String {
    return String.format(Locale.getDefault(), "%.1f%%", value * 100.0)
}

private fun formatMs(value: Double): String {
    return "${value.toInt()} ms"
}

private const val MAX_PROVIDER_ROWS = 10
