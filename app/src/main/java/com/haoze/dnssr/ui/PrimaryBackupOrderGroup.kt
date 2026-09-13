package com.haoze.dnssr.ui

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.foundation.gestures.scrollBy
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DragHandle
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import com.haoze.dnssr.ui.components.DnsProtocolBadge
import com.haoze.dnssr.ui.components.SettingsCornerShape
import com.haoze.dnssr.ui.components.SettingsDivider
import com.haoze.dnssr.vpn.DnsProvider
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

@Composable
internal fun PrimaryBackupOrderGroup(
    backupIds: List<String>,
    providersById: Map<String, DnsProvider>,
    listState: LazyListState,
    listViewportBounds: Rect?,
    onReorder: (String, Int) -> Unit
) {
    var orderedIds by remember(backupIds) { mutableStateOf(backupIds) }
    var draggedId by remember { mutableStateOf<String?>(null) }
    var settlingId by remember { mutableStateOf<String?>(null) }
    var dragOffsetY by remember { mutableFloatStateOf(0f) }
    var dragStartIndex by remember { mutableIntStateOf(0) }
    var targetIndex by remember { mutableIntStateOf(0) }
    var draggedCoordinates by remember { mutableStateOf<LayoutCoordinates?>(null) }
    var settleJob by remember { mutableStateOf<Job?>(null) }
    val latestBackupOrder = rememberUpdatedState(backupIds)
    val density = LocalDensity.current
    val hapticFeedback = LocalHapticFeedback.current
    val coroutineScope = rememberCoroutineScope()
    val settleOffset = remember { Animatable(0f) }
    val reorderThresholdPx = with(density) { 40.dp.toPx() }
    val edgeOverscrollPx = with(density) { 20.dp.toPx() }
    val autoScrollEdgePx = with(density) { 72.dp.toPx() }
    val maxAutoScrollPxPerSecond = with(density) { 720.dp.toPx() }
    val rowHeight = 48.dp
    val dividerHeight = 1.dp
    val itemHeight = rowHeight + dividerHeight
    val itemHeightPx = with(density) { itemHeight.toPx() }
    val liftedShape = SettingsCornerShape
    val rowColor = MaterialTheme.colorScheme.surfaceContainer

    fun updateDraggedPosition(providerId: String) {
        while (true) {
            val current = orderedIds
            val from = current.indexOf(providerId)
            if (from < 0) return

            if (from == 0 && dragOffsetY < -edgeOverscrollPx) {
                dragOffsetY = -edgeOverscrollPx
            }
            if (from == current.lastIndex && dragOffsetY > edgeOverscrollPx) {
                dragOffsetY = edgeOverscrollPx
            }

            val direction = when {
                dragOffsetY <= -reorderThresholdPx -> -1
                dragOffsetY >= reorderThresholdPx -> 1
                else -> return
            }
            val to = (from + direction).coerceIn(current.indices)
            if (from == to) return

            orderedIds = current.toMutableList().apply {
                add(to, removeAt(from))
            }
            targetIndex = to
            dragOffsetY -= direction * itemHeightPx
        }
    }

    fun settleDraggedItem(providerId: String) {
        settleJob?.cancel()
        settleJob = coroutineScope.launch(start = CoroutineStart.UNDISPATCHED) {
            settleOffset.snapTo(dragOffsetY)
            settlingId = providerId
            draggedId = null
            draggedCoordinates = null
            settleOffset.animateTo(
                targetValue = 0f,
                animationSpec = spring(
                    dampingRatio = Spring.DampingRatioNoBouncy,
                    stiffness = Spring.StiffnessMedium
                )
            )
            if (settlingId == providerId) {
                dragOffsetY = 0f
                settlingId = null
            }
        }
    }

    LaunchedEffect(draggedId, listViewportBounds) {
        val providerId = draggedId ?: return@LaunchedEffect
        val viewport = listViewportBounds ?: return@LaunchedEffect
        var previousFrameNanos = withFrameNanos { it }

        while (draggedId == providerId) {
            val frameNanos = withFrameNanos { it }
            val frameSeconds = ((frameNanos - previousFrameNanos) / 1_000_000_000f)
                .coerceAtMost(0.05f)
            previousFrameNanos = frameNanos

            val coordinates = draggedCoordinates
            if (coordinates?.isAttached != true) continue
            val centerY = coordinates.boundsInWindow().center.y
            val topDistance = centerY - viewport.top
            val bottomDistance = viewport.bottom - centerY
            val scrollVelocity = when {
                topDistance < autoScrollEdgePx && listState.canScrollBackward -> {
                    -maxAutoScrollPxPerSecond *
                        (1f - topDistance / autoScrollEdgePx).coerceIn(0f, 1f)
                }
                bottomDistance < autoScrollEdgePx && listState.canScrollForward -> {
                    maxAutoScrollPxPerSecond *
                        (1f - bottomDistance / autoScrollEdgePx).coerceIn(0f, 1f)
                }
                else -> 0f
            }
            if (scrollVelocity == 0f) continue

            val consumedScroll = listState.scrollBy(scrollVelocity * frameSeconds)
            if (consumedScroll != 0f) {
                dragOffsetY += consumedScroll
                updateDraggedPosition(providerId)
            }
        }
    }

    Box(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp)
            .height(itemHeight * orderedIds.size - dividerHeight)
    ) {
        Surface(
            modifier = Modifier.fillMaxSize(),
            shape = SettingsCornerShape,
            color = rowColor
        ) {}

        orderedIds.forEachIndexed { index, providerId ->
            val provider = providersById[providerId] ?: return@forEachIndexed
            key(providerId) {
                var rowCoordinates by remember { mutableStateOf<LayoutCoordinates?>(null) }
                val isDragging = draggedId == providerId
                val isSettling = settlingId == providerId
                val isRaised = isDragging || isSettling
                val baseOffset by animateDpAsState(
                    targetValue = itemHeight * index,
                    animationSpec = if (isRaised) snap() else tween(durationMillis = 160),
                    label = "primaryBackupItemPlacement"
                )
                val liftedScale by animateFloatAsState(
                    targetValue = if (isRaised) 1.02f else 1f,
                    animationSpec = tween(durationMillis = 120),
                    label = "primaryBackupLiftScale"
                )
                val displayIndex = if (isRaised) dragStartIndex else index
                val accessibilityActions = buildList {
                    if (index > 0) {
                        add(CustomAccessibilityAction(localizedText("提高优先级")) {
                            onReorder(providerId, index - 1)
                            true
                        })
                    }
                    if (index < orderedIds.lastIndex) {
                        add(CustomAccessibilityAction(localizedText("降低优先级")) {
                            onReorder(providerId, index + 1)
                            true
                        })
                    }
                }

                Row(
                    Modifier
                        .fillMaxWidth()
                        .height(rowHeight)
                        .offset(y = baseOffset)
                        .zIndex(if (isRaised) 1f else 0f)
                        .graphicsLayer {
                            translationY = when {
                                isDragging -> dragOffsetY
                                isSettling -> settleOffset.value
                                else -> 0f
                            }
                            scaleX = liftedScale
                            scaleY = liftedScale
                            shadowElevation = if (isDragging) 8.dp.toPx() else 0f
                            shape = liftedShape
                        }
                        .onGloballyPositioned {
                            rowCoordinates = it
                            if (isDragging) draggedCoordinates = it
                        }
                        .background(
                            color = if (isRaised) rowColor else Color.Transparent,
                            shape = liftedShape
                        )
                        .semantics(mergeDescendants = true) {
                            customActions = accessibilityActions
                        }
                        .padding(start = 16.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = localizedText(if (displayIndex == 0) {
                            "主"
                        } else {
                            "备 $displayIndex"
                        }),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(end = 8.dp)
                    )
                    Text(
                        text = localizedText(provider.name),
                        style = MaterialTheme.typography.bodyLarge,
                        modifier = Modifier.weight(1f),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    DnsProtocolBadge(
                        protocol = provider.protocol,
                        modifier = Modifier.padding(start = 8.dp)
                    )
                    Box(
                        modifier = Modifier
                            .size(48.dp)
                            .pointerInput(providerId, itemHeightPx, backupIds) {
                                detectDragGesturesAfterLongPress(
                                    onDragStart = {
                                        settleJob?.cancel()
                                        settlingId = null
                                        draggedId = providerId
                                        draggedCoordinates = rowCoordinates
                                        dragStartIndex = orderedIds.indexOf(providerId)
                                        targetIndex = dragStartIndex
                                        dragOffsetY = 0f
                                        hapticFeedback.performHapticFeedback(
                                            HapticFeedbackType.LongPress
                                        )
                                    },
                                    onDragCancel = {
                                        val currentIndex = orderedIds.indexOf(providerId)
                                        val backupOrder = latestBackupOrder.value
                                        val originalIndex = backupOrder.indexOf(providerId)
                                        if (currentIndex >= 0 && originalIndex >= 0) {
                                            dragOffsetY +=
                                                (currentIndex - originalIndex) * itemHeightPx
                                            targetIndex = originalIndex
                                        }
                                        orderedIds = backupOrder
                                        settleDraggedItem(providerId)
                                    },
                                    onDragEnd = {
                                        onReorder(providerId, targetIndex)
                                        settleDraggedItem(providerId)
                                    },
                                    onDrag = { change, dragAmount ->
                                        change.consume()
                                        dragOffsetY += dragAmount.y
                                        updateDraggedPosition(providerId)
                                    }
                                )
                            },
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(
                            imageVector = Icons.Default.DragHandle,
                            contentDescription = localizedText("长按并拖动调整顺序"),
                            tint = if (isRaised) {
                                MaterialTheme.colorScheme.primary
                            } else {
                                MaterialTheme.colorScheme.onSurfaceVariant
                            }
                        )
                    }
                }
            }
        }
        repeat(orderedIds.lastIndex) { index ->
            SettingsDivider(Modifier.offset(y = itemHeight * index + rowHeight))
        }
    }
}
