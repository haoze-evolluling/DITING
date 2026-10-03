package com.haoze.diting.ui.components.cascade

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.MutableTransitionState
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.requiredWidth
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.surfaceColorAtElevation
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupProperties
import com.haoze.diting.ui.components.cascade.internal.AnimateEntryExit
import com.haoze.diting.ui.components.cascade.internal.CoercePositiveValues
import com.haoze.diting.ui.components.cascade.internal.DropdownMenuPositionProvider
import com.haoze.diting.ui.components.cascade.internal.FixedPopupPositionProvider
import com.haoze.diting.ui.components.cascade.internal.PositionPopupContent
import com.haoze.diting.ui.components.cascade.internal.ScreenRelativeBounds
import com.haoze.diting.ui.components.cascade.internal.calculateTransformOrigin
import com.haoze.diting.ui.components.cascade.internal.cascadeTransitionSpec
import com.haoze.diting.ui.components.cascade.internal.clickableWithoutRipple
import com.haoze.diting.ui.components.cascade.internal.copy
import com.haoze.diting.ui.components.cascade.internal.thenIf
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.onEach

/**
 * 谛听 Cascade 风格 Compose 下拉菜单组件。
 *
 * 具有精准锚点定位、基于触发点的缩放揭开动画、无缝级联子菜单过渡，
 * 并与 Material 3 动态色彩体系及阴影体系完美融合。
 */
@Composable
fun CascadeDropdownMenu(
    expanded: Boolean,
    onDismissRequest: () -> Unit,
    modifier: Modifier = Modifier,
    offset: DpOffset = DpOffset.Zero,
    fixedWidth: Dp? = CascadeDefaults.menuWidth,
    shadowElevation: Dp = CascadeDefaults.shadowElevation,
    tonalElevation: Dp = CascadeDefaults.tonalElevation,
    properties: PopupProperties = PopupProperties(focusable = true),
    state: CascadeState = rememberCascadeState(),
    shape: Shape = CascadeDefaults.shape,
    content: @Composable CascadeColumnScope.() -> Unit
) {
    val expandedStates = remember { MutableTransitionState(false) }
    expandedStates.targetState = expanded

    if (expandedStates.currentState || expandedStates.targetState) {
        val transformOriginState = remember { mutableStateOf(TransformOrigin.Center) }
        val popupPositionProvider = CoercePositiveValues(
            DropdownMenuPositionProvider(
                offset,
                LocalDensity.current
            ) { parentBounds, menuBounds ->
                transformOriginState.value = calculateTransformOrigin(
                    parentBounds = parentBounds,
                    menuBounds = CoercePositiveValues.correctMenuBounds(menuBounds)
                )
            }
        )

        val anchorHostView = LocalView.current
        var anchorBounds: ScreenRelativeBounds? by remember { mutableStateOf(null) }
        Box(
            Modifier.onGloballyPositioned { coordinates ->
                val parentCoords = coordinates.parentLayoutCoordinates ?: coordinates
                anchorBounds = ScreenRelativeBounds(parentCoords, owner = anchorHostView)
            }
        )

        Popup(
            onDismissRequest = onDismissRequest,
            properties = properties.copy(usePlatformDefaultWidth = false),
            popupPositionProvider = remember { FixedPopupPositionProvider(IntOffset.Zero) }
        ) {
            PositionPopupContent(
                modifier = Modifier
                    .fillMaxSize()
                    .thenIf(properties.dismissOnClickOutside) {
                        clickableWithoutRipple(onClick = onDismissRequest)
                    },
                positionProvider = popupPositionProvider,
                anchorBounds = anchorBounds,
                properties = properties,
            ) {
                AnimateEntryExit(
                    modifier = Modifier
                        .clickableWithoutRipple {}
                        .then(modifier),
                    expandedStates = expandedStates,
                    transformOriginState = transformOriginState,
                    shadowElevation = shadowElevation,
                    shape = shape,
                ) {
                    CascadeDropdownMenuContent(
                        state = state,
                        fixedWidth = fixedWidth,
                        tonalElevation = tonalElevation,
                        shape = shape,
                        content = content
                    )
                }
            }
        }
    }
}

@Composable
private fun CascadeDropdownMenuContent(
    state: CascadeState,
    fixedWidth: Dp?,
    tonalElevation: Dp,
    shape: Shape,
    modifier: Modifier = Modifier,
    content: @Composable CascadeColumnScope.() -> Unit,
) {
    DisposableEffect(Unit) {
        onDispose {
            state.resetBackStack()
        }
    }

    val widthModifier = if (fixedWidth != null) {
        Modifier.requiredWidth(fixedWidth)
    } else {
        Modifier.widthIn(min = CascadeDefaults.minWidth)
    }

    Surface(
        modifier = widthModifier.then(modifier),
        shape = shape,
        color = MaterialTheme.colorScheme.surface,
        tonalElevation = tonalElevation,
    ) {
        val isTransitionRunning = remember { MutableStateFlow(false) }
        val backStackSnapshot by remember {
            snapshotFlow { state.backStackSnapshot() }
                .onEach {
                    isTransitionRunning.first { running -> !running }
                }
        }.collectAsState(initial = state.backStackSnapshot())

        val layoutDirection = LocalLayoutDirection.current
        AnimatedContent(
            targetState = backStackSnapshot,
            transitionSpec = { cascadeTransitionSpec(layoutDirection) },
            label = "cascadeAnimation"
        ) { snapshot ->
            Column(
                Modifier
                    .background(MaterialTheme.colorScheme.surfaceColorAtElevation(tonalElevation))
                    .verticalScroll(rememberScrollState())
            ) {
                val contentScope = remember(this, snapshot) {
                    object : CascadeColumnScope, ColumnScope by this {
                        override val cascadeState get() = state
                        override val hasParentMenu: Boolean get() = snapshot.hasParentMenu()
                        override val isNavigationRunning: Boolean get() = isTransitionRunning.value
                    }
                }
                val currentContent = snapshot.topMostEntry?.childrenContent ?: content
                with(contentScope) {
                    snapshot.topMostEntry?.header?.invoke(contentScope)
                    currentContent()
                }
            }

            LaunchedEffect(transition.isRunning) {
                isTransitionRunning.tryEmit(transition.isRunning)
            }
        }
    }
}
