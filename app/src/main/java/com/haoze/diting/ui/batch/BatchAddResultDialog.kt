package com.haoze.diting.ui.batch

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.VerticalDivider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.haoze.diting.ui.components.AppAlertDialog
import com.haoze.diting.ui.components.AppDialogButton
import com.haoze.diting.ui.components.SettingsCornerShape
import com.haoze.diting.ui.localizedText

@Composable
fun BatchAddResultDialog(
    summary: BatchValidationSummary,
    onDismiss: () -> Unit,
    onConfirm: () -> Unit
) {
    var showDetails by remember { mutableStateOf(false) }

    AppAlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(localizedText("规则校验结果")) },
        text = {
            Column(
                modifier = Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                // Unified validation summary band
                ValidationSummaryBand(
                    validCount = summary.validCount,
                    duplicateCount = summary.duplicateCount,
                    invalidCount = summary.invalidCount
                )

                if (summary.ignoredCount > 0) {
                    Text(
                        text = localizedText("已自动忽略 ${summary.ignoredCount} 行空行或注释"),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }

                // If duplicates or invalid rules exist, show expandable details section
                val totalIssues = summary.duplicateCount + summary.invalidCount
                if (totalIssues > 0) {
                    Card(
                        shape = SettingsCornerShape,
                        colors = CardDefaults.cardColors(
                            containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)
                        ),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Column(modifier = Modifier.padding(10.dp)) {
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clickable { showDetails = !showDetails }
                                    .padding(vertical = 4.dp),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Text(
                                    text = localizedText(if (showDetails) "收起异常规则明细" else "查看异常规则明细 ($totalIssues 条)"),
                                    style = MaterialTheme.typography.labelMedium,
                                    fontWeight = FontWeight.SemiBold,
                                    color = MaterialTheme.colorScheme.primary
                                )
                                Icon(
                                    imageVector = if (showDetails) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore,
                                    contentDescription = null,
                                    tint = MaterialTheme.colorScheme.primary
                                )
                            }

                            if (showDetails) {
                                Column(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .heightIn(max = 200.dp)
                                        .verticalScroll(rememberScrollState())
                                        .padding(top = 8.dp),
                                    verticalArrangement = Arrangement.spacedBy(6.dp)
                                ) {
                                    summary.invalidItems.forEach { item ->
                                        IssueItemRow(
                                            lineNo = item.lineNumber,
                                            content = item.rawLine,
                                            reason = item.reason,
                                            isError = true
                                        )
                                    }
                                    summary.duplicateItems.forEach { item ->
                                        IssueItemRow(
                                            lineNo = item.lineNumber,
                                            content = item.rawLine,
                                            reason = item.reason,
                                            isError = false
                                        )
                                    }
                                }
                            }
                        }
                    }
                }

                if (summary.validCount == 0) {
                    Text(
                        text = localizedText("未识别到任何有效的新增规则，请修改后重试。"),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.error
                    )
                } else {
                    Text(
                        text = localizedText("将添加 ${summary.validCount} 条有效规则至${summary.target.singularName}。"),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurface
                    )
                }
            }
        },
        confirmButton = {
            if (summary.validCount > 0) {
                AppDialogButton(
                    label = "确认添加 (${summary.validCount}条)",
                    onClick = onConfirm
                )
            } else {
                AppDialogButton(
                    label = "返回修改",
                    onClick = onDismiss
                )
            }
        },
        dismissButton = if (summary.validCount > 0) {
            { AppDialogButton(label = "取消", onClick = onDismiss) }
        } else null
    )
}

@Composable
private fun ValidationSummaryBand(
    validCount: Int,
    duplicateCount: Int,
    invalidCount: Int,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = SettingsCornerShape,
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.45f)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 12.dp, horizontal = 4.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            ValidationMetricColumn(
                label = "有效",
                count = validCount,
                icon = Icons.Filled.CheckCircle,
                activeColor = MaterialTheme.colorScheme.primary,
                modifier = Modifier.weight(1f)
            )
            VerticalDivider(
                modifier = Modifier.height(28.dp),
                thickness = 1.dp,
                color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f)
            )
            ValidationMetricColumn(
                label = "重复",
                count = duplicateCount,
                icon = Icons.Filled.Warning,
                activeColor = MaterialTheme.colorScheme.tertiary,
                modifier = Modifier.weight(1f)
            )
            VerticalDivider(
                modifier = Modifier.height(28.dp),
                thickness = 1.dp,
                color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f)
            )
            ValidationMetricColumn(
                label = "无效",
                count = invalidCount,
                icon = Icons.Filled.Error,
                activeColor = MaterialTheme.colorScheme.error,
                modifier = Modifier.weight(1f)
            )
        }
    }
}

@Composable
private fun ValidationMetricColumn(
    label: String,
    count: Int,
    icon: ImageVector,
    activeColor: Color,
    modifier: Modifier = Modifier
) {
    val hasCount = count > 0
    val contentColor = if (hasCount) activeColor else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.45f)
    val labelColor = if (hasCount) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f)

    Column(
        modifier = modifier,
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = contentColor,
                modifier = Modifier.size(15.dp)
            )
            Text(
                text = localizedText(label),
                style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.Medium,
                color = labelColor
            )
        }
        Text(
            text = "$count",
            style = MaterialTheme.typography.titleLarge.copy(fontSize = 20.sp),
            fontWeight = FontWeight.Bold,
            color = contentColor
        )
    }
}

@Composable
private fun IssueItemRow(
    lineNo: Int,
    content: String,
    reason: String,
    isError: Boolean
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(6.dp))
            .background(MaterialTheme.colorScheme.surface)
            .padding(horizontal = 8.dp, vertical = 6.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text(
                text = "第 $lineNo 行",
                style = MaterialTheme.typography.labelSmall,
                color = if (isError) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.tertiary,
                fontWeight = FontWeight.Medium
            )
            Text(
                text = localizedText(reason),
                style = MaterialTheme.typography.labelSmall,
                color = if (isError) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        Text(
            text = content,
            style = MaterialTheme.typography.bodySmall.copy(
                fontFamily = FontFamily.Monospace,
                fontSize = 12.sp
            ),
            color = MaterialTheme.colorScheme.onSurface,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}
