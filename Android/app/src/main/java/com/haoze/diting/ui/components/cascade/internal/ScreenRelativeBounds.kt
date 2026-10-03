package com.haoze.diting.ui.components.cascade.internal

import android.view.View
import androidx.compose.runtime.Immutable
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.findRootCoordinates
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.layout.positionInWindow
import androidx.compose.ui.unit.toSize
import androidx.core.graphics.Insets
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat.Type.ime

@Immutable
internal data class ScreenRelativeBounds(
    val boundsInRoot: Rect,
    val root: RootLayoutCoordinatesInfo,
) {
    val boundsInWindow: Rect
        get() = Rect(
            offset = boundsInRoot.topLeft + root.layoutPositionInWindow,
            size = boundsInRoot.size,
        )
}

@Immutable
internal data class ScreenRelativeOffset(
    val positionInWindow: Offset,
    val root: RootLayoutCoordinatesInfo,
) {
    val positionInRoot: Offset
        get() = positionInWindow - root.layoutPositionInWindow
}

@Immutable
internal data class RootLayoutCoordinatesInfo(
    val layoutPositionInWindow: Offset,
    val windowBoundsMinusIme: Rect,
)

internal fun ScreenRelativeBounds(coordinates: LayoutCoordinates, owner: View): ScreenRelativeBounds {
    val rootCoords = coordinates.findRootCoordinates()
    return ScreenRelativeBounds(
        boundsInRoot = Rect(
            offset = coordinates.positionInRoot(),
            size = coordinates.size.toSize()
        ),
        root = RootLayoutCoordinatesInfo(
            layoutPositionInWindow = rootCoords.positionInWindow(),
            windowBoundsMinusIme = owner.rootView.getBoundsOnScreenAsRoot().let { bounds ->
                val insets = ViewCompat.getRootWindowInsets(owner)?.getInsets(ime()) ?: Insets.NONE
                bounds.copy(
                    left = bounds.left + insets.left,
                    top = bounds.top + insets.top,
                    right = bounds.right - insets.right,
                    bottom = bounds.bottom - insets.bottom,
                )
            }
        )
    )
}

private fun View.getBoundsOnScreenAsRoot(): Rect {
    check(this === rootView)
    return Rect(
        offset = intArrayBuffer.let {
            getLocationOnScreen(it)
            Offset(x = it[0].toFloat(), y = it[1].toFloat())
        },
        size = Size(width.toFloat(), height.toFloat()),
    )
}

private val intArrayBuffer = IntArray(size = 2)

internal fun ScreenRelativeOffset.positionInWindowOf(other: ScreenRelativeBounds): Offset {
    return positionInRoot -
        (other.root.layoutPositionInWindow - root.layoutPositionInWindow) -
        (other.root.windowBoundsMinusIme.topLeft - root.windowBoundsMinusIme.topLeft)
}
