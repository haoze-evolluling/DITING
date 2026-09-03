package com.haoze.dnssr.ui

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.EaseOut
import androidx.compose.animation.core.spring
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Apps
import androidx.compose.material.icons.filled.Home
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.util.fastCoerceIn
import androidx.compose.ui.util.fastFirstOrNull
import androidx.compose.ui.util.fastRoundToInt
import com.haoze.dnssr.ui.component.liquid.DampedDragAnimation
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.sign

/**
 * 现代轻量化 Material 3 悬浮胶囊底栏。
 * 纯状态与手势驱动，彻底移除所有光影着色器及硬件传感器监听，具有优异的能效表现。
 */
@Composable
fun FloatingNavigationBar(
    currentPage: Int,
    onPageSelected: (Int) -> Unit,
    modifier: Modifier = Modifier,
    pagerProgress: (() -> Float)? = null
) {
    val pillShape = remember { CircleShape }
    val accentColor = MaterialTheme.colorScheme.onPrimaryContainer
    val activeTabIndicatorColor = MaterialTheme.colorScheme.primaryContainer
    val tabContentColor = MaterialTheme.colorScheme.onSurfaceVariant
    val containerColor = MaterialTheme.colorScheme.surfaceContainer
    val borderColor = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.35f)

    val density = LocalDensity.current
    val isLtr = LocalLayoutDirection.current == LayoutDirection.Ltr
    val animationScope = rememberCoroutineScope()
    val tabsCount = 2

    var tabWidthPx by remember { mutableFloatStateOf(0f) }
    var totalWidthPx by remember { mutableFloatStateOf(0f) }
    var isUserDragging by remember { mutableStateOf(false) }

    val offsetAnimation = remember { Animatable(0f) }
    val rubberBandPx = with(density) { 4.dp.toPx() }
    val panelOffset by remember(rubberBandPx) {
        derivedStateOf {
            if (totalWidthPx == 0f) {
                0f
            } else {
                val fraction = (offsetAnimation.value / totalWidthPx).fastCoerceIn(-1f, 1f)
                rubberBandPx * fraction.sign * EaseOut.transform(abs(fraction))
            }
        }
    }

    var currentIndex by remember(currentPage) { mutableIntStateOf(currentPage) }

    val dampedDragAnimation = remember(animationScope, tabsCount, density, isLtr) {
        DampedDragAnimation(
            animationScope = animationScope,
            initialValue = currentPage.toFloat(),
            valueRange = 0f..(tabsCount - 1).toFloat(),
            visibilityThreshold = 0.001f,
            initialScale = 1f,
            pressedScale = 78f / 56f
        )
    }

    // 跟随 Pager 页面滑动进度
    if (pagerProgress != null) {
        LaunchedEffect(dampedDragAnimation) {
            snapshotFlow { pagerProgress() }
                .distinctUntilChanged()
                .collectLatest { progress ->
                    if (!isUserDragging) {
                        dampedDragAnimation.updateValue(progress.fastCoerceIn(0f, (tabsCount - 1).toFloat()))
                    }
                }
        }
    } else {
        LaunchedEffect(currentPage) {
            if (!isUserDragging) {
                currentIndex = currentPage
                dampedDragAnimation.animateToValue(currentPage.toFloat())
            }
        }
    }

    LaunchedEffect(dampedDragAnimation) {
        snapshotFlow { currentIndex }.drop(1).collectLatest { index ->
            if (!isUserDragging) {
                dampedDragAnimation.animateToValue(index.toFloat())
            }
        }
    }

    val animValue = dampedDragAnimation.value
    val tab0Weight = (1f - animValue).fastCoerceIn(0f, 1f)
    val tab1Weight = animValue.fastCoerceIn(0f, 1f)

    Box(
        modifier = modifier
            .width(208.dp)
            .height(64.dp)
            .pointerInput(tabWidthPx, totalWidthPx, isLtr) {
                awaitEachGesture {
                    val down = awaitFirstDown(requireUnconsumed = false)
                    isUserDragging = true
                    val downX = down.position.x
                    dampedDragAnimation.press()

                    var hasMoved = false
                    val touchSlop = viewConfiguration.touchSlop
                    val currentPointerId = down.id

                    while (true) {
                        val event = awaitPointerEvent()
                        val change = event.changes.fastFirstOrNull { it.id == currentPointerId } ?: break
                        if (change.pressed) {
                            val dragAmount = change.positionChange()
                            val totalMoveX = abs(change.position.x - downX)
                            if (!hasMoved && totalMoveX > touchSlop) {
                                hasMoved = true
                            }

                            if (hasMoved) {
                                change.consume()
                            }

                            if (tabWidthPx > 0f) {
                                val rawDelta = if (isLtr) dragAmount.x / tabWidthPx else -dragAmount.x / tabWidthPx
                                val newTarget = dampedDragAnimation.targetValue + rawDelta
                                val clampedTarget = newTarget.fastCoerceIn(0f, (tabsCount - 1).toFloat())
                                dampedDragAnimation.updateValue(clampedTarget)

                                val excess = (newTarget - clampedTarget) * tabWidthPx * if (isLtr) 1f else -1f
                                if (excess != 0f || offsetAnimation.value != 0f) {
                                    animationScope.launch {
                                        offsetAnimation.snapTo(offsetAnimation.value + dragAmount.x * 0.4f)
                                    }
                                }
                            }
                        } else {
                            change.consume()
                            val upX = change.position.x
                            val targetIndex = if (!hasMoved) {
                                // 点击手势：按触摸位置确定 tab
                                if (isLtr) {
                                    if (upX < totalWidthPx / 2f) 0 else 1
                                } else {
                                    if (upX < totalWidthPx / 2f) 1 else 0
                                }.fastCoerceIn(0, tabsCount - 1)
                            } else {
                                // 滑动手势：吸附至最近 tab
                                dampedDragAnimation.targetValue.fastRoundToInt().fastCoerceIn(0, tabsCount - 1)
                            }

                            currentIndex = targetIndex
                            dampedDragAnimation.animateToValue(targetIndex.toFloat())
                            onPageSelected(targetIndex)
                            dampedDragAnimation.release()

                            animationScope.launch {
                                offsetAnimation.animateTo(0f, spring(1f, 300f, 0.5f))
                            }
                            isUserDragging = false
                            break
                        }
                    }
                }
            },
        contentAlignment = Alignment.CenterStart
    ) {
        // 1. 底栏容器背景
        Box(
            modifier = Modifier
                .fillMaxSize()
                .onGloballyPositioned { coords ->
                    totalWidthPx = coords.size.width.toFloat()
                    val contentWidthPx = totalWidthPx - with(density) { 8.dp.toPx() }
                    tabWidthPx = (contentWidthPx / tabsCount).coerceAtLeast(0f)
                }
                .graphicsLayer { translationX = panelOffset }
                .shadow(
                    elevation = 6.dp,
                    shape = pillShape,
                    ambientColor = Color.Black.copy(alpha = 0.08f),
                    spotColor = Color.Black.copy(alpha = 0.12f)
                )
                .clip(pillShape)
                .background(containerColor, pillShape)
                .border(BorderStroke(0.75.dp, borderColor), pillShape)
        )

        // 2. 滑动指示器胶囊
        if (tabWidthPx > 0f) {
            val tabWidthDp = with(density) { tabWidthPx.toDp() }
            Box(
                Modifier
                    .padding(start = 4.dp)
                    .graphicsLayer {
                        val progressOffset = dampedDragAnimation.value * tabWidthPx
                        translationX = if (isLtr) progressOffset + panelOffset else -progressOffset + panelOffset
                        scaleX = dampedDragAnimation.scaleX
                        scaleY = dampedDragAnimation.scaleY
                        val velocity = dampedDragAnimation.velocity / 10f
                        scaleX /= 1f - (velocity * 0.75f).fastCoerceIn(-0.2f, 0.2f)
                        scaleY *= 1f - (velocity * 0.25f).fastCoerceIn(-0.2f, 0.2f)
                    }
                    .height(56.dp)
                    .width(tabWidthDp)
                    .clip(pillShape)
                    .background(activeTabIndicatorColor, pillShape)
            )
        }

        // 3. 标签项
        Row(
            modifier = Modifier
                .fillMaxSize()
                .padding(4.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            FloatingBottomBarTab(
                weight = tab0Weight,
                pressProgress = dampedDragAnimation.pressProgress,
                icon = Icons.Default.Home,
                label = localizedText("首页"),
                accentColor = accentColor,
                contentColor = tabContentColor
            )
            FloatingBottomBarTab(
                weight = tab1Weight,
                pressProgress = dampedDragAnimation.pressProgress,
                icon = Icons.Default.Apps,
                label = localizedText("功能中心"),
                accentColor = accentColor,
                contentColor = tabContentColor
            )
        }
    }
}

@Composable
private fun RowScope.FloatingBottomBarTab(
    weight: Float,
    pressProgress: Float,
    icon: ImageVector,
    label: String,
    accentColor: Color,
    contentColor: Color,
    modifier: Modifier = Modifier
) {
    val dynamicColor = lerp(contentColor, accentColor, weight)
    val dynamicScale = 1f + 0.04f * weight * pressProgress

    Column(
        modifier = modifier
            .semantics { role = Role.Tab }
            .fillMaxHeight()
            .weight(1f)
            .graphicsLayer {
                scaleX = dynamicScale
                scaleY = dynamicScale
            },
        verticalArrangement = Arrangement.spacedBy(1.dp, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Icon(
            imageVector = icon,
            contentDescription = label,
            tint = dynamicColor,
            modifier = Modifier.size(22.dp)
        )
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall.copy(
                fontSize = 11.sp,
                lineHeight = 14.sp
            ),
            color = dynamicColor,
            fontWeight = if (weight > 0.5f) FontWeight.SemiBold else FontWeight.Medium,
            maxLines = 1,
            softWrap = false,
            overflow = TextOverflow.Ellipsis
        )
    }
}
