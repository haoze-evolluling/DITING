package com.haoze.dnssr.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import java.text.NumberFormat
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.roundToInt

private val DashboardCardShape = RoundedCornerShape(8.dp)
private val DashboardPillShape = RoundedCornerShape(6.dp)
private val DashboardTagShape = RoundedCornerShape(9.dp)

private val AccentGreen = Color(0xFF34D399)
private val AccentRed = Color(0xFFDC2626)
private val AccentAmber = Color(0xFFB45309)
private val AccentCyan = Color(0xFF0891B2)
private val AccentViolet = Color(0xFFA78BFA)
private val AccentBlue = Color(0xFF2563EB)

@Composable
fun ModernLogDashboardScreen(
    onBack: () -> Unit,
    onNavigateToDnsLogs: () -> Unit,
    onNavigateToDnsCache: () -> Unit,
    onNavigateToRaceStats: () -> Unit,
    onNavigateToBootstrapStats: () -> Unit,
    onNavigateToSubscriptionInterceptionStats: () -> Unit,
    onNavigateToAppInterceptionStats: () -> Unit,
    viewModel: ModernLogDashboardViewModel = viewModel()
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val colors = MaterialTheme.colorScheme

    LaunchedEffect(viewModel) {
        viewModel.refresh()
    }

    val subtitle = remember(uiState.logMode, uiState.generatedAt, uiState.hasData) {
        val modeLabel = when (uiState.logMode) {
            DnsLogMode.ALL -> "记录全部请求"
            DnsLogMode.BLOCKED_AND_ERRORS -> "仅记录拦截与错误"
            DnsLogMode.OFF -> "请求日志已关闭"
        }
        if (!uiState.hasData || uiState.generatedAt <= 0L) {
            modeLabel
        } else {
            val time = formatClockTime(uiState.generatedAt)
            when (uiState.logMode) {
                DnsLogMode.ALL -> "$modeLabel · 更新于 $time"
                else -> "$modeLabel · $time"
            }
        }
    }

    Scaffold(
        containerColor = colors.background,
        topBar = {
            DashboardTopBar(
                subtitle = subtitle,
                onBack = onBack,
                onRefresh = viewModel::refresh
            )
        }
    ) { innerPadding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .background(colors.background)
        ) {
            if (uiState.loading && !uiState.hasData) {
                Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center
                ) {
                    CircularProgressIndicator()
                }
            } else {
                when (uiState.logMode) {
                    DnsLogMode.ALL -> AllModeDashboard(
                        state = uiState,
                        onNavigateToDnsLogs = onNavigateToDnsLogs,
                        onNavigateToDnsCache = onNavigateToDnsCache,
                        onNavigateToRaceStats = onNavigateToRaceStats,
                        onNavigateToBootstrapStats = onNavigateToBootstrapStats,
                        onNavigateToSubscriptionInterceptionStats = onNavigateToSubscriptionInterceptionStats,
                        onNavigateToAppInterceptionStats = onNavigateToAppInterceptionStats
                    )
                    DnsLogMode.BLOCKED_AND_ERRORS -> FilteredModeDashboard(
                        state = uiState,
                        onNavigateToAppInterceptionStats = onNavigateToAppInterceptionStats
                    )
                    DnsLogMode.OFF -> OffModeDashboard(
                        state = uiState,
                        onNavigateToAppInterceptionStats = onNavigateToAppInterceptionStats
                    )
                }
            }
        }
    }
}

