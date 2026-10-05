package com.haoze.diting.express.ui

import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ArrowDownward
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.DeleteOutline
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.haoze.diting.ui.BottomBarDestination
import com.haoze.diting.ui.components.SettingsGroupTitle
import com.haoze.diting.ui.components.SettingsInfoText
import com.haoze.diting.ui.components.SettingsScaffold
import com.haoze.diting.ui.components.SettingsSurfaceGroup
import com.haoze.diting.ui.localizedText
import com.haoze.diting.ui.settings.AppearanceSettingsStore

/**
 * Dedicated Bottom Bar Customization Screen for Express Mode.
 *
 * Restricts customization options to the 4 destinations valid in Express Mode:
 * HOME, FEATURE_HUB, LOG_DASHBOARD, SETTINGS.
 * Physically omits full-tunnel destinations (APP_TRAFFIC_STATS & NETWORK_TOOLS).
 */
@Composable
fun ExpressBottomBarCustomizationScreen(
    onBack: () -> Unit,
    onBottomBarChanged: () -> Unit = {}
) {
    val context = LocalContext.current
    var selectedItems by remember {
        mutableStateOf(ExpressBottomBarDestination.getDestinations(context))
    }

    val saveAndNotify = { newItems: List<ExpressBottomBarDestination> ->
        selectedItems = newItems
        val legacyList = newItems.mapNotNull { BottomBarDestination.fromId(it.id) }
        AppearanceSettingsStore.setBottomBarDestinations(context, legacyList)
        onBottomBarChanged()
    }

    val availableItems = remember(selectedItems) {
        ExpressBottomBarDestination.entries.filterNot { it in selectedItems }
    }

    SettingsScaffold(
        title = localizedText("底栏自定义"),
        onBack = onBack,
        actions = {
            TextButton(
                onClick = {
                    saveAndNotify(ExpressBottomBarDestination.DEFAULT_DESTINATIONS)
                    Toast.makeText(context, localizedText(context, "已恢复默认底栏配置"), Toast.LENGTH_SHORT).show()
                }
            ) {
                Text(localizedText("恢复默认"))
            }
        }
    ) { innerPadding ->
        val selectedGroupItems = buildList<@Composable () -> Unit> {
            selectedItems.forEachIndexed { index, item ->
                add {
                    ExpressSelectedBottomBarItemRow(
                        index = index,
                        totalCount = selectedItems.size,
                        destination = item,
                        canMoveUp = index > 0,
                        canMoveDown = index < selectedItems.size - 1,
                        canRemove = selectedItems.size > ExpressBottomBarDestination.MIN_COUNT,
                        onMoveUp = {
                            if (index > 0) {
                                val mutable = selectedItems.toMutableList()
                                val temp = mutable[index]
                                mutable[index] = mutable[index - 1]
                                mutable[index - 1] = temp
                                saveAndNotify(mutable)
                            }
                        },
                        onMoveDown = {
                            if (index < selectedItems.size - 1) {
                                val mutable = selectedItems.toMutableList()
                                val temp = mutable[index]
                                mutable[index] = mutable[index + 1]
                                mutable[index + 1] = temp
                                saveAndNotify(mutable)
                            }
                        },
                        onRemove = {
                            if (selectedItems.size <= ExpressBottomBarDestination.MIN_COUNT) {
                                Toast.makeText(
                                    context,
                                    localizedText(context, "底栏至少保留 2 个按钮"),
                                    Toast.LENGTH_SHORT
                                ).show()
                            } else {
                                val mutable = selectedItems.toMutableList()
                                mutable.removeAt(index)
                                saveAndNotify(mutable)
                            }
                        }
                    )
                }
            }
        }

        val availableGroupItems = buildList<@Composable () -> Unit> {
            availableItems.forEach { item ->
                add {
                    ExpressAvailableBottomBarItemRow(
                        destination = item,
                        canAdd = selectedItems.size < ExpressBottomBarDestination.MAX_COUNT,
                        onAdd = {
                            if (selectedItems.size >= ExpressBottomBarDestination.MAX_COUNT) {
                                Toast.makeText(
                                    context,
                                    localizedText(context, "底栏最多添加 4 个按钮"),
                                    Toast.LENGTH_SHORT
                                ).show()
                            } else {
                                saveAndNotify(selectedItems + item)
                            }
                        }
                    )
                }
            }
        }

        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            item {
                SettingsInfoText(
                    localizedText("极速模式底栏按钮数量限制在 2～4 个。您可在此自由添加、移除或调整底栏按钮的显示顺序。")
                )
            }

            item {
                SettingsGroupTitle(
                    text = localizedText("已选底栏按钮") + " (${selectedItems.size}/${ExpressBottomBarDestination.MAX_COUNT})"
                )
            }

            item {
                SettingsSurfaceGroup(content = selectedGroupItems)
            }

            if (availableItems.isNotEmpty()) {
                item {
                    SettingsGroupTitle(
                        text = localizedText("可添加的按钮") + " (${availableItems.size})"
                    )
                }
                item {
                    SettingsSurfaceGroup(content = availableGroupItems)
                }
            }
        }
    }
}

