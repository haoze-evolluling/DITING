package com.haoze.dnssr.ui.dashboard

import com.haoze.dnssr.util.formatMs
import com.haoze.dnssr.util.formatPercent
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.haoze.dnssr.ui.ModernLogDashboardUiState
import com.haoze.dnssr.ui.localizedText

@Composable
fun AllModeDashboard(
    state: ModernLogDashboardUiState,
    onNavigateToDnsLogs: () -> Unit,
    onNavigateToDnsCache: () -> Unit,
    onNavigateToRaceStats: () -> Unit,
    onNavigateToBootstrapStats: () -> Unit,
    onNavigateToSubscriptionInterceptionStats: () -> Unit,
    onNavigateToTrafficStats: (() -> Unit)? = null
) {
    val stats = state.dailyStats
    val race = state.race
    val bootstrap = state.bootstrap
    val raceRate = if (race.requests > 0) race.successes.toDouble() / race.requests else 0.0
    val blockRate = if (stats.total > 0) stats.blocked.toDouble() / stats.total else 0.0
    val cacheRate = if (stats.total > 0) stats.cached.toDouble() / stats.total else 0.0

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(start = 16.dp, end = 16.dp, bottom = 28.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            DashboardHero(
                title = localizedText("请求日志仪表盘"),
                description = localizedText("全部 DNS、HTTPS、缓存、竞速与规则拦截的实时概览")
            )
        }
        if (onNavigateToTrafficStats != null) {
            item {
                TrafficMonitorDashboardCard(onClick = onNavigateToTrafficStats)
            }
        }
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                MetricCard(
                    label = localizedText("今日请求"),
                    value = formatCount(stats.total),
                    valueColor = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.weight(1f)
                )
                MetricCard(
                    label = localizedText("通过"),
                    value = formatCount(stats.passed),
                    valueColor = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.weight(1f)
                )
            }
        }
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                MetricCard(
                    label = localizedText("过滤"),
                    value = formatCount(stats.blocked),
                    valueColor = MaterialTheme.colorScheme.error,
                    modifier = Modifier.weight(1f)
                )
                MetricCard(
                    label = localizedText("缓存命中"),
                    value = formatCount(stats.cached),
                    valueColor = MaterialTheme.colorScheme.tertiary,
                    modifier = Modifier.weight(1f)
                )
            }
        }
        item {
            DashboardCard {
                SectionTitle(title = localizedText("今日流量结构"), trailing = { PillLabel(localizedText("实时汇总")) })
                state.error?.let { message ->
                    ErrorBanner(message = message)
                    Spacer(modifier = Modifier.height(12.dp))
                }
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(IntrinsicSize.Min),
                    horizontalArrangement = Arrangement.spacedBy(24.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    ResultDonut(
                        stats = stats,
                        modifier = Modifier.size(128.dp)
                    )
                    Column(
                        modifier = Modifier
                            .weight(1f)
                            .fillMaxHeight()
                            .padding(end = 8.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterVertically)
                    ) {
                        LegendRow(localizedText("通过"), formatCount(stats.passed), MaterialTheme.colorScheme.primary)
                        LegendRow(localizedText("过滤"), formatCount(stats.blocked), MaterialTheme.colorScheme.error)
                        LegendRow(localizedText("失败"), formatCount(stats.error), MaterialTheme.colorScheme.error.copy(alpha = 0.7f))
                        LegendRow(localizedText("旁路"), formatCount(stats.bypassed), MaterialTheme.colorScheme.secondary)
                        LegendRow(localizedText("缓存"), formatCount(stats.cached), MaterialTheme.colorScheme.tertiary)
                    }
                }
                Spacer(modifier = Modifier.height(14.dp))
                RateRow(
                    label = localizedText("竞速成功率"),
                    value = localizedText("${formatPercent(raceRate)} · ${formatCount(race.requests)} 次 · ${formatMs(race.avgElapsedMs)}"),
                    progress = raceRate.toFloat()
                )
                Spacer(modifier = Modifier.height(14.dp))
                RateRow(
                    label = localizedText("Bootstrap 成功率"),
                    value = localizedText("${formatPercent(bootstrap.successRate)} · ${formatCount(bootstrap.attempts)} 次 · ${formatMs(bootstrap.avgElapsedMs)}"),
                    progress = bootstrap.successRate.toFloat()
                )
                Spacer(modifier = Modifier.height(14.dp))
                RateRow(
                    label = localizedText("拦截率"),
                    value = localizedText("${formatPercent(blockRate)} · ${formatCount(stats.blocked)} 次"),
                    progress = blockRate.toFloat()
                )
                Spacer(modifier = Modifier.height(14.dp))
                RateRow(
                    label = localizedText("缓存率"),
                    value = localizedText("${formatPercent(cacheRate)} · ${formatCount(stats.cached)} 次"),
                    progress = cacheRate.toFloat()
                )
            }
        }
        item {
            DashboardCard {
                SectionTitle(
                    title = localizedText("最近请求"),
                    trailing = { PillLink(text = localizedText("查看全部"), onClick = onNavigateToDnsLogs) }
                )
                if (state.recentLogs.isEmpty()) {
                    EmptyText(localizedText("暂无请求日志"))
                } else {
                    state.recentLogs.forEachIndexed { index, item ->
                        if (index > 0) ListDivider()
                        RequestLogRow(item)
                    }
                }
            }
        }
        item {
            DashboardListCard(
                title = localizedText("缓存热点"),
                emptyText = localizedText("暂无有效缓存"),
                rowCount = state.cacheEntries.size,
                trailing = { PillLink(text = localizedText("详情"), onClick = onNavigateToDnsCache) }
            ) { index ->
                CacheEntryRow(state.cacheEntries[index])
            }
        }
        item {
            DashboardListCard(
                title = localizedText("竞速胜出"),
                emptyText = localizedText("暂无竞速数据"),
                rowCount = race.winners.size,
                trailing = { PillLink(text = localizedText("详情"), onClick = onNavigateToRaceStats) }
            ) { index ->
                val item = race.winners[index]
                DashboardListRow(
                    title = item.name,
                    subtitle = localizedText("平均胜出耗时 ${formatMs(item.avgElapsedMs)}"),
                    tag = localizedText("${formatCount(item.wins)} 次"),
                    tagColor = MaterialTheme.colorScheme.secondary
                )
            }
        }
        item {
            DashboardListCard(
                title = localizedText("Bootstrap DNS"),
                emptyText = localizedText("暂无 Bootstrap 数据"),
                rowCount = bootstrap.ips.size,
                trailing = { PillLink(text = localizedText("详情"), onClick = onNavigateToBootstrapStats) }
            ) { index ->
                val item = bootstrap.ips[index]
                DashboardListRow(
                    title = item.name,
                    subtitle = localizedText("${item.ip} · 成功 ${formatPercent(item.successRate)} · ${formatMs(item.avgElapsedMs)}"),
                    tag = localizedText("${formatCount(item.attempts)} 次"),
                    tagColor = MaterialTheme.colorScheme.primary
                )
            }
        }
        item {
            DashboardListCard(
                title = localizedText("规则拦截"),
                emptyText = localizedText("暂无规则拦截数据"),
                rowCount = state.subscriptions.items.size,
                trailing = {
                    PillLink(
                        text = localizedText("详情"),
                        onClick = onNavigateToSubscriptionInterceptionStats
                    )
                }
            ) { index ->
                val item = state.subscriptions.items[index]
                val status = localizedText(when {
                    item.deleted -> "已删除"
                    item.enabled -> "已启用"
                    else -> "已禁用"
                })
                DashboardListRow(
                    title = item.name,
                    subtitle = localizedText("$status · 占全部请求 ${formatPercent(item.rate)}"),
                    tag = localizedText("${formatCount(item.hits)} 次"),
                    tagColor = MaterialTheme.colorScheme.error
                )
            }
        }
    }
}