@Composable
private fun DashboardTopBar(
    subtitle: String,
    onBack: () -> Unit,
    onRefresh: () -> Unit
) {
    val colors = MaterialTheme.colorScheme
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .statusBarsPadding()
            .padding(horizontal = 16.dp, vertical = 8.dp)
            .border(1.dp, colors.outline.copy(alpha = 0.5f), DashboardCardShape),
        color = colors.surfaceVariant.copy(alpha = 0.5f),
        shape = DashboardCardShape,
        shadowElevation = 0.dp,
        tonalElevation = 0.dp
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 4.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            IconButton(onClick = onBack) {
                Icon(
                    imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                    contentDescription = localizedText("返回")
                )
            }
            Column(
                modifier = Modifier
                    .weight(1f)
                    .padding(horizontal = 4.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text(
                    text = localizedText("日志仪表盘"),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Text(
                    text = localizedText(subtitle),
                    style = MaterialTheme.typography.bodySmall,
                    color = colors.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
            IconButton(onClick = onRefresh) {
                Icon(
                    imageVector = Icons.Default.Refresh,
                    contentDescription = localizedText("刷新")
                )
            }
        }
    }
}

@Composable
private fun AllModeDashboard(
    state: ModernLogDashboardUiState,
    onNavigateToDnsLogs: () -> Unit,
    onNavigateToDnsCache: () -> Unit,
    onNavigateToRaceStats: () -> Unit,
    onNavigateToBootstrapStats: () -> Unit,
    onNavigateToSubscriptionInterceptionStats: () -> Unit,
    onNavigateToAppInterceptionStats: () -> Unit
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
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                MetricCard(
                    label = localizedText("今日请求"),
                    value = formatCount(stats.total),
                    valueColor = AccentCyan,
                    modifier = Modifier.weight(1f)
                )
                MetricCard(
                    label = localizedText("通过"),
                    value = formatCount(stats.passed),
                    valueColor = AccentGreen,
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
                    valueColor = AccentRed,
                    modifier = Modifier.weight(1f)
                )
                MetricCard(
                    label = localizedText("缓存命中"),
                    value = formatCount(stats.cached),
                    valueColor = AccentBlue,
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
                    horizontalArrangement = Arrangement.spacedBy(14.dp)
                ) {
                    ResultDonut(
                        stats = stats,
                        modifier = Modifier.size(128.dp)
                    )
                    Column(
                        modifier = Modifier
                            .weight(1f)
                            .fillMaxHeight(),
                        verticalArrangement = Arrangement.SpaceBetween
                    ) {
                        LegendRow(localizedText("通过"), formatCount(stats.passed), AccentGreen)
                        LegendRow(localizedText("过滤"), formatCount(stats.blocked), AccentRed)
                        LegendRow(localizedText("失败"), formatCount(stats.error), AccentAmber)
                        LegendRow(localizedText("旁路"), formatCount(stats.bypassed), AccentViolet)
                        LegendRow(localizedText("缓存"), formatCount(stats.cached), AccentBlue)
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
            DashboardCard {
                SectionTitle(
                    title = localizedText("缓存热点"),
                    trailing = { PillLink(text = localizedText("详情"), onClick = onNavigateToDnsCache) }
                )
                if (state.cacheEntries.isEmpty()) {
                    EmptyText(localizedText("暂无有效缓存"))
                } else {
                    state.cacheEntries.forEachIndexed { index, item ->
                        if (index > 0) ListDivider()
                        CacheEntryRow(item)
                    }
                }
            }
        }
        item {
            DashboardCard {
                SectionTitle(
                    title = localizedText("竞速胜出"),
                    trailing = { PillLink(text = localizedText("详情"), onClick = onNavigateToRaceStats) }
                )
                if (race.winners.isEmpty()) {
                    EmptyText(localizedText("暂无竞速数据"))
                } else {
                    race.winners.forEachIndexed { index, item ->
                        if (index > 0) ListDivider()
                        DashboardListRow(
                            title = item.name,
                            subtitle = localizedText("平均胜出耗时 ${formatMs(item.avgElapsedMs)}"),
                            tag = localizedText("${formatCount(item.wins)} 次"),
                            tagColor = AccentViolet
                        )
                    }
                }
            }
        }
        item {
            DashboardCard {
                SectionTitle(
                    title = localizedText("Bootstrap DNS"),
                    trailing = { PillLink(text = localizedText("详情"), onClick = onNavigateToBootstrapStats) }
                )
                if (bootstrap.ips.isEmpty()) {
                    EmptyText(localizedText("暂无 Bootstrap 数据"))
                } else {
                    bootstrap.ips.forEachIndexed { index, item ->
                        if (index > 0) ListDivider()
                        DashboardListRow(
                            title = item.name,
                            subtitle = localizedText("${item.ip} · 成功 ${formatPercent(item.successRate)} · ${formatMs(item.avgElapsedMs)}"),
                            tag = localizedText("${formatCount(item.attempts)} 次"),
                            tagColor = AccentCyan
                        )
                    }
                }
            }
        }
        item {
            DashboardCard {
                SectionTitle(
                    title = localizedText("规则拦截"),
                    trailing = {
                        PillLink(
                            text = localizedText("详情"),
                            onClick = onNavigateToSubscriptionInterceptionStats
                        )
                    }
                )
                if (state.subscriptions.items.isEmpty()) {
                    EmptyText(localizedText("暂无规则拦截数据"))
                } else {
                    state.subscriptions.items.forEachIndexed { index, item ->
                        if (index > 0) ListDivider()
                        val status = localizedText(when {
                            item.deleted -> "已删除"
                            item.enabled -> "已启用"
                            else -> "已禁用"
                        })
                        DashboardListRow(
                            title = item.name,
                            subtitle = localizedText("$status · 占全部请求 ${formatPercent(item.rate)}"),
                            tag = localizedText("${formatCount(item.hits)} 次"),
                            tagColor = AccentRed
                        )
                    }
                }
            }
        }
        item { AppInterceptionNavigationCard(onNavigateToAppInterceptionStats) }
    }
}

@Composable
private fun FilteredModeDashboard(
    state: ModernLogDashboardUiState,
    onNavigateToAppInterceptionStats: () -> Unit
) {
    val stats = state.dailyStats
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(start = 12.dp, end = 12.dp, bottom = 28.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        item {
            DashboardHero(
                title = localizedText("重点请求概览"),
                description = localizedText("仅汇总 DNS 与 HTTPS 的拦截、错误和旁路记录。")
            )
        }
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                TopBorderMetricCard(
                    label = localizedText("今日拦截"),
                    value = formatCount(stats.blocked),
                    valueColor = AccentRed,
                    borderColor = AccentRed,
                    modifier = Modifier.weight(1f)
                )
                TopBorderMetricCard(
                    label = localizedText("今日错误"),
                    value = formatCount(stats.error),
                    valueColor = AccentAmber,
                    borderColor = AccentAmber,
                    modifier = Modifier.weight(1f)
                )
                TopBorderMetricCard(
                    label = localizedText("今日旁路"),
                    value = formatCount(stats.bypassed),
                    valueColor = AccentViolet,
                    borderColor = AccentViolet,
                    modifier = Modifier.weight(1f)
                )
            }
        }
        item {
            DashboardCard(topBorderColor = MaterialTheme.colorScheme.primary) {
                SectionTitle(title = localizedText("最近重点请求"))
                if (state.recentLogs.isEmpty()) {
                    EmptyText(localizedText("暂无拦截或错误记录"))
                } else {
                    state.recentLogs.forEachIndexed { index, item ->
                        if (index > 0) ListDivider()
                        RequestLogRow(item, compactTag = true)
                    }
                }
            }
        }
        item {
            DashboardCard(topBorderColor = MaterialTheme.colorScheme.primary) {
                SectionTitle(title = localizedText("订阅拦截"))
                if (state.subscriptions.items.isEmpty()) {
                    EmptyText(localizedText("暂无订阅拦截数据"))
                } else {
                    state.subscriptions.items.forEachIndexed { index, item ->
                        if (index > 0) ListDivider()
                        SimpleKvRow(
                            label = item.name,
                            value = localizedText("${item.hits} 次")
                        )
                    }
                }
            }
        }
        item {
            DashboardCard(topBorderColor = MaterialTheme.colorScheme.primary) {
                SectionTitle(title = localizedText("解析运行状态"))
                SimpleKvRow(label = localizedText("竞速请求"), value = formatCount(state.race.requests))
                ListDivider()
                SimpleKvRow(label = localizedText("Bootstrap 尝试"), value = formatCount(state.bootstrap.attempts))
                ListDivider()
                SimpleKvRow(label = localizedText("有效缓存"), value = formatCount(state.cacheEntries.size))
            }
        }
        item { AppInterceptionNavigationCard(onNavigateToAppInterceptionStats) }
    }
}

