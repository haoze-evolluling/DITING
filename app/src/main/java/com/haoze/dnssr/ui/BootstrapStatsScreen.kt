package com.haoze.dnssr.ui

import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.haoze.dnssr.data.BootstrapIpStats
import com.haoze.dnssr.data.BootstrapOverallStats
import com.haoze.dnssr.data.BootstrapStats
import com.haoze.dnssr.data.BootstrapStatsRange
import com.haoze.dnssr.ui.components.SettingsGroupTitle
import com.haoze.dnssr.ui.components.SettingsCornerShape
import com.haoze.dnssr.ui.components.SettingsInfoText
import com.haoze.dnssr.ui.components.SettingsItem
import com.haoze.dnssr.ui.components.SettingsScaffold
import com.haoze.dnssr.ui.components.SettingsSurfaceGroup
import java.util.Locale

@Composable
fun BootstrapStatsScreen(
    onBack: () -> Unit,
    viewModel: BootstrapStatsViewModel = viewModel()
) {
    val range by viewModel.range.collectAsStateWithLifecycle()
    val stats by viewModel.stats.collectAsStateWithLifecycle()
    val loading by viewModel.loading.collectAsStateWithLifecycle()

    NavigationSettledEffect {
        viewModel.activate()
    }

    SettingsScaffold(
        title = localizedText("Bootstrap DNS 解析统计"),
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
        BootstrapStatsContent(
            stats = stats,
            range = range,
            loading = loading,
            onRangeClick = viewModel::setRange,
            modifier = Modifier.padding(innerPadding)
        )
    }
}

@Composable
private fun BootstrapStatsContent(
    stats: BootstrapStats,
    range: BootstrapStatsRange,
    loading: Boolean,
    onRangeClick: (BootstrapStatsRange) -> Unit,
    modifier: Modifier = Modifier
) {
    LazyColumn(
        modifier = modifier.fillMaxSize(),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            SettingsGroupTitle(localizedText("时间范围"))
            SettingsSurfaceGroup(
                content = listOf {
                    BootstrapRangeSelector(
                        selected = range,
                        onRangeClick = onRangeClick
                    )
                }
            )
            SettingsInfoText(localizedText("统计 Bootstrap DNS 解析加密服务商域名（DoH/DoT/DoQ）的使用情况。"))
        }

        if (stats.overall.attempts == 0) {
            item {
                SettingsGroupTitle(localizedText("统计"))
                SettingsSurfaceGroup(content = listOf {
                    SettingsItem(
                        title = localizedText(if (loading) "正在加载" else "暂无 Bootstrap 数据"),
                        subtitle = localizedText("产生真实 DNS 查询或 DNS 查询测速后，这里会显示 Bootstrap DNS 的成功率和权重。")
                    )
                })
            }
            return@LazyColumn
        }

        item {
            SettingsGroupTitle(localizedText("概览"))
            SettingsSurfaceGroup(content = listOf { OverallStatsItem(stats.overall) })
        }

        item {
            SettingsGroupTitle(localizedText("Bootstrap DNS 使用排行"))
            SettingsSurfaceGroup(
                content = stats.ipStats.map { item -> { BootstrapIpStatsItem(item) } }
            )
        }
    }
}

@Composable
private fun BootstrapRangeSelector(
    selected: BootstrapStatsRange,
    onRangeClick: (BootstrapStatsRange) -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        BootstrapStatsRange.entries.forEach { range ->
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
private fun OverallStatsItem(item: BootstrapOverallStats) {
    SettingsItem(
        title = localizedText("整体表现"),
        subtitle = localizedText("成功 ${formatPercent(item.successRate)} · 平均 ${formatMs(item.avgElapsedMs)} · 备用 ${item.fallbackUses} 次")
    ) {
        Text(
            text = localizedText("${item.attempts} 次"),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
private fun BootstrapIpStatsItem(item: BootstrapIpStats) {
    val cooldown = if (System.currentTimeMillis() < item.cooldownUntil) localizedText(" · 冷却中") else ""
    val failures = if (item.consecutiveFailures > 0) localizedText(" · 连续失败 ${item.consecutiveFailures}") else ""
    SettingsItem(
        title = item.ipName,
        subtitle = localizedText("${item.ip} · 成功 ${formatPercent(item.successRate)} · 平均 ${formatMs(item.avgElapsedMs)} · 权重 ${formatWeight(item.predictionWeight)}$cooldown$failures")
    ) {
        Text(
            text = localizedText("${item.attempts} 次"),
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

private fun formatWeight(value: Double): String {
    return String.format(Locale.getDefault(), "%.2f", value)
}
