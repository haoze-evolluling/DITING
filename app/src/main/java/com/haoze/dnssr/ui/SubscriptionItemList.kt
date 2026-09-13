package com.haoze.dnssr.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.haoze.dnssr.data.entity.SubscriptionEntity
import com.haoze.dnssr.data.entity.SubscriptionImportState
import com.haoze.dnssr.data.entity.SubscriptionKind
import com.haoze.dnssr.data.entity.SubscriptionSourceType
import com.haoze.dnssr.ui.components.SettingsSurfaceGroup
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@Composable
internal fun SubscriptionItems(
    subscriptions: List<SubscriptionEntity>,
    busy: Boolean,
    importingSubscriptionId: Long?,
    progress: SubscriptionProgress,
    ruleBreakdowns: Map<Long, SubscriptionRuleBreakdown>,
    onShowUrl: (SubscriptionEntity) -> Unit,
    onShowActions: (SubscriptionEntity) -> Unit
) {
    SettingsSurfaceGroup(
        content = subscriptions.map { sub ->
            {
                SubscriptionItem(
                    sub,
                    { onShowUrl(sub) },
                    { onShowActions(sub) },
                    !busy,
                    importingSubscriptionId == sub.id,
                    progress.takeIf { importingSubscriptionId == sub.id },
                    ruleBreakdown = ruleBreakdowns[sub.id]
                )
            }
        }
    )
}

@Composable
internal fun SubscriptionItem(
    subscription: SubscriptionEntity,
    onShowUrl: () -> Unit,
    onShowActions: () -> Unit,
    actionsEnabled: Boolean,
    isUpdating: Boolean,
    progress: SubscriptionProgress?,
    ruleBreakdown: SubscriptionRuleBreakdown? = null
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = subscription.name,
                    style = MaterialTheme.typography.bodyLarge,
                    color = if (subscription.enabled) {
                        MaterialTheme.colorScheme.onSurface
                    } else {
                        MaterialTheme.colorScheme.onSurfaceVariant
                    }
                )
                val kindLabel = when (subscription.kind) {
                    SubscriptionKind.REWRITE -> "hosts 覆写"
                    SubscriptionKind.BLOCK -> "DNS 过滤"
                    SubscriptionKind.ALLOW -> "白名单"
                    else -> "规则订阅"
                }
                Text(
                    text = buildString {
                        append(localizedText(kindLabel))
                        if (subscription.mirrorTemplate != null) append(localizedText(" · 自定义镜像"))
                    },
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.primary
                )
                Spacer(modifier = Modifier.height(2.dp))
                Text(
                    text = if (subscription.sourceType == SubscriptionSourceType.LOCAL) localizedText("本地文件") else subscription.url,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = if (subscription.sourceType == SubscriptionSourceType.REMOTE) {
                        Modifier.clickable(onClick = onShowUrl)
                    } else {
                        Modifier
                    }
                )
            }
            IconButton(onClick = onShowActions, enabled = actionsEnabled) {
                Icon(
                    Icons.Default.MoreVert,
                    contentDescription = localizedText("打开规则订阅操作")
                )
            }
        }
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Text(
                text = localizedText(if (subscription.enabled) "已启用" else "已禁用"),
                style = MaterialTheme.typography.bodySmall,
                color = if (subscription.enabled) {
                    MaterialTheme.colorScheme.primary
                } else {
                    MaterialTheme.colorScheme.onSurfaceVariant
                }
            )
            val breakdown = ruleBreakdown
            val ruleCountText = if (breakdown != null && (breakdown.blockCount > 0 || breakdown.allowCount > 0 || breakdown.rewriteCount > 0)) {
                val details = buildList {
                    if (breakdown.blockCount > 0) add(localizedText("黑名单") + " ${breakdown.blockCount}")
                    if (breakdown.allowCount > 0) add(localizedText("白名单") + " ${breakdown.allowCount}")
                    if (breakdown.rewriteCount > 0) add(localizedText("覆写") + " ${breakdown.rewriteCount}")
                }.joinToString(" · ")
                "${subscription.ruleCount} " + localizedText("条规则") + if (details.isNotEmpty()) "（$details）" else ""
            } else {
                localizedText("${subscription.ruleCount} 条规则")
            }
            Text(
                text = ruleCountText,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        if (subscription.lastUpdated > 0) {
            val dateStr = remember(subscription.lastUpdated) {
                SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.getDefault())
                    .format(Date(subscription.lastUpdated))
            }
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = localizedText(if (subscription.sourceType == SubscriptionSourceType.LOCAL) {
                    "导入于 $dateStr"
                } else {
                    "更新于 $dateStr"
                }),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        if (subscription.sourceType == SubscriptionSourceType.REMOTE && subscription.lastAttemptAt > 0) {
            val attemptDate = remember(subscription.lastAttemptAt) {
                SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.getDefault())
                    .format(Date(subscription.lastAttemptAt))
            }
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = localizedText("上次尝试于 $attemptDate"),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        if (isUpdating || subscription.importState == SubscriptionImportState.IMPORTING) {
            val total = progress?.total ?: 0
            val current = (progress?.current ?: -1).coerceAtLeast(0)
            val fraction = if (total > 0) (current.toFloat() / total).coerceIn(0f, 1f) else 0f
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = localizedText(
                    if (total > 0) "正在下载并更新规则... $current / $total（${(fraction * 100).toInt()}%）"
                    else "正在下载并更新规则..."
                ),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Spacer(modifier = Modifier.height(4.dp))
            LinearProgressIndicator(progress = { fraction }, modifier = Modifier.fillMaxWidth())
        }
        if (subscription.importState == SubscriptionImportState.FAILED) {
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = localizedText(if (subscription.sourceType == SubscriptionSourceType.REMOTE) {
                    "更新失败（连续 ${subscription.consecutiveFailureCount} 次）：" +
                        (subscription.importError ?: "未知错误")
                } else {
                    "导入失败：${subscription.importError ?: "未知错误"}"
                }),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.error
            )
        }
    }
}
