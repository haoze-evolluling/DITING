package com.haoze.dnssr.ui.traffic

import com.haoze.dnssr.util.formatBytes

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.core.graphics.drawable.toBitmap
import com.haoze.dnssr.ui.components.AppAlertDialog
import com.haoze.dnssr.ui.components.SettingsCornerShape
import com.haoze.dnssr.ui.localizedText

@Composable
internal fun AppTrafficDetailDialog(
    detail: AppDetailTrafficState,
    onDismiss: () -> Unit
) {
    val context = LocalContext.current
    val colors = MaterialTheme.colorScheme
    val appIcon = remember(detail.packageName) {
        runCatching { context.packageManager.getApplicationIcon(detail.packageName) }.getOrNull()
    }

    AppAlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                if (appIcon != null) {
                    val bitmap = remember(appIcon) { appIcon.toBitmap(96, 96).asImageBitmap() }
                    Image(
                        bitmap = bitmap,
                        contentDescription = null,
                        modifier = Modifier.size(32.dp)
                    )
                }
                Column {
                    Text(
                        text = detail.appName,
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    Text(
                        text = detail.packageName,
                        style = MaterialTheme.typography.labelSmall,
                        color = colors.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            }
        },
        text = {
            Column(
                modifier = Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Card(
                    shape = SettingsCornerShape,
                    colors = CardDefaults.cardColors(containerColor = colors.surfaceVariant.copy(alpha = 0.4f)),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Column(
                        modifier = Modifier.padding(12.dp),
                        verticalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        DetailMetricRow(
                            label = localizedText("今日消耗"),
                            totalBytes = detail.todayTxBytes + detail.todayRxBytes,
                            rxBytes = detail.todayRxBytes,
                            txBytes = detail.todayTxBytes
                        )
                        DetailMetricRow(
                            label = localizedText("本次会话"),
                            totalBytes = detail.sessionTxBytes + detail.sessionRxBytes,
                            rxBytes = detail.sessionRxBytes,
                            txBytes = detail.sessionTxBytes
                        )
                        DetailMetricRow(
                            label = localizedText("历史累计"),
                            totalBytes = detail.totalHistoryTxBytes + detail.totalHistoryRxBytes,
                            rxBytes = detail.totalHistoryRxBytes,
                            txBytes = detail.totalHistoryTxBytes
                        )
                    }
                }

                if (detail.dailyRecords.isNotEmpty()) {
                    Text(
                        text = localizedText("历史日消耗记录"),
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.Bold
                    )
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(160.dp)
                    ) {
                        LazyColumn(
                            modifier = Modifier.fillMaxSize(),
                            verticalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            items(detail.dailyRecords) { record ->
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.SpaceBetween,
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Text(
                                        text = record.date,
                                        style = MaterialTheme.typography.bodyMedium,
                                        color = colors.onSurfaceVariant
                                    )
                                    Column(
                                        horizontalAlignment = Alignment.End,
                                        verticalArrangement = Arrangement.spacedBy(2.dp)
                                    ) {
                                        Text(
                                            text = formatBytes(record.txBytes + record.rxBytes),
                                            style = MaterialTheme.typography.bodyMedium,
                                            fontWeight = FontWeight.SemiBold,
                                            color = colors.onSurface
                                        )
                                        Text(
                                            text = "↓ " + formatBytes(record.rxBytes) + "  ↑ " + formatBytes(record.txBytes),
                                            style = MaterialTheme.typography.labelSmall,
                                            color = colors.onSurfaceVariant.copy(alpha = 0.8f)
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) {
                Text(localizedText("关闭"))
            }
        }
    )
}

@Composable
private fun DetailMetricRow(
    label: String,
    totalBytes: Long,
    rxBytes: Long,
    txBytes: Long
) {
    val colors = MaterialTheme.colorScheme
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.bodyMedium,
            color = colors.onSurfaceVariant
        )
        Column(
            horizontalAlignment = Alignment.End,
            verticalArrangement = Arrangement.spacedBy(2.dp)
        ) {
            Text(
                text = formatBytes(totalBytes),
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold,
                color = colors.onSurface
            )
            Text(
                text = "↓ " + formatBytes(rxBytes) + "  ↑ " + formatBytes(txBytes),
                style = MaterialTheme.typography.labelSmall,
                color = colors.onSurfaceVariant.copy(alpha = 0.8f)
            )
        }
    }
}
