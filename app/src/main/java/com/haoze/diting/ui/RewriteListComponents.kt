package com.haoze.diting.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.AltRoute
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.haoze.diting.data.entity.RewriteTargetType
import com.haoze.diting.ui.components.RuleItemActionsMenu
import com.haoze.diting.ui.components.RuleStatsCard
import com.haoze.diting.ui.components.RuleTagChip

@Composable
internal fun RewriteListStatsCard(stats: RewriteListStats) {
    RuleStatsCard(
        icon = Icons.AutoMirrored.Filled.AltRoute,
        title = localizedText("覆写统计与状态"),
        activeBadgeText = localizedText("生效中: ${stats.totalActive} 条"),
        stats = listOf(
            "IPv4 覆写" to stats.ipv4Count.toString(),
            "IPv6 覆写" to stats.ipv6Count.toString(),
            "CNAME 覆写" to stats.cnameCount.toString(),
            "用户自定义" to "${stats.userEnabled}/${stats.userTotal}"
        )
    )
}

@Composable
internal fun RewriteListItemRow(
    item: RewriteListItem,
    onToggle: (Boolean) -> Unit,
    onEdit: () -> Unit,
    onDelete: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Column(
            modifier = Modifier
                .weight(1f)
                .padding(end = 8.dp)
                .alpha(if (!item.effectiveEnabled) 0.5f else 1f),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            // Rule domain
            Text(
                text = item.pattern,
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.Medium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )

            // Rewrite target indicator
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Text(
                    text = "-> ${item.targetValue}",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.primary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }

            // Tag row
            Row(
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                // Source tag
                if (item.isUserRule) {
                    RuleTagChip(
                        text = localizedText("自定义"),
                        containerColor = MaterialTheme.colorScheme.primaryContainer,
                        contentColor = MaterialTheme.colorScheme.onPrimaryContainer
                    )
                }
                if (item.isSubscription) {
                    RuleTagChip(
                        text = item.subscriptionName?.let { localizedText(it) } ?: localizedText("规则订阅"),
                        containerColor = MaterialTheme.colorScheme.secondaryContainer,
                        contentColor = MaterialTheme.colorScheme.onSecondaryContainer,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }

                // Target type tag
                RuleTagChip(
                    text = item.targetType,
                    containerColor = when (item.targetType) {
                        RewriteTargetType.IPV4 -> MaterialTheme.colorScheme.tertiaryContainer
                        RewriteTargetType.IPV6 -> MaterialTheme.colorScheme.secondaryContainer
                        else -> MaterialTheme.colorScheme.surfaceVariant
                    },
                    contentColor = when (item.targetType) {
                        RewriteTargetType.IPV4 -> MaterialTheme.colorScheme.onTertiaryContainer
                        RewriteTargetType.IPV6 -> MaterialTheme.colorScheme.onSecondaryContainer
                        else -> MaterialTheme.colorScheme.onSurfaceVariant
                    }
                )
            }

            // Original rule line (shown when it differs from pattern -> targetValue)
            val standardLine = "${item.pattern} -> ${item.targetValue}"
            if (item.rawLine != standardLine && item.rawLine.isNotBlank() && item.rawLine != item.pattern) {
                Text(
                    text = item.rawLine,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }

        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Switch(
                checked = item.effectiveEnabled,
                onCheckedChange = onToggle,
                enabled = item.masterEnabled,
                modifier = Modifier.alpha(if (!item.masterEnabled) 0.5f else 1f)
            )

            RuleItemActionsMenu(
                onEdit = onEdit,
                onDelete = onDelete
            )
        }
    }
}
