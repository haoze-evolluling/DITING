package com.haoze.dnssr.ui

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.EaseOut
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.ui.draw.dropShadow
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.shadow.Shadow
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
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
import com.haoze.dnssr.ui.component.liquid.InnerShadow
import com.haoze.dnssr.ui.component.liquid.InteractiveHighlight
import com.haoze.dnssr.ui.component.liquid.IosIndicatorSpecular
import com.haoze.dnssr.ui.component.liquid.drawSpecularHighlight
import com.haoze.dnssr.ui.component.liquid.innerShadow
import com.haoze.dnssr.ui.component.liquid.rememberDeviceTilt
import com.haoze.dnssr.ui.component.liquid.rememberGravityRotatedHighlight
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.sign

/**
 * Liquid-glass floating pill bottom bar (SyncTouch/KernelSU design language).
 *
 * Interaction set:
 * - the indicator tracks the finger 1:1 while dragging inside the navigation
 *   section, with rubber-band overshoot on the whole pill and a
 *   velocity-driven squash/stretch deformation of the indicator;
 * - a press swells the indicator and lights an interactive touch glow;
 * - releasing settles to the nearest tab; a tap (no slop crossed) selects the
 *   tab under the touch position;
 * - the specular border highlights on the pill and the indicator are steered
 *   by the device gravity sensor, which lives only while this bar is rendered
 *   in glass mode and the app is resumed (see [rememberDeviceTilt]);
 * - [pagerProgress] keeps the indicator glued to the pager while its pages
 *   scroll; without it the indicator simply springs to [selectedPage];
 */