@Composable
fun FilteredModeDashboard(
    state: ModernLogDashboardUiState,
    onNavigateToDnsLogs: () -> Unit,
    onNavigateToDnsCache: () -> Unit,
    onNavigateToRaceStats: () -> Unit,
    onNavigateToBootstrapStats: () -> Unit,
    onNavigateToSubscriptionInterceptionStats: () -> Unit,
    onNavigateToTrafficStats: (() -> Unit)? = null
) {
    val stats = state.dailyStats
    val race = state.race
    val bootstrap = state.bootstrap
    val raceRate = if (race.requests > 0) race.successes.toDouble() / race.requests else 0.0
    val blockRate = if (stats.total > 0) stats.blocked.toDouble() / stats.total else 0.0

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(start = 16.dp, end = 16.dp, bottom = 28.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            DashboardHero(
                title = localizedText("重点请求仪表盘"),
                description = localizedText("DNS 与 HTTPS 拦截、错误、旁路记录及解析状态概览")
            )
        }
        if (onNavigateToTrafficStats != null) {
            item {
                TrafficMonitorDashboardCard(onClick = onNavigateToTrafficStats)
            }
        }
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                MetricCard(
                    label = localizedText("重点记录"),
                    value = formatCount(stats.total),
                    valueColor = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.weight(1f)
                )
                MetricCard(
                    label = localizedText("过滤拦截"),
                    value = formatCount(stats.blocked),
                    valueColor = MaterialTheme.colorScheme.error,
                    modifier = Modifier.weight(1f)
                )
            }
        }
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                MetricCard(
                    label = localizedText("异常失败"),
                    value = formatCount(stats.error),
                    valueColor = MaterialTheme.colorScheme.error.copy(alpha = 0.7f),
                    modifier = Modifier.weight(1f)
                )
                MetricCard(
                    label = localizedText("旁路直连"),
                    value = formatCount(stats.bypassed),
                    valueColor = MaterialTheme.colorScheme.secondary,
                    modifier = Modifier.weight(1f)
                )
            }
        }
        item {
            DashboardCard {
                SectionTitle(title = localizedText("重点流量结构"), trailing = { PillLabel(localizedText("实时汇总")) })
                state.error?.let { message ->
                    ErrorBanner(message = message)
                    Spacer(modifier = Modifier.height(12.dp))
                }
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(IntrinsicSize.Min),
                    horizontalArrangement = Arrangement.spacedBy(24.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    ResultDonut(
                        stats = stats,
                        modifier = Modifier.size(128.dp)
                    )
                    Column(
                        modifier = Modifier
                            .weight(1f)
                            .fillMaxHeight()
                            .padding(end = 8.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterVertically)
                    ) {
                        LegendRow(localizedText("过滤"), formatCount(stats.blocked), MaterialTheme.colorScheme.error)
                        LegendRow(localizedText("失败"), formatCount(stats.error), MaterialTheme.colorScheme.error.copy(alpha = 0.7f))
                        LegendRow(localizedText("旁路"), formatCount(stats.bypassed), MaterialTheme.colorScheme.secondary)
                    }
                }
                Spacer(modifier = Modifier.height(14.dp))
                RateRow(
                    label = localizedText("竞速成功率"),
                    value = localizedText("${formatPercent(raceRate)} · ${formatCount(race.requests)} 次 · ${formatMs(race.avgElapsedMs)}"),
                    progress = raceRate.toFloat()
                )
                Spacer(modifier = Modifier.height(14.dp))
                RateRow(
                    label = localizedText("Bootstrap 成功率"),
                    value = localizedText("${formatPercent(bootstrap.successRate)} · ${formatCount(bootstrap.attempts)} 次 · ${formatMs(bootstrap.avgElapsedMs)}"),
                    progress = bootstrap.successRate.toFloat()
                )
                Spacer(modifier = Modifier.height(14.dp))
                RateRow(
                    label = localizedText("拦截占比"),
                    value = localizedText("${formatPercent(blockRate)} · ${formatCount(stats.blocked)} 次"),
                    progress = blockRate.toFloat()
                )
            }
        }
        item {
            DashboardCard {
                SectionTitle(
                    title = localizedText("最近拦截与错误"),
                    trailing = { PillLink(text = localizedText("查看全部"), onClick = onNavigateToDnsLogs) }
                )
                if (state.recentLogs.isEmpty()) {
                    EmptyText(localizedText("暂无拦截或错误记录"))
                } else {
                    state.recentLogs.forEachIndexed { index, item ->
                        if (index > 0) ListDivider()
                        RequestLogRow(item)
                    }
                }
            }
        }
        item {
            DashboardListCard(
                title = localizedText("缓存热点"),
                emptyText = localizedText("暂无有效缓存"),
                rowCount = state.cacheEntries.size,
                trailing = { PillLink(text = localizedText("详情"), onClick = onNavigateToDnsCache) }
            ) { index ->
                CacheEntryRow(state.cacheEntries[index])
            }
        }
        item {
            DashboardListCard(
                title = localizedText("竞速胜出"),
                emptyText = localizedText("暂无竞速数据"),
                rowCount = race.winners.size,
                trailing = { PillLink(text = localizedText("详情"), onClick = onNavigateToRaceStats) }
            ) { index ->
                val item = race.winners[index]
                DashboardListRow(
                    title = item.name,
                    subtitle = localizedText("平均胜出耗时 ${formatMs(item.avgElapsedMs)}"),
                    tag = localizedText("${formatCount(item.wins)} 次"),
                    tagColor = MaterialTheme.colorScheme.secondary
                )
            }
        }
        item {
            DashboardListCard(
                title = localizedText("Bootstrap DNS"),
                emptyText = localizedText("暂无 Bootstrap 数据"),
                rowCount = bootstrap.ips.size,
                trailing = { PillLink(text = localizedText("详情"), onClick = onNavigateToBootstrapStats) }
            ) { index ->
                val item = bootstrap.ips[index]
                DashboardListRow(
                    title = item.name,
                    subtitle = localizedText("${item.ip} · 成功 ${formatPercent(item.successRate)} · ${formatMs(item.avgElapsedMs)}"),
                    tag = localizedText("${formatCount(item.attempts)} 次"),
                    tagColor = MaterialTheme.colorScheme.primary
                )
            }
        }
        item {
            DashboardListCard(
                title = localizedText("规则拦截"),
                emptyText = localizedText("暂无规则拦截数据"),
                rowCount = state.subscriptions.items.size,
                trailing = {
                    PillLink(
                        text = localizedText("详情"),
                        onClick = onNavigateToSubscriptionInterceptionStats
                    )
                }
            ) { index ->
                val item = state.subscriptions.items[index]
                val status = localizedText(when {
                    item.deleted -> "已删除"
                    item.enabled -> "已启用"
                    else -> "已禁用"
                })
                DashboardListRow(
                    title = item.name,
                    subtitle = localizedText("$status · 占全部请求 ${formatPercent(item.rate)}"),
                    tag = localizedText("${formatCount(item.hits)} 次"),
                    tagColor = MaterialTheme.colorScheme.error
                )
            }
        }
    }
}

