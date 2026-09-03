package com.haoze.dnssr.ui.dashboard

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
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
import com.haoze.dnssr.ui.DashboardCacheEntryItem
import com.haoze.dnssr.ui.DashboardDailyStats
import com.haoze.dnssr.ui.DashboardRequestLogItem
import com.haoze.dnssr.ui.components.SettingsCornerShape
import com.haoze.dnssr.ui.localizedText
import com.haoze.dnssr.vpn.traffic.TrafficStatsManager

import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width

val DashboardCardShape = SettingsCornerShape
val DashboardPillShape = SettingsCornerShape
val DashboardTagShape = SettingsCornerShape

@Composable
fun DashboardHero(title: String, description: String) {
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
fun MetricCard(
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
fun TopBorderMetricCard(
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
fun DashboardCard(
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
fun SectionTitle(
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
fun PillLabel(text: String) {
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
fun PillLink(text: String, onClick: () -> Unit) {
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
fun LegendRow(label: String, value: String, valueColor: Color) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.weight(1f, fill = false)
        ) {
            Box(
                modifier = Modifier
                    .size(7.dp)
                    .clip(CircleShape)
                    .background(valueColor)
            )
            Spacer(modifier = Modifier.width(8.dp))
            Text(
                text = label,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurface,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
        Spacer(modifier = Modifier.width(16.dp))
        Text(
            text = value,
            color = valueColor,
            fontWeight = FontWeight.Bold,
            style = MaterialTheme.typography.bodyMedium
        )
    }
}

@Composable
fun RateRow(label: String, value: String, progress: Float) {
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
fun ProgressBar(progress: Float) {
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
                .background(MaterialTheme.colorScheme.primary)
        )
    }
}

@Composable
fun ResultDonut(
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
            stats.passed to MaterialTheme.colorScheme.primary,
            stats.blocked to MaterialTheme.colorScheme.error,
            stats.error to MaterialTheme.colorScheme.error.copy(alpha = 0.7f),
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
fun RequestLogRow(item: DashboardRequestLogItem, compactTag: Boolean = false) {
    val tagColor = when (item.status) {
        "passed" -> MaterialTheme.colorScheme.primary
        "blocked" -> MaterialTheme.colorScheme.error
        "bypassed" -> MaterialTheme.colorScheme.secondary
        else -> MaterialTheme.colorScheme.error
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
fun CacheEntryRow(item: DashboardCacheEntryItem) {
    DashboardListRow(
        title = item.queryName,
        subtitle = localizedText("${item.queryType} · ${formatDuration(item.remainingSeconds)} 后过期 · ${formatCount(item.responseSize)} B"),
        tag = localizedText("${formatCount(item.hitCount)} 次"),
        tagColor = MaterialTheme.colorScheme.tertiary
    )
}

@Composable
fun DashboardListRow(
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
fun SimpleKvRow(label: String, value: String) {
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
            color = MaterialTheme.colorScheme.primary,
            modifier = Modifier
                .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.10f), SettingsCornerShape)
                .padding(horizontal = 8.dp, vertical = 4.dp)
        )
    }
}

@Composable
fun ListDivider() {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(1.dp)
            .background(MaterialTheme.colorScheme.outline.copy(alpha = 0.25f))
    )
}

@Composable
fun EmptyText(text: String) {
    Text(
        text = localizedText(text),
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(vertical = 12.dp)
    )
}

/** 带「标题 + 详情链接 + 空状态/行列表」结构的仪表盘列表卡片，三种日志模式共用。 */
@Composable
fun DashboardListCard(
    title: String,
    emptyText: String,
    rowCount: Int,
    modifier: Modifier = Modifier,
    trailing: (@Composable () -> Unit)? = null,
    rowContent: @Composable (Int) -> Unit
) {
    DashboardCard(modifier = modifier) {
        SectionTitle(title = title, trailing = trailing)
        if (rowCount == 0) {
            EmptyText(emptyText)
        } else {
            for (index in 0 until rowCount) {
                if (index > 0) ListDivider()
                rowContent(index)
            }
        }
    }
}

@Composable
fun ErrorBanner(message: String) {
    Text(
        text = localizedText(message),
        style = MaterialTheme.typography.bodyMedium,
        modifier = Modifier
            .fillMaxWidth()
            .border(
                1.dp,
                MaterialTheme.colorScheme.error.copy(alpha = 0.35f),
                SettingsCornerShape
            )
            .background(
                MaterialTheme.colorScheme.error.copy(alpha = 0.12f),
                SettingsCornerShape
            )
            .padding(12.dp)
    )
}

@Composable
fun TrafficMonitorDashboardCard(onClick: () -> Unit) {
    val trafficSnapshot by TrafficStatsManager.uiSnapshot.collectAsStateWithLifecycle()
    val colors = MaterialTheme.colorScheme

    DashboardCard {
        SectionTitle(
            title = localizedText("应用流量统计"),
            trailing = { PillLink(text = localizedText("详情"), onClick = onClick) }
        )
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clip(SettingsCornerShape)
                .clickable(onClick = onClick)
                .padding(vertical = 4.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(
                    text = localizedText("今日代理流量"),
                    style = MaterialTheme.typography.labelSmall,
                    color = colors.onSurfaceVariant
                )
                Text(
                    text = formatTrafficBytes(trafficSnapshot.todayTotalBytes),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    color = colors.primary
                )
            }
            Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(
                    text = localizedText("实时速率"),
                    style = MaterialTheme.typography.labelSmall,
                    color = colors.onSurfaceVariant
                )
                Text(
                    text = "↓ ${formatTrafficSpeed(trafficSnapshot.totalRxSpeedBps)}  ↑ ${formatTrafficSpeed(trafficSnapshot.totalTxSpeedBps)}",
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.SemiBold
                )
            }
        }
    }
}
