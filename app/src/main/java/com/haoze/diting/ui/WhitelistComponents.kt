package com.haoze.diting.ui

import android.widget.Toast
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Security
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.haoze.diting.ui.components.RuleItemActionsMenu
import com.haoze.diting.ui.components.RuleStatsCard
import com.haoze.diting.ui.components.RuleTagChip

@Composable
internal fun WhitelistStatsCard(stats: WhitelistStats) {
    RuleStatsCard(
        icon = Icons.Filled.Security,
        title = localizedText("放行统计与状态"),
        activeBadgeText = localizedText("生效中: ${stats.totalActive} 条"),
        stats = listOf(
            "放行域名数" to stats.totalDomains.toString(),
            "默认预设" to "${stats.presetEnabled}/${stats.presetTotal}",
            "用户自定义" to "${stats.userEnabled}/${stats.userTotal}",
            "放行 URL" to stats.urlAllowCount.toString()
        )
    )
}

@Composable
internal fun WhitelistItemRow(
    item: WhitelistItem,
    allowEditDefault: Boolean,
    onToggle: (Boolean) -> Unit,
    onEdit: () -> Unit,
    onDelete: () -> Unit
) {
    val context = LocalContext.current
    val isReadOnly = item.isPreset && !allowEditDefault

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
                .alpha(if (!item.effectiveEnabled) 0.5f else if (isReadOnly) 0.75f else 1f),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            // Rule content
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Text(
                    text = item.pattern,
                    style = MaterialTheme.typography.bodyLarge,
                    fontWeight = FontWeight.Medium,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f, fill = false)
                )
            }

            // Tag row
            Row(
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                // Source tag
                if (item.isPreset) {
                    RuleTagChip(
                        text = localizedText("默认预设"),
                        containerColor = MaterialTheme.colorScheme.secondaryContainer.copy(alpha = 0.7f),
                        contentColor = MaterialTheme.colorScheme.onSecondaryContainer
                    )
                }
                if (item.isUserRule && !item.isPreset) {
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

                // Type tag (URL allow)
                if (item.type == WhitelistType.URL) {
                    RuleTagChip(
                        text = "URL",
                        containerColor = MaterialTheme.colorScheme.tertiaryContainer,
                        contentColor = MaterialTheme.colorScheme.onTertiaryContainer
                    )
                }

                // Important rule tag
                if (item.important) {
                    RuleTagChip(
                        text = localizedText("重要"),
                        containerColor = MaterialTheme.colorScheme.errorContainer,
                        contentColor = MaterialTheme.colorScheme.onErrorContainer
                    )
                }

                // Wildcard tag
                if (item.isWildcard) {
                    RuleTagChip(
                        text = localizedText("通配符"),
                        containerColor = MaterialTheme.colorScheme.secondaryContainer,
                        contentColor = MaterialTheme.colorScheme.onSecondaryContainer
                    )
                }

                // App scope tag
                item.appScope?.takeIf { it.isNotBlank() }?.let { app ->
                    val label = (if (item.appInverted) "~" else "") + app
                    RuleTagChip(
                        text = "App: $label",
                        containerColor = MaterialTheme.colorScheme.tertiaryContainer,
                        contentColor = MaterialTheme.colorScheme.onTertiaryContainer,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }

                // Group tag
                item.groupName?.takeIf { it.isNotBlank() }?.let { group ->
                    RuleTagChip(
                        text = group,
                        containerColor = MaterialTheme.colorScheme.surfaceVariant,
                        contentColor = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            }

            // Original rule line (shown when it differs from the pattern)
            if (item.rawLine != item.pattern && item.rawLine.isNotBlank()) {
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
                enabled = !isReadOnly && item.masterEnabled,
                modifier = Modifier.alpha(if (isReadOnly || !item.masterEnabled) 0.5f else 1f)
            )

            RuleItemActionsMenu(
                onEdit = onEdit,
                onDelete = onDelete,
                enabled = !isReadOnly,
                onDisabledClick = { context.showToast("请先开启【允许编辑默认白名单】开关", Toast.LENGTH_SHORT) }
            )
        }
    }
}