@Composable
fun OffModeDashboard(
    state: ModernLogDashboardUiState,
    onNavigateToDnsCache: () -> Unit,
    onNavigateToRaceStats: () -> Unit,
    onNavigateToBootstrapStats: () -> Unit,
    onNavigateToTrafficStats: (() -> Unit)? = null
) {
    val race = state.race
    val bootstrap = state.bootstrap
    val raceRate = if (race.requests > 0) race.successes.toDouble() / race.requests else 0.0

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(start = 16.dp, end = 16.dp, bottom = 28.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            DashboardHero(
                title = localizedText("服务状态与解析概览"),
                description = localizedText("当前处于隐私模式，不记录请求明细。DNS 缓存、并发竞速与网络流量监控仍正常运行。")
            )
        }
        item {
            DashboardCard {
                SectionTitle(
                    title = localizedText("隐私模式保护中"),
                    trailing = { PillLabel(localizedText("日志已关闭")) }
                )
                Text(
                    text = localizedText("重新开启日志后，仪表盘将从新产生的请求开始统计。当前各类解析服务与缓存热点均正常工作。"),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
        if (onNavigateToTrafficStats != null) {
            item {
                TrafficMonitorDashboardCard(onClick = onNavigateToTrafficStats)
            }
        }
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                MetricCard(
                    label = localizedText("有效缓存"),
                    value = formatCount(state.totalCacheEntries),
                    valueColor = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.weight(1f)
                )
                MetricCard(
                    label = localizedText("累计缓存命中"),
                    value = formatCount(state.totalCacheHits),
                    valueColor = MaterialTheme.colorScheme.tertiary,
                    modifier = Modifier.weight(1f)
                )
            }
        }
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                MetricCard(
                    label = localizedText("并发竞速请求"),
                    value = formatCount(race.requests),
                    valueColor = MaterialTheme.colorScheme.secondary,
                    modifier = Modifier.weight(1f)
                )
                MetricCard(
                    label = localizedText("Bootstrap 尝试"),
                    value = formatCount(bootstrap.attempts),
                    valueColor = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.weight(1f)
                )
            }
        }
        item {
            DashboardCard {
                SectionTitle(
                    title = localizedText("解析效能概况"),
                    trailing = { PillLabel(localizedText("实时统计")) }
                )
                RateRow(
                    label = localizedText("竞速成功率"),
                    value = localizedText("${formatPercent(raceRate)} · ${formatCount(race.requests)} 次 · ${formatMs(race.avgElapsedMs)}"),
                    progress = raceRate.toFloat()
                )
                Spacer(modifier = Modifier.height(14.dp))
                RateRow(
                    label = localizedText("Bootstrap 成功率"),
                    value = localizedText("${formatPercent(bootstrap.successRate)} · ${formatCount(bootstrap.attempts)} 次 · ${formatMs(bootstrap.avgElapsedMs)}"),
                    progress = bootstrap.successRate.toFloat()
                )
            }
        }
        item {
            DashboardListCard(
                title = localizedText("缓存热点"),
                emptyText = localizedText("暂无有效缓存"),
                rowCount = state.cacheEntries.size,
                trailing = { PillLink(text = localizedText("详情"), onClick = onNavigateToDnsCache) }
            ) { index ->
                CacheEntryRow(state.cacheEntries[index])
            }
        }
        item {
            DashboardListCard(
                title = localizedText("竞速胜出"),
                emptyText = localizedText("暂无竞速数据"),
                rowCount = race.winners.size,
                trailing = { PillLink(text = localizedText("详情"), onClick = onNavigateToRaceStats) }
            ) { index ->
                val item = race.winners[index]
                DashboardListRow(
                    title = item.name,
                    subtitle = localizedText("平均胜出耗时 ${formatMs(item.avgElapsedMs)}"),
                    tag = localizedText("${formatCount(item.wins)} 次"),
                    tagColor = MaterialTheme.colorScheme.secondary
                )
            }
        }
        item {
            DashboardListCard(
                title = localizedText("Bootstrap DNS"),
                emptyText = localizedText("暂无 Bootstrap 数据"),
                rowCount = bootstrap.ips.size,
                trailing = { PillLink(text = localizedText("详情"), onClick = onNavigateToBootstrapStats) }
            ) { index ->
                val item = bootstrap.ips[index]
                DashboardListRow(
                    title = item.name,
                    subtitle = localizedText("${item.ip} · 成功 ${formatPercent(item.successRate)} · ${formatMs(item.avgElapsedMs)}"),
                    tag = localizedText("${formatCount(item.attempts)} 次"),
                    tagColor = MaterialTheme.colorScheme.primary
                )
            }
        }
    }
}
