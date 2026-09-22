package com.haoze.diting.ui

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
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.haoze.diting.ui.components.SettingsGroupTitle
import com.haoze.diting.ui.components.SettingsInfoText
import com.haoze.diting.ui.components.SettingsScaffold
import com.haoze.diting.ui.components.SettingsSurfaceGroup
import com.haoze.diting.ui.settings.AppearanceSettingsStore

@Composable
fun BottomBarCustomizationScreen(
    onBack: () -> Unit,
    onBottomBarChanged: () -> Unit = {}
) {
    val context = LocalContext.current
    var selectedItems by remember {
        mutableStateOf(AppearanceSettingsStore.getBottomBarDestinations(context))
    }

    val saveAndNotify = { newItems: List<BottomBarDestination> ->
        selectedItems = newItems
        AppearanceSettingsStore.setBottomBarDestinations(context, newItems)
        onBottomBarChanged()
    }

    val availableItems = remember(selectedItems) {
        BottomBarDestination.entries.filterNot { it in selectedItems }
    }

    SettingsScaffold(
        title = localizedText("底栏自定义"),
        onBack = onBack,
        actions = {
            TextButton(
                onClick = {
                    saveAndNotify(BottomBarDestination.DEFAULT_DESTINATIONS)
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
                    SelectedBottomBarItemRow(
                        index = index,
                        totalCount = selectedItems.size,
                        destination = item,
                        canMoveUp = index > 0,
                        canMoveDown = index < selectedItems.size - 1,
                        canRemove = selectedItems.size > BottomBarDestination.MIN_COUNT,
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
                            if (selectedItems.size <= BottomBarDestination.MIN_COUNT) {
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
                    AvailableBottomBarItemRow(
                        destination = item,
                        canAdd = selectedItems.size < BottomBarDestination.MAX_COUNT,
                        onAdd = {
                            if (selectedItems.size >= BottomBarDestination.MAX_COUNT) {
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
                    localizedText("底栏按钮数量限制在 2～4 个。您可在此自由添加、移除或调整底栏按钮的显示顺序。")
                )
            }

            item {
                SettingsGroupTitle(
                    text = localizedText("已选底栏按钮") + " (${selectedItems.size}/${BottomBarDestination.MAX_COUNT})"
                )
            }

            item {
                SettingsSurfaceGroup(content = selectedGroupItems)
            }

            item {
                SettingsGroupTitle(localizedText("可添加的页面"))
            }

            if (availableItems.isEmpty()) {
                item {
                    SettingsInfoText(localizedText("所有页面均已添加到底栏"))
                }
            } else {
                item {
                    SettingsSurfaceGroup(content = availableGroupItems)
                }
            }

            item {
                SettingsGroupTitle(localizedText("底栏效果预览"))
            }

            item {
                BottomBarPreviewCard(destinations = selectedItems)
            }

            item {
                Spacer(modifier = Modifier.height(28.dp))
            }
        }
    }
}

@Composable
private fun SelectedBottomBarItemRow(
    index: Int,
    totalCount: Int,
    destination: BottomBarDestination,
    canMoveUp: Boolean,
    canMoveDown: Boolean,
    canRemove: Boolean,
    onMoveUp: () -> Unit,
    onMoveDown: () -> Unit,
    onRemove: () -> Unit,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = 72.dp)
            .padding(horizontal = 20.dp, vertical = 16.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        // Index badge
        Box(
            modifier = Modifier
                .size(24.dp)
                .background(
                    MaterialTheme.colorScheme.primary.copy(alpha = 0.12f),
                    CircleShape
                ),
            contentAlignment = Alignment.Center
        ) {
            Text(
                text = "${index + 1}",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.primary,
                fontWeight = FontWeight.Bold
            )
        }

        Spacer(modifier = Modifier.width(10.dp))

        // Destination Icon container
        Box(
            modifier = Modifier
                .size(42.dp)
                .background(
                    MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.5f),
                    RoundedCornerShape(12.dp)
                ),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = destination.icon,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(22.dp)
            )
        }

        Spacer(modifier = Modifier.width(14.dp))

        // Title and description
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(2.dp)
        ) {
            Text(
                text = localizedText(destination.title),
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurface,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Text(
                text = localizedText(destination.description),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }

        Spacer(modifier = Modifier.width(6.dp))

        // Action buttons
        IconButton(
            onClick = onMoveUp,
            enabled = canMoveUp,
            modifier = Modifier.size(34.dp)
        ) {
            Icon(
                imageVector = Icons.Default.ArrowUpward,
                contentDescription = localizedText("向上移动"),
                tint = if (canMoveUp) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.28f),
                modifier = Modifier.size(19.dp)
            )
        }

        IconButton(
            onClick = onMoveDown,
            enabled = canMoveDown,
            modifier = Modifier.size(34.dp)
        ) {
            Icon(
                imageVector = Icons.Default.ArrowDownward,
                contentDescription = localizedText("向下移动"),
                tint = if (canMoveDown) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.28f),
                modifier = Modifier.size(19.dp)
            )
        }

        IconButton(
            onClick = onRemove,
            enabled = canRemove,
            modifier = Modifier.size(34.dp)
        ) {
            Icon(
                imageVector = Icons.Default.DeleteOutline,
                contentDescription = localizedText("移除"),
                tint = if (canRemove) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.error.copy(alpha = 0.28f),
                modifier = Modifier.size(19.dp)
            )
        }
    }
}

@Composable
private fun AvailableBottomBarItemRow(
    destination: BottomBarDestination,
    canAdd: Boolean,
    onAdd: () -> Unit,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = 72.dp)
            .padding(horizontal = 20.dp, vertical = 16.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        // Destination Icon container
        Box(
            modifier = Modifier
                .size(42.dp)
                .background(
                    MaterialTheme.colorScheme.surfaceContainerHighest.copy(alpha = 0.65f),
                    RoundedCornerShape(12.dp)
                ),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = destination.icon,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(22.dp)
            )
        }

        Spacer(modifier = Modifier.width(14.dp))

        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(2.dp)
        ) {
            Text(
                text = localizedText(destination.title),
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurface,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Text(
                text = localizedText(destination.description),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }

        Spacer(modifier = Modifier.width(6.dp))

        FilledTonalIconButton(
            onClick = onAdd,
            enabled = canAdd,
            modifier = Modifier.size(36.dp),
            colors = IconButtonDefaults.filledTonalIconButtonColors(
                containerColor = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.6f),
                contentColor = MaterialTheme.colorScheme.primary,
                disabledContainerColor = MaterialTheme.colorScheme.surfaceContainerHighest.copy(alpha = 0.4f),
                disabledContentColor = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.38f)
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

@Composable
private fun BottomBarPreviewCard(
    destinations: List<BottomBarDestination>,
    modifier: Modifier = Modifier
) {
    var previewSelectedPage by remember(destinations) { mutableIntStateOf(0) }
    val safeSelectedPage = previewSelectedPage.coerceIn(0, (destinations.size - 1).coerceAtLeast(0))

    SettingsSurfaceGroup(
        modifier = modifier,
        content = listOf {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp, vertical = 18.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                // Header row of preview
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Box(
                            modifier = Modifier
                                .size(28.dp)
                                .background(
                                    MaterialTheme.colorScheme.primary.copy(alpha = 0.12f),
                                    CircleShape
                                ),
                            contentAlignment = Alignment.Center
                        ) {
                            Icon(
                                imageVector = Icons.Default.Visibility,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.primary,
                                modifier = Modifier.size(16.dp)
                            )
                        }
                        Text(
                            text = localizedText("当前底栏预览"),
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold,
                            color = MaterialTheme.colorScheme.onSurface
                        )
                    }

                    Surface(
                        shape = CircleShape,
                        color = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.5f)
                    ) {
                        Text(
                            text = "${destinations.size} " + localizedText("项"),
                            style = MaterialTheme.typography.labelSmall,
                            fontWeight = FontWeight.Medium,
                            color = MaterialTheme.colorScheme.onPrimaryContainer,
                            modifier = Modifier.padding(horizontal = 10.dp, vertical = 4.dp)
                        )
                    }
                }

                Spacer(modifier = Modifier.height(14.dp))

                // Simulated container preview stage
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(20.dp))
                        .background(
                            MaterialTheme.colorScheme.surface.copy(alpha = 0.6f)
                        )
                        .border(
                            width = 1.dp,
                            color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.4f),
                            shape = RoundedCornerShape(20.dp)
                        )
                        .padding(vertical = 16.dp, horizontal = 8.dp),
                    contentAlignment = Alignment.Center
                ) {
                    BoxWithConstraints(
                        modifier = Modifier.fillMaxWidth(),
                        contentAlignment = Alignment.Center
                    ) {
                        val tabsCount = destinations.size.coerceIn(
                            BottomBarDestination.MIN_COUNT,
                            BottomBarDestination.MAX_COUNT
                        )
                        val targetWidth = when (tabsCount) {
                            2 -> 204.dp
                            3 -> 276.dp
                            4 -> 340.dp
                            else -> 204.dp
                        }
                        val scale = if (maxWidth < targetWidth + 16.dp) {
                            ((maxWidth.value - 16f) / targetWidth.value).coerceAtLeast(0.7f)
                        } else {
                            1f
                        }.coerceAtMost(1f)

                        Box(
                            modifier = Modifier
                                .height(64.dp)
                                .graphicsLayer {
                                    scaleX = scale
                                    scaleY = scale
                                },
                            contentAlignment = Alignment.Center
                        ) {
                            FloatingNavigationBar(
                                selectedPage = safeSelectedPage,
                                onPageSelected = { previewSelectedPage = it },
                                items = destinations,
                                isGlassEnabled = true
                            )
                        }
                    }
                }

                Spacer(modifier = Modifier.height(10.dp))

                Text(
                    text = localizedText("可点击上方底栏图标测试切换效果与高光"),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    )
}
