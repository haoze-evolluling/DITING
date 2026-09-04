package com.haoze.dnssr.ui

import com.haoze.dnssr.util.formatPercent

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
import com.haoze.dnssr.data.SubscriptionInterceptionStatsRange
import com.haoze.dnssr.ui.components.SettingsGroupTitle
import com.haoze.dnssr.ui.components.SettingsCornerShape
import com.haoze.dnssr.ui.components.SettingsInfoText
import com.haoze.dnssr.ui.components.SettingsItem
import com.haoze.dnssr.ui.components.SettingsScaffold
import com.haoze.dnssr.ui.components.SettingsSurfaceGroup

@Composable
fun SubscriptionInterceptionStatsScreen(
    onBack: () -> Unit,
    viewModel: SubscriptionInterceptionStatsViewModel = viewModel()
) {
    val range by viewModel.range.collectAsStateWithLifecycle()
    val totalRequests by viewModel.totalRequests.collectAsStateWithLifecycle()
    val items by viewModel.items.collectAsStateWithLifecycle()
    val loading by viewModel.loading.collectAsStateWithLifecycle()

    NavigationSettledEffect { viewModel.refresh() }

    SettingsScaffold(
        title = localizedText("订阅规则拦截率"),
        onBack = onBack,
        actions = {
            IconButton(onClick = viewModel::refresh) {
            Icon(Icons.Default.Refresh, contentDescription = localizedText("刷新"))
            }
        }
    ) { innerPadding ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(innerPadding),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            item {
                SettingsGroupTitle(localizedText("时间范围"))
                SettingsSurfaceGroup(
                    content = listOf {
                        SubscriptionInterceptionRangeSelector(range, viewModel::setRange)
                    }
                )
                SettingsInfoText(localizedText("拦截率为所选时间范围内，该订阅拦截请求数占全部已记录请求（DNS + HTTPS）的比例。"))
            }
            item {
        SettingsGroupTitle(localizedText("概览"))
                SettingsSurfaceGroup(content = listOf {
                    SettingsItem(
            title = localizedText("全部已记录请求"),
                        subtitle = localizedText(if (loading) "正在加载统计数据" else "DNS 与 HTTPS 日志合计，含通过、屏蔽和失败")
                    ) {
                        Text("$totalRequests", style = MaterialTheme.typography.bodyMedium)
                    }
                })
            }
            item {
        SettingsGroupTitle(localizedText("屏蔽订阅"))
                if (items.isEmpty()) {
                    SettingsSurfaceGroup(content = listOf {
                        SettingsItem(
                            title = localizedText(if (loading) "正在加载" else "暂无屏蔽订阅"),
            subtitle = localizedText("导入屏蔽订阅并产生 DNS 或 HTTPS 请求后，此处将显示其拦截率。")
                        )
                    })
                } else {
                    SettingsSurfaceGroup(
                        content = items.map { item -> { SubscriptionInterceptionItem(item) } }
                    )
                }
            }
        }
    }
}

@Composable
private fun SubscriptionInterceptionRangeSelector(
    selected: SubscriptionInterceptionStatsRange,
    onRangeClick: (SubscriptionInterceptionStatsRange) -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        SubscriptionInterceptionStatsRange.entries.forEach { range ->
            val selectedColor = MaterialTheme.colorScheme.primary
            TextButton(
                onClick = { onRangeClick(range) },
                shape = SettingsCornerShape,
                colors = ButtonDefaults.textButtonColors(
                    containerColor = if (range == selected) selectedColor.copy(alpha = 0.12f) else Color.Transparent,
                    contentColor = if (range == selected) selectedColor else MaterialTheme.colorScheme.onSurfaceVariant
                )
            ) { Text(localizedText(range.displayName)) }
        }
    }
}

@Composable
private fun SubscriptionInterceptionItem(item: SubscriptionInterceptionStatItem) {
    val state = localizedText(when {
        item.deleted -> "已删除"
        item.enabled -> "已启用"
        else -> "已禁用"
    })
    SettingsItem(
        title = item.name,
            subtitle = localizedText("$state | 拦截 ${item.hits} 次 | ${formatPercent(item.rate)}")
    ) {
        Text(
            text = formatPercent(item.rate),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

