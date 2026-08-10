package com.haoze.dnssr.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Apps
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
import com.haoze.dnssr.data.AppInterceptionStatsRange
import com.haoze.dnssr.ui.components.SettingsCornerShape
import com.haoze.dnssr.ui.components.SettingsGroup
import com.haoze.dnssr.ui.components.SettingsGroupTitle
import com.haoze.dnssr.ui.components.SettingsInfoText
import com.haoze.dnssr.ui.components.SettingsItem
import com.haoze.dnssr.ui.components.SettingsScaffold
import com.haoze.dnssr.ui.components.SettingsSurfaceGroup
import java.util.Locale

@Composable
fun AppInterceptionStatsScreen(
    onBack: () -> Unit,
    viewModel: AppInterceptionStatsViewModel = viewModel()
) {
    val range by viewModel.range.collectAsStateWithLifecycle()
    val summary by viewModel.summary.collectAsStateWithLifecycle()
    val items by viewModel.items.collectAsStateWithLifecycle()
    val loading by viewModel.loading.collectAsStateWithLifecycle()

    LaunchedEffect(Unit) { viewModel.refresh() }

    SettingsScaffold(
        title = localizedText("应用拦截统计"),
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
                SettingsGroup {
                    AppInterceptionRangeSelector(range, viewModel::setRange)
                }
                SettingsInfoText(localizedText("统计来自 HTTP(S) 检查日志；只有已启用 HTTPS 检查的应用会出现在列表中。"))
            }
            item {
                SettingsGroupTitle(localizedText("概览"))
                SettingsSurfaceGroup(
                    content = listOf(
                        {
                            SettingsItem(
                                title = localizedText("已记录请求"),
                                subtitle = localizedText(if (loading) "正在汇总应用请求" else "HTTP(S) 检查日志合计")
                            ) {
                                Text(formatAppStatCount(summary.total), style = MaterialTheme.typography.bodyMedium)
                            }
                        },
                        {
                            SettingsItem(
                                title = localizedText("已拦截"),
                                subtitle = localizedText("拦截率 ${formatAppStatPercent(summary.blockRate)}")
                            ) {
                                Text(
                                    formatAppStatCount(summary.blocked),
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.error
                                )
                            }
                        },
                        {
                            SettingsItem(
                                title = localizedText("已放行"),
                                subtitle = localizedText("旁路 ${formatAppStatCount(summary.bypassed)} · 异常 ${formatAppStatCount(summary.errors)}")
                            ) {
                                Text(formatAppStatCount(summary.allowed), style = MaterialTheme.typography.bodyMedium)
                            }
                        }
                    )
                )
            }
            item {
                SettingsGroupTitle(localizedText("应用程序"))
                if (items.isEmpty()) {
                    SettingsSurfaceGroup(content = listOf {
                        SettingsItem(
                            title = localizedText(if (loading) "正在加载" else "暂无应用统计"),
                            subtitle = localizedText("启用 HTTPS 检查并产生请求后，这里会显示各应用的拦截次数。")
                        ) {}
                    })
                } else {
                    SettingsSurfaceGroup(content = items.map { item -> { AppInterceptionStatRow(item) } })
                }
            }
        }
    }
}

@Composable
private fun AppInterceptionRangeSelector(
    selected: AppInterceptionStatsRange,
    onRangeClick: (AppInterceptionStatsRange) -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        AppInterceptionStatsRange.entries.forEach { range ->
            TextButton(
                onClick = { onRangeClick(range) },
                shape = SettingsCornerShape,
                colors = ButtonDefaults.textButtonColors(
                    containerColor = if (range == selected) {
                        MaterialTheme.colorScheme.primary.copy(alpha = 0.12f)
                    } else {
                        Color.Transparent
                    },
                    contentColor = if (range == selected) {
                        MaterialTheme.colorScheme.primary
                    } else {
                        MaterialTheme.colorScheme.onSurfaceVariant
                    }
                )
            ) {
                Text(localizedText(range.displayName))
            }
        }
    }
}

@Composable
private fun AppInterceptionStatRow(item: AppInterceptionStatItem) {
    SettingsItem(
        title = item.appName,
        subtitle = localizedText(
            "${item.packageName} · ${formatAppStatCount(item.total)} 请求 · 拦截 ${formatAppStatPercent(item.blockRate)}"
        ),
        leadingIcon = Icons.Default.Apps
    ) {
        Text(
            text = formatAppStatCount(item.blocked),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.error
        )
    }
}

private fun formatAppStatCount(value: Int): String = String.format(Locale.getDefault(), "%,d", value)

private fun formatAppStatPercent(value: Double): String =
    String.format(Locale.getDefault(), "%.1f%%", value * 100.0)