@Composable
private fun OffModeDashboard(
    state: ModernLogDashboardUiState,
    onNavigateToAppInterceptionStats: () -> Unit
) {
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(start = 12.dp, end = 12.dp, bottom = 28.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        item {
            DashboardHero(
                title = localizedText("日志记录已暂停"),
                description = localizedText("当前不会保存 DNS 或 HTTPS 请求记录，缓存和解析服务仍正常运行。")
            )
        }
        item {
            Surface(
                modifier = Modifier
                    .fillMaxWidth()
                    .border(1.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.5f), DashboardCardShape),
                color = MaterialTheme.colorScheme.surface,
                shape = DashboardCardShape
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Text(
                        text = localizedText("隐私模式运行中"),
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold
                    )
                    Spacer(modifier = Modifier.height(6.dp))
                    Text(
                        text = localizedText("重新开启日志后，仪表盘将从新产生的请求开始统计。"),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }
        item {
            DashboardCard(topBorderColor = AccentBlue) {
                SectionTitle(title = localizedText("DNS 缓存"))
                SimpleKvRow(label = localizedText("当前有效条目"), value = formatCount(state.cacheEntries.size))
                ListDivider()
                SimpleKvRow(
                    label = localizedText("累计缓存命中"),
                    value = formatCount(state.cacheEntries.sumOf { it.hitCount })
                )
            }
        }
        item {
            DashboardCard(topBorderColor = AccentGreen) {
                SectionTitle(title = localizedText("解析运行状态"))
                SimpleKvRow(label = localizedText("竞速请求"), value = formatCount(state.race.requests))
                ListDivider()
                SimpleKvRow(label = localizedText("Bootstrap 尝试"), value = formatCount(state.bootstrap.attempts))
            }
        }
        item { AppInterceptionNavigationCard(onNavigateToAppInterceptionStats) }
    }
}

@Composable
private fun AppInterceptionNavigationCard(onNavigate: () -> Unit) {
    DashboardCard {
        SectionTitle(
            title = localizedText("应用拦截"),
            trailing = {
                PillLink(
                    text = localizedText("查看"),
                    onClick = onNavigate
                )
            }
        )
        EmptyText(localizedText("按应用汇总 HTTP(S) 请求、拦截次数和拦截率。"))
    }
}

@Composable
private fun DashboardHero(title: String, description: String) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 8.dp, bottom = 4.dp)
    ) {
        Text(
            text = title,
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold,
            fontSize = 24.sp
        )
        Spacer(modifier = Modifier.height(6.dp))
        Text(
            text = description,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
private fun MetricCard(
    label: String,
    value: String,
    valueColor: Color,
    modifier: Modifier = Modifier
) {
    DashboardCard(modifier = modifier) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = value,
            color = valueColor,
            fontSize = 28.sp,
            fontWeight = FontWeight.ExtraBold,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}

@Composable
private fun TopBorderMetricCard(
    label: String,
    value: String,
    valueColor: Color,
    borderColor: Color,
    modifier: Modifier = Modifier
) {
    DashboardCard(modifier = modifier, topBorderColor = borderColor) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(modifier = Modifier.height(5.dp))
        Text(
            text = value,
            color = valueColor,
            fontSize = 25.sp,
            fontWeight = FontWeight.Bold,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}

@Composable
private fun DashboardCard(
    modifier: Modifier = Modifier,
    topBorderColor: Color? = null,
    content: @Composable ColumnScope.() -> Unit
) {
    val colors = MaterialTheme.colorScheme
    val shape = DashboardCardShape
    Surface(
        modifier = modifier
            .fillMaxWidth()
            .border(1.dp, colors.outline.copy(alpha = 0.45f), shape),
        color = colors.surface,
        shape = shape,
        shadowElevation = 0.dp,
        tonalElevation = 0.dp
    ) {
        Column(modifier = Modifier.fillMaxWidth()) {
            if (topBorderColor != null) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(4.dp)
                        .background(topBorderColor)
                )
            }
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(16.dp),
                content = content
            )
        }
    }
}

