package com.haoze.diting.ui.components.cascade.internal

import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntRect
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.window.PopupPositionProvider
import androidx.compose.ui.window.PopupProperties

@Immutable
internal data class CoercePositiveValues(
    val delegate: PopupPositionProvider
) : PopupPositionProvider {

    override fun calculatePosition(
        anchorBounds: IntRect,
        windowSize: IntSize,
        layoutDirection: LayoutDirection,
        popupContentSize: IntSize
    ): IntOffset {
        val position = delegate.calculatePosition(
            anchorBounds = anchorBounds,
            windowSize = windowSize,
            layoutDirection = layoutDirection,
            popupContentSize = popupContentSize
        )
        return position.copy(
            x = maxOf(0, position.x),
            y = maxOf(0, position.y)
        )
    }

    companion object {
        internal fun correctMenuBounds(menuBounds: IntRect): IntRect {
            return menuBounds.translate(
                translateX = minOf(0, menuBounds.left) * -1,
                translateY = minOf(0, menuBounds.top) * -1
            )
        }
    }
}

internal class FixedPopupPositionProvider(
    private val position: IntOffset
) : PopupPositionProvider {
    override fun calculatePosition(
        anchorBounds: IntRect,
        windowSize: IntSize,
        layoutDirection: LayoutDirection,
        popupContentSize: IntSize
    ): IntOffset = position
}

internal fun PopupProperties.copy(
    usePlatformDefaultWidth: Boolean
): PopupProperties {
    return PopupProperties(
        focusable = focusable,
        dismissOnBackPress = dismissOnBackPress,
        dismissOnClickOutside = dismissOnClickOutside,
        securePolicy = securePolicy,
        excludeFromSystemGesture = excludeFromSystemGesture,
        clippingEnabled = clippingEnabled,
        usePlatformDefaultWidth = usePlatformDefaultWidth
    )
}

internal fun Modifier.clickableWithoutRipple(onClick: () -> Unit): Modifier = composed {
    clickable(
        indication = null,
        interactionSource = remember { MutableInteractionSource() },
        onClick = onClick
    )
}

internal inline fun Modifier.thenIf(predicate: Boolean, modifier: Modifier.() -> Modifier): Modifier {
    return if (predicate) modifier() else this
}