@Composable
fun FloatingNavigationBar(
    selectedPage: Int,
    onPageSelected: (Int) -> Unit,
    modifier: Modifier = Modifier,
    pagerProgress: (() -> Float)? = null,
    isGlassEnabled: Boolean = true,
) {
    val isInDark = MaterialTheme.colorScheme.surface.luminance() < 0.5f
    val pillShape = remember { CircleShape }
    val accentColor = MaterialTheme.colorScheme.primary
    val tabContentColor = MaterialTheme.colorScheme.onSurfaceVariant
    val surfaceContainer = MaterialTheme.colorScheme.surfaceContainer
    val containerColor = if (isGlassEnabled) {
        if (isInDark) surfaceContainer.copy(alpha = 0.52f) else surfaceContainer.copy(alpha = 0.58f)
    } else {
        surfaceContainer
    }

    val density = LocalDensity.current
    val isLtr = LocalLayoutDirection.current == LayoutDirection.Ltr
    val animationScope = rememberCoroutineScope()
    val tabsCount = 2

    val navSectionWidthDp = 204.dp
    val barHeightDp = 64.dp
    val totalWidthDp = navSectionWidthDp

    var tabWidthPx by remember { mutableFloatStateOf(0f) }
    var navWidthPx by remember { mutableFloatStateOf(0f) }
    var isUserDragging by remember { mutableStateOf(false) }

    val offsetAnimation = remember { Animatable(0f) }
    val rubberBandPx = with(density) { 4.dp.toPx() }
    val panelOffset by remember(rubberBandPx) {
        derivedStateOf {
            if (navWidthPx == 0f) {
                0f
            } else {
                val fraction = (offsetAnimation.value / navWidthPx).fastCoerceIn(-1f, 1f)
                rubberBandPx * fraction.sign * EaseOut.transform(abs(fraction))
            }
        }
    }

    var currentIndex by remember(selectedPage) { mutableIntStateOf(selectedPage) }

    val dampedDragAnimation = remember(animationScope, tabsCount, density, isLtr) {
        DampedDragAnimation(
            animationScope = animationScope,
            initialValue = selectedPage.toFloat(),
            valueRange = 0f..(tabsCount - 1).toFloat(),
            visibilityThreshold = 0.001f,
            initialScale = 1f,
            pressedScale = 78f / 56f
        )
    }

    // Keep indicator in sync while the pager scrolls on screen
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
        LaunchedEffect(selectedPage) {
            if (!isUserDragging) {
                currentIndex = selectedPage
                dampedDragAnimation.animateToValue(selectedPage.toFloat())
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

    val interactiveHighlight = remember(animationScope) {
        InteractiveHighlight(
            animationScope = animationScope,
            position = { size, touchOffset ->
                Offset(
                    touchOffset.x.fastCoerceIn(0f, size.width),
                    size.height / 2f
                )
            }
        )
    }

    // One tilt sensor feeds both highlights; it lives only while glass mode renders this bar.
    val deviceTilt = rememberDeviceTilt(enabled = isGlassEnabled)
    val baseHighlight = rememberGravityRotatedHighlight(IosIndicatorSpecular, extraDegrees = -45f, tiltState = deviceTilt)
    val pillHighlight = rememberGravityRotatedHighlight(IosIndicatorSpecular, extraDegrees = 90f, tiltState = deviceTilt)

    val animValue = dampedDragAnimation.value
    val tab0Weight = (1f - animValue).fastCoerceIn(0f, 1f)
    val tab1Weight = animValue.fastCoerceIn(0f, 1f)

    Box(
        modifier = modifier
            .width(totalWidthDp)
            .height(barHeightDp),
        contentAlignment = Alignment.CenterStart
    ) {
        // 1. Container background surface
        Box(
            modifier = Modifier
                .fillMaxSize()
                .graphicsLayer { translationX = panelOffset }
                .then(
                    if (isGlassEnabled) {
                        Modifier
                            .dropShadow(
                                shape = pillShape,
                                shadow = Shadow(
                                    radius = 10.dp,
                                    color = Color.Black,
                                    alpha = if (isInDark) 0.25f else 0.12f,
                                ),
                            )
                            .clip(pillShape)
                            .background(containerColor, pillShape)
                            .drawSpecularHighlight(
                                shape = pillShape,
                                highlight = baseHighlight,
                                alpha = 0.85f
                            )
                            .then(interactiveHighlight.modifier)
                    } else {
                        Modifier
                            .shadow(
                                elevation = 6.dp,
                                shape = pillShape,
                                ambientColor = Color.Black.copy(alpha = 0.12f),
                                spotColor = Color.Black.copy(alpha = 0.18f)
                            )
                            .clip(pillShape)
                            .background(containerColor, pillShape)
                            .then(interactiveHighlight.modifier)
                    }
                )
        )

        // 2. Navigation section: drag gesture + sliding indicator + tab items
        Box(
            modifier = Modifier
                .fillMaxHeight()
                .width(navSectionWidthDp)
                .onGloballyPositioned { coords ->
                    navWidthPx = coords.size.width.toFloat()
                    val contentWidthPx = navWidthPx - with(density) { 8.dp.toPx() }
                    tabWidthPx = (contentWidthPx / tabsCount).coerceAtLeast(0f)
                }
                .pointerInput(tabWidthPx, navWidthPx, isLtr) {
                    awaitEachGesture {
                        val down = awaitFirstDown(requireUnconsumed = false)
                        isUserDragging = true
                        val downX = down.position.x
                        interactiveHighlight.press(down.position)
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

                                interactiveHighlight.updatePosition(change.position)

                                if (tabWidthPx > 0f) {
                                    val rawDelta = if (isLtr) dragAmount.x / tabWidthPx else -dragAmount.x / tabWidthPx
                                    val newTarget = dampedDragAnimation.targetValue + rawDelta
                                    val clampedTarget = newTarget.fastCoerceIn(0f, (tabsCount - 1).toFloat())
                                    dampedDragAnimation.updateValue(clampedTarget)

                                    // Rubber band: overshoot beyond the tabs nudges the whole pill
                                    val excess = (newTarget - clampedTarget) * tabWidthPx * if (isLtr) 1f else -1f
                                    if (excess != 0f || offsetAnimation.value != 0f) {
                                        animationScope.launch {
                                            offsetAnimation.snapTo(offsetAnimation.value + dragAmount.x * 0.4f)
                                        }
                                    }
                                }
                            } else {
                                // Pointer up
                                change.consume()
                                val upX = change.position.x
                                val targetIndex = if (!hasMoved) {
                                    // Tap gesture: pick tab by touch position
                                    if (isLtr) {
                                        if (upX < navWidthPx / 2f) 0 else 1
                                    } else {
                                        if (upX < navWidthPx / 2f) 1 else 0
                                    }.fastCoerceIn(0, tabsCount - 1)
                                } else {
                                    // Drag gesture: settle to closest tab
                                    dampedDragAnimation.targetValue.fastRoundToInt().fastCoerceIn(0, tabsCount - 1)
                                }

                                currentIndex = targetIndex
                                dampedDragAnimation.animateToValue(targetIndex.toFloat())
                                onPageSelected(targetIndex)

                                val finalCenter = Offset(
                                    if (isLtr) (targetIndex + 0.5f) * tabWidthPx + with(density) { 4.dp.toPx() }
                                    else navWidthPx - (targetIndex + 0.5f) * tabWidthPx - with(density) { 4.dp.toPx() },
                                    size.height / 2f
                                )
                                interactiveHighlight.release(finalCenter)
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
            // 2a. Sliding pill indicator
            if (tabWidthPx > 0f) {
                val tabWidthDp = with(density) { tabWidthPx.toDp() }
                if (isGlassEnabled) {
                    Box(
                        Modifier
                            .padding(start = 4.dp)
                            .graphicsLayer {
                                val progressOffset = dampedDragAnimation.value * tabWidthPx
                                translationX = if (isLtr) progressOffset + panelOffset else -progressOffset + panelOffset
                                scaleX = dampedDragAnimation.scaleX
                                scaleY = dampedDragAnimation.scaleY
                                // Velocity-driven squash & stretch
                                val velocity = dampedDragAnimation.velocity / 10f
                                scaleX /= 1f - (velocity * 0.75f).fastCoerceIn(-0.2f, 0.2f)
                                scaleY *= 1f - (velocity * 0.25f).fastCoerceIn(-0.2f, 0.2f)
                            }
                            .height(56.dp)
                            .width(tabWidthDp)
                            .clip(pillShape)
                            .background(
                                MaterialTheme.colorScheme.primaryContainer.copy(
                                    alpha = if (!isInDark) 0.68f else 0.75f
                                ),
                                pillShape
                            )
                            .drawSpecularHighlight(
                                shape = pillShape,
                                highlight = pillHighlight,
                                alpha = 0.90f
                            )
                            .innerShadow(shape = pillShape) {
                                InnerShadow(
                                    radius = 8.dp * dampedDragAnimation.pressProgress.coerceAtLeast(0.4f),
                                    color = Color.Black.copy(alpha = 0.18f),
                                    alpha = dampedDragAnimation.pressProgress.coerceAtLeast(0.4f),
                                )
                            }
                    ) {
                        // Specular lens sheen top gradient
                        Box(
                            modifier = Modifier
                                .fillMaxSize()
                                .clip(pillShape)
                                .background(
                                    Brush.verticalGradient(
                                        colors = listOf(
                                            Color.White.copy(alpha = if (isInDark) 0.22f else 0.35f),
                                            Color.Transparent
                                        ),
                                        startY = 0f,
                                        endY = with(density) { 28.dp.toPx() }
                                    )
                                )
                        )
                    }
                } else {
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
                            .background(MaterialTheme.colorScheme.primaryContainer, pillShape)
                    )
                }
            }

            // 2b. Foreground tab items (crisp text & icons with fluid interpolation)
            Row(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(4.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                FloatingBottomBarTab(
                    index = 0,
                    weight = tab0Weight,
                    pressProgress = dampedDragAnimation.pressProgress,
                    icon = Icons.Default.Home,
                    label = localizedText("首页"),
                    accentColor = if (isGlassEnabled) MaterialTheme.colorScheme.onPrimaryContainer else accentColor,
                    contentColor = tabContentColor,
                    onSelect = { onPageSelected(0) }
                )
                FloatingBottomBarTab(
                    index = 1,
                    weight = tab1Weight,
                    pressProgress = dampedDragAnimation.pressProgress,
                    icon = Icons.Default.Apps,
                    label = localizedText("功能中心"),
                    accentColor = if (isGlassEnabled) MaterialTheme.colorScheme.onPrimaryContainer else accentColor,
                    contentColor = tabContentColor,
                    onSelect = { onPageSelected(1) }
                )
            }
        }

    }
}

@Composable
private fun RowScope.FloatingBottomBarTab(
    index: Int,
    weight: Float,
    pressProgress: Float,
    icon: ImageVector,
    label: String,
    accentColor: Color,
    contentColor: Color,
    onSelect: () -> Unit,
    modifier: Modifier = Modifier
) {
    val dynamicColor = lerp(contentColor, accentColor, weight)
    val dynamicScale = 1f + 0.05f * weight * pressProgress

    Column(
        modifier = modifier
            .semantics {
                role = Role.Tab
                selected = weight > 0.5f
                onClick(label = label) { onSelect(); true }
            }
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