@Composable
private fun SectionTitle(
    title: String,
    trailing: (@Composable () -> Unit)? = null
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(bottom = 14.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = title,
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
            fontSize = 16.sp,
            modifier = Modifier.weight(1f, fill = false)
        )
        if (trailing != null) {
            trailing()
        }
    }
}

@Composable
private fun PillLabel(text: String) {
    Text(
        text = localizedText(text),
        style = MaterialTheme.typography.labelSmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier
            .border(1.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.45f), DashboardPillShape)
            .background(MaterialTheme.colorScheme.surface, DashboardPillShape)
            .padding(horizontal = 8.dp, vertical = 5.dp)
    )
}

@Composable
private fun PillLink(text: String, onClick: () -> Unit) {
    Text(
        text = localizedText(text),
        style = MaterialTheme.typography.labelSmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier
            .clip(DashboardPillShape)
            .border(1.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.45f), DashboardPillShape)
            .background(MaterialTheme.colorScheme.surface, DashboardPillShape)
            .clickable(onClick = onClick)
            .padding(horizontal = 8.dp, vertical = 5.dp)
    )
}

@Composable
private fun LegendRow(label: String, value: String, valueColor: Color) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.bodyMedium,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f)
        )
        Text(
            text = value,
            color = valueColor,
            fontWeight = FontWeight.Bold,
            style = MaterialTheme.typography.bodyMedium
        )
    }
}

