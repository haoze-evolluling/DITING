package com.haoze.dnssr.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.haoze.dnssr.data.entity.SubscriptionGroupEntity
import com.haoze.dnssr.ui.components.SettingsCornerShape

@Composable
internal fun SubscriptionGroupTabs(
    groups: List<SubscriptionGroupEntity>,
    selectedGroupId: Long?,
    onGroupSelected: (Long?) -> Unit,
    onGroupLongClick: (SubscriptionGroupEntity) -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .horizontalScroll(rememberScrollState())
            .padding(horizontal = 16.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        SubscriptionGroupTab(localizedText("未分组"), selectedGroupId == null, { onGroupSelected(null) })
        groups.forEach { group ->
            SubscriptionGroupTab(
                name = group.name,
                selected = selectedGroupId == group.id,
                onClick = { onGroupSelected(group.id) },
                onLongClick = { onGroupLongClick(group) }
            )
        }
    }
}

@Composable
internal fun SubscriptionGroupTab(
    name: String,
    selected: Boolean,
    onClick: () -> Unit,
    onLongClick: (() -> Unit)? = null
) {
    val containerColor = if (selected) MaterialTheme.colorScheme.secondaryContainer else Color.Transparent
    val contentColor = if (selected) MaterialTheme.colorScheme.onSecondaryContainer else MaterialTheme.colorScheme.onSurfaceVariant
    Text(
        text = name,
        style = MaterialTheme.typography.labelLarge,
        color = contentColor,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
        modifier = Modifier
            .clip(SettingsCornerShape)
            .background(containerColor)
            .combinedClickable(onClick = onClick, onLongClick = onLongClick)
            .padding(horizontal = 16.dp, vertical = 10.dp)
    )
}
