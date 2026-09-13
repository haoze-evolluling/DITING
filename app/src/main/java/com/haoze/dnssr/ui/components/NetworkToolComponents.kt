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
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.VerticalDivider
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
 * Shared components for the network diagnostics module: segmented options, run buttons, stat bands, status headers, key-value rows, etc.
 * Used only by the network diagnostics sections so their styling stays independent of the global settings components.
 */

/**
 * Single-select segmented button row for small mutually exclusive option sets, such as the ping count, record type, and DNS server mode.
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
 * Primary action button for the tools; embeds a small progress indicator while running to show that a task is in progress.
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
 * Data cell in a stat band; falls back to onSurface when [valueColor] is null.
 */
data class NetworkToolStat(
    val label: String,
    val value: String,
    val valueColor: Color? = null
)

/**
 * Stat band: equally divided cells for key figures (e.g. min/avg/max latency), easier to scan than a run of inline text.
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
                    VerticalDivider(
                        modifier = Modifier.height(24.dp),
                        thickness = 1.dp,
                        color = MaterialTheme.colorScheme.outlineVariant
                    )
                }
            }
        }
    }
}

/**
 * Result status header: success/failure icon + title + supporting description.
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
 * Sub-section label within a group (e.g. 'Resolved IP', 'Per-packet details').
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
 * Key-value info row: label on the left, value on the right.
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
 * Copyable value row: tapping anywhere on the row copies it, with a copy icon on the right; used for text that needs to be taken elsewhere, such as IP addresses.
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