@Composable
private fun RateRow(label: String, value: String, progress: Float) {
    Column(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = label,
                style = MaterialTheme.typography.bodyMedium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f)
            )
            Text(
                text = value,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
        Spacer(modifier = Modifier.height(8.dp))
        ProgressBar(progress = progress.coerceIn(0f, 1f))
    }
}

@Composable
private fun ProgressBar(progress: Float) {
    val track = MaterialTheme.colorScheme.secondary.copy(alpha = 0.14f)
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(9.dp)
            .clip(RoundedCornerShape(4.dp))
            .background(track)
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth(progress)
                .fillMaxHeight()
                .clip(RoundedCornerShape(4.dp))
                .background(AccentCyan)
        )
    }
}

@Composable
private fun ResultDonut(
    stats: DashboardDailyStats,
    modifier: Modifier = Modifier
) {
    val total = stats.total.coerceAtLeast(0)
    val line = MaterialTheme.colorScheme.outline.copy(alpha = 0.35f)
    val surface = MaterialTheme.colorScheme.surface
    val onSurface = MaterialTheme.colorScheme.onSurface
    val segments = if (total == 0) {
        emptyList()
    } else {
        listOf(
            stats.passed to AccentGreen,
            stats.blocked to AccentRed,
            stats.error to AccentAmber,
            stats.bypassed to MaterialTheme.colorScheme.secondary
        ).filter { it.first > 0 }
    }
    Box(modifier = modifier, contentAlignment = Alignment.Center) {
        Canvas(modifier = Modifier.fillMaxSize()) {
            val stroke = 18.dp.toPx()
            val diameter = size.minDimension
            val topLeft = Offset((size.width - diameter) / 2f, (size.height - diameter) / 2f)
            val arcSize = Size(diameter, diameter)
            if (segments.isEmpty()) {
                drawArc(
                    color = line,
                    startAngle = -90f,
                    sweepAngle = 360f,
                    useCenter = false,
                    topLeft = topLeft,
                    size = arcSize,
                    style = Stroke(width = stroke, cap = StrokeCap.Butt)
                )
            } else {
                var start = -90f
                segments.forEach { (count, color) ->
                    val sweep = 360f * count.toFloat() / total.toFloat()
                    drawArc(
                        color = color,
                        startAngle = start,
                        sweepAngle = sweep,
                        useCenter = false,
                        topLeft = topLeft,
                        size = arcSize,
                        style = Stroke(width = stroke, cap = StrokeCap.Butt)
                    )
                    start += sweep
                }
            }
            val hole = diameter * 0.72f
            drawCircle(
                color = surface,
                radius = hole / 2f,
                center = center
            )
        }
        Text(
            text = formatCount(total),
            fontWeight = FontWeight.ExtraBold,
            fontSize = 22.sp,
            color = onSurface
        )
    }
}