@Composable
private fun ExpressSelectedBottomBarItemRow(
    index: Int,
    totalCount: Int,
    destination: ExpressBottomBarDestination,
    canMoveUp: Boolean,
    canMoveDown: Boolean,
    canRemove: Boolean,
    onMoveUp: () -> Unit,
    onMoveDown: () -> Unit,
    onRemove: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 68.dp)
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Surface(
            shape = CircleShape,
            color = MaterialTheme.colorScheme.primaryContainer,
            modifier = Modifier.size(36.dp)
        ) {
            Box(contentAlignment = Alignment.Center) {
                Icon(
                    imageVector = destination.icon,
                    contentDescription = null,
                    modifier = Modifier.size(20.dp),
                    tint = MaterialTheme.colorScheme.onPrimaryContainer
                )
            }
        }

        Spacer(modifier = Modifier.width(12.dp))

        Column(modifier = Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = localizedText(destination.title),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Medium,
                    color = MaterialTheme.colorScheme.onSurface
                )
                Spacer(modifier = Modifier.width(6.dp))
                Surface(
                    shape = RoundedCornerShape(4.dp),
                    color = MaterialTheme.colorScheme.secondaryContainer.copy(alpha = 0.6f)
                ) {
                    Text(
                        text = "${index + 1}/$totalCount",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSecondaryContainer,
                        modifier = Modifier.padding(horizontal = 4.dp, vertical = 1.dp)
                    )
                }
            }
            Text(
                text = localizedText(destination.description),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }

        Spacer(modifier = Modifier.width(8.dp))

        Row(verticalAlignment = Alignment.CenterVertically) {
            IconButton(
                onClick = onMoveUp,
                enabled = canMoveUp,
                modifier = Modifier.size(36.dp)
            ) {
                Icon(
                    imageVector = Icons.Default.ArrowUpward,
                    contentDescription = localizedText("上移"),
                    tint = if (canMoveUp) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.38f)
                )
            }

            IconButton(
                onClick = onMoveDown,
                enabled = canMoveDown,
                modifier = Modifier.size(36.dp)
            ) {
                Icon(
                    imageVector = Icons.Default.ArrowDownward,
                    contentDescription = localizedText("下移"),
                    tint = if (canMoveDown) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.38f)
                )
            }

            IconButton(
                onClick = onRemove,
                enabled = canRemove,
                modifier = Modifier.size(36.dp)
            ) {
                Icon(
                    imageVector = Icons.Default.DeleteOutline,
                    contentDescription = localizedText("移除"),
                    tint = if (canRemove) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.38f)
                )
            }
        }
    }
}

@Composable
private fun ExpressAvailableBottomBarItemRow(
    destination: ExpressBottomBarDestination,
    canAdd: Boolean,
    onAdd: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 68.dp)
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Surface(
            shape = CircleShape,
            color = MaterialTheme.colorScheme.surfaceVariant,
            modifier = Modifier.size(36.dp)
        ) {
            Box(contentAlignment = Alignment.Center) {
                Icon(
                    imageVector = destination.icon,
                    contentDescription = null,
                    modifier = Modifier.size(20.dp),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }

        Spacer(modifier = Modifier.width(12.dp))

        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = localizedText(destination.title),
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Medium,
                color = MaterialTheme.colorScheme.onSurface
            )
            Text(
                text = localizedText(destination.description),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }

        Spacer(modifier = Modifier.width(8.dp))

        FilledTonalIconButton(
            onClick = onAdd,
            enabled = canAdd,
            modifier = Modifier.size(36.dp),
            colors = IconButtonDefaults.filledTonalIconButtonColors(
                containerColor = MaterialTheme.colorScheme.primaryContainer,
                contentColor = MaterialTheme.colorScheme.onPrimaryContainer
            )
        ) {
            Icon(
                imageVector = Icons.Default.Add,
                contentDescription = localizedText("添加"),
                modifier = Modifier.size(20.dp)
            )
        }
    }
}
