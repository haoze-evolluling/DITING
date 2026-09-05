package com.haoze.dnssr.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Button
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import com.haoze.dnssr.ui.localizedText
import java.util.Locale
import kotlin.math.roundToInt

/**
 * 网络诊断模块专用组件：分段选项、运行按钮、统计带、状态头与键值行等。
 * 仅由网络诊断各分区使用，避免影响全局设置组件的风格。
 */

/**
 * 单选分段按钮行：用于 Ping 次数、记录类型、DNS 服务器模式等少量互斥选项。
 */
@Composable
fun NetworkToolSegmentedRow(
    options: List<String>,
    selectedIndex: Int,
    onSelect: (Int) -> Unit,
    modifier: Modifier = Modifier
) {
    SingleChoiceSegmentedButtonRow(modifier = modifier.fillMaxWidth()) {
        options.forEachIndexed { index, option ->
            SegmentedButton(
                selected = selectedIndex == index,
                onClick = { onSelect(index) },
                shape = SegmentedButtonDefaults.itemShape(index = index, count = options.size),
                label = {
                    Text(
                        text = localizedText(option),
                        maxLines = 1
                    )
                }
            )
        }
    }
}

/**
 * 工具主操作按钮：运行中内嵌小型进度指示器，告知任务正在进行。
 */
@Composable
fun NetworkToolRunButton(
    running: Boolean,
    runningLabel: String,
    idleLabel: String,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    onClick: () -> Unit
) {
    Button(
        onClick = onClick,
        modifier = modifier.fillMaxWidth(),
        enabled = enabled && !running,
        shape = SettingsCornerShape
    ) {
        if (running) {
            CircularProgressIndicator(
                modifier = Modifier.size(16.dp),
                strokeWidth = 2.dp,
                color = MaterialTheme.colorScheme.onPrimary
            )
            Spacer(Modifier.width(8.dp))
        }
        Text(text = localizedText(if (running) runningLabel else idleLabel))
    }
}

/**
 * 统计带数据项；[valueColor] 为空时使用 onSurface。
 */
data class NetworkToolStat(
    val label: String,
    val value: String,
    val valueColor: Color? = null
)

/**
 * 统计带：等分单元展示关键数值（如最小/平均/最大时延），比连排文字更易扫读。
 */
@Composable
fun NetworkToolStatBand(
    stats: List<NetworkToolStat>,
    modifier: Modifier = Modifier
) {
    if (stats.isEmpty()) return
    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(12.dp),
        color = MaterialTheme.colorScheme.surfaceContainerHigh
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            stats.forEachIndexed { index, stat ->
                Column(
                    modifier = Modifier.weight(1f),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(2.dp)
                ) {
                    Text(
                        text = stat.value,
                        style = MaterialTheme.typography.titleMedium,
                        color = stat.valueColor ?: MaterialTheme.colorScheme.onSurface
                    )
                    Text(
                        text = localizedText(stat.label),
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                if (index != stats.lastIndex) {
                    Box(
                        modifier = Modifier
                            .width(1.dp)
                            .height(24.dp)
                            .background(MaterialTheme.colorScheme.outlineVariant)
                    )
                }
            }
        }
    }
}

/**
 * 结果状态头：成功/失败图标 + 标题 + 补充说明。
 */
@Composable
fun NetworkToolResultHeader(
    success: Boolean,
    title: String,
    subtitle: String? = null,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                imageVector = if (success) Icons.Filled.CheckCircle else Icons.Filled.ErrorOutline,
                contentDescription = null,
                tint = if (success) {
                    MaterialTheme.colorScheme.primary
                } else {
                    MaterialTheme.colorScheme.error
                },
                modifier = Modifier.size(20.dp)
            )
            Text(
                text = localizedText(title),
                style = MaterialTheme.typography.titleMedium,
                color = if (success) {
                    MaterialTheme.colorScheme.onSurface
                } else {
                    MaterialTheme.colorScheme.error
                }
            )
        }
        subtitle?.let {
            Text(
                text = it,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

/**
 * 分组内小节标签（如「解析 IP」「逐包明细」）。
 */
@Composable
fun NetworkToolSectionLabel(
    text: String,
    modifier: Modifier = Modifier
) {
    Text(
        text = localizedText(text),
        style = MaterialTheme.typography.labelLarge,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = modifier.fillMaxWidth()
    )
}

/**
 * 键值信息行：左侧标签、右侧值。
 */
@Composable
fun NetworkToolInfoRow(
    label: String,
    value: String,
    modifier: Modifier = Modifier,
    valueColor: Color = MaterialTheme.colorScheme.onSurface
) {
    Row(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = localizedText(label),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Text(
            text = value,
            style = MaterialTheme.typography.bodyMedium,
            fontFamily = FontFamily.Monospace,
            color = valueColor,
            modifier = Modifier.weight(1f)
        )
    }
}

/**
 * 可复制值行：整行点击复制，右侧带复制图标，用于 IP 地址等需要取用的文本。
 */
@Composable
fun NetworkToolCopyValueRow(
    value: String,
    copyLabel: String,
    modifier: Modifier = Modifier,
    onCopy: () -> Unit
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .clickable(onClick = onCopy),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = value,
            style = MaterialTheme.typography.bodyMedium,
            fontFamily = FontFamily.Monospace,
            color = MaterialTheme.colorScheme.onSurface,
            modifier = Modifier.weight(1f)
        )
        IconButton(onClick = onCopy) {
            Icon(
                imageVector = Icons.Filled.ContentCopy,
                contentDescription = localizedText(copyLabel),
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(16.dp)
            )
        }
    }
}

/**
 * 组内横向细分隔线。
 */
@Composable
fun NetworkToolDivider(modifier: Modifier = Modifier) {
    HorizontalDivider(
        modifier = modifier.fillMaxWidth(),
        thickness = 0.5.dp,
        color = MaterialTheme.colorScheme.outlineVariant
    )
}

internal fun formatMsValue(value: Double?): String {
    if (value == null) return "-"
    return if (value >= 100) {
        "${value.roundToInt()} ms"
    } else {
        String.format(Locale.US, "%.1f ms", value)
    }
}

internal fun formatLossPercent(loss: Double): String {
    return if (loss % 1.0 == 0.0) {
        "${loss.toInt()}%"
    } else {
        String.format(Locale.US, "%.1f%%", loss)
    }
}