@Composable
private fun RequestLogRow(item: DashboardRequestLogItem, compactTag: Boolean = false) {
    val tagColor = when (item.status) {
        "passed" -> AccentGreen
        "blocked" -> AccentRed
        "bypassed" -> AccentViolet
        else -> AccentAmber
    }
    DashboardListRow(
        title = item.name,
        subtitle = localizedText(if (compactTag) {
            "${item.source} · ${item.meta}"
        } else {
            "${formatClockTime(item.timestamp)} · ${item.source} · ${item.meta}"
        }),
        tag = localizedText(item.resultLabel),
        tagColor = tagColor
    )
}

@Composable
private fun CacheEntryRow(item: DashboardCacheEntryItem) {
    DashboardListRow(
        title = item.queryName,
        subtitle = localizedText("${item.queryType} · ${formatDuration(item.remainingSeconds)} 后过期 · ${formatCount(item.responseSize)} B"),
        tag = localizedText("${formatCount(item.hitCount)} 次"),
        tagColor = AccentBlue
    )
}

@Composable
private fun DashboardListRow(
    title: String,
    subtitle: String,
    tag: String,
    tagColor: Color
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = title,
                style = MaterialTheme.typography.bodyMedium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Spacer(modifier = Modifier.height(3.dp))
            Text(
                text = subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
        Text(
            text = tag,
            style = MaterialTheme.typography.labelSmall,
            fontWeight = FontWeight.Bold,
            color = tagColor,
            modifier = Modifier
                .background(tagColor.copy(alpha = 0.12f), DashboardTagShape)
                .padding(horizontal = 7.dp, vertical = 5.dp)
        )
    }
}

@Composable
private fun SimpleKvRow(label: String, value: String) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 11.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.bodyMedium,
            modifier = Modifier.weight(1f),
            maxLines = 2,
            overflow = TextOverflow.Ellipsis
        )
        Text(
            text = value,
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.Bold,
            color = AccentBlue,
            modifier = Modifier
                .background(AccentBlue.copy(alpha = 0.10f), RoundedCornerShape(6.dp))
                .padding(horizontal = 8.dp, vertical = 4.dp)
        )
    }
}

@Composable
private fun ListDivider() {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(1.dp)
            .background(MaterialTheme.colorScheme.outline.copy(alpha = 0.25f))
    )
}

@Composable
private fun EmptyText(text: String) {
    Text(
        text = localizedText(text),
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(vertical = 12.dp)
    )
}

@Composable
private fun ErrorBanner(message: String) {
    Text(
        text = localizedText(message),
        style = MaterialTheme.typography.bodyMedium,
        modifier = Modifier
            .fillMaxWidth()
            .border(
                1.dp,
                MaterialTheme.colorScheme.error.copy(alpha = 0.35f),
                RoundedCornerShape(12.dp)
            )
            .background(
                MaterialTheme.colorScheme.error.copy(alpha = 0.12f),
                RoundedCornerShape(12.dp)
            )
            .padding(12.dp)
    )
}

private fun formatCount(value: Int): String {
    return NumberFormat.getIntegerInstance(Locale.CHINA).format(value)
}

private fun formatClockTime(millis: Long): String {
    if (millis <= 0L) return "无"
    return SimpleDateFormat("HH:mm:ss", Locale.CHINA).format(Date(millis))
}

private fun formatPercent(value: Double): String {
    val rounded = (value * 1000.0).roundToInt() / 10.0
    return if (rounded % 1.0 == 0.0) {
        "${rounded.toInt()}%"
    } else {
        "$rounded%"
    }
}

private fun formatMs(value: Double): String {
    return "${value.roundToInt()} ms"
}

private fun formatDuration(seconds: Long): String {
    return when {
        seconds >= 3600L -> "${seconds / 3600L} 小时"
        seconds >= 60L -> "${seconds / 60L} 分钟"
        else -> "$seconds 秒"
    }
}
