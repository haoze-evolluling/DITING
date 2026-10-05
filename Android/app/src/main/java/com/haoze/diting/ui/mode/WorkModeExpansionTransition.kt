package com.haoze.diting.ui.mode

import android.app.Activity
import android.os.Build
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.lerp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.util.lerp
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.Easing
import com.haoze.diting.ui.localizedText
import kotlin.math.roundToInt

/**
 * Material 3 Emphasized Decelerate non-linear easing curve.
 */
val MaterialEmphasizedDecelerate: Easing = CubicBezierEasing(0.05f, 0.7f, 0.1f, 1.0f)

/**
 * Bounds and corner radii of a mode card prior to expansion.
 */
data class WorkModeTransitionBounds(
    val bounds: Rect,
    val topRadius: Dp,
    val bottomRadius: Dp
)

/**
 * Disables window transition animations between activities across API versions.
 */
fun Activity.disableWindowTransitions() {
    if (Build.VERSION.SDK_INT >= 34) {
        overrideActivityTransition(Activity.OVERRIDE_TRANSITION_OPEN, 0, 0)
        overrideActivityTransition(Activity.OVERRIDE_TRANSITION_CLOSE, 0, 0)
    } else {
        @Suppress("DEPRECATION")
        overridePendingTransition(0, 0)
    }
}

/**
 * Applies a smooth window crossfade animation when closing this activity.
 */
fun Activity.overrideFadeTransition() {
    if (Build.VERSION.SDK_INT >= 34) {
        overrideActivityTransition(Activity.OVERRIDE_TRANSITION_OPEN, android.R.anim.fade_in, android.R.anim.fade_out)
        overrideActivityTransition(Activity.OVERRIDE_TRANSITION_CLOSE, android.R.anim.fade_in, android.R.anim.fade_out)
    } else {
        @Suppress("DEPRECATION")
        overridePendingTransition(android.R.anim.fade_in, android.R.anim.fade_out)
    }
}

/**
 * Applies a smooth window crossfade animation when opening this activity.
 */
fun Activity.overrideOpenFadeTransition() {
    if (Build.VERSION.SDK_INT >= 34) {
        overrideActivityTransition(Activity.OVERRIDE_TRANSITION_OPEN, android.R.anim.fade_in, android.R.anim.fade_out)
    } else {
        @Suppress("DEPRECATION")
        overridePendingTransition(android.R.anim.fade_in, android.R.anim.fade_out)
    }
}

/**
 * Overlay component that seamlessly expands a mode card to full screen with Material 3 morphing.
 */
@Composable
fun WorkModeExpansionOverlay(
    mode: AppWorkMode,
    startBounds: WorkModeTransitionBounds,
    containerSize: IntSize,
    progress: Float,
    modifier: Modifier = Modifier
) {
    if (containerSize.width <= 0 || containerSize.height <= 0) return

    val density = LocalDensity.current
    val containerWidth = containerSize.width.toFloat()
    val containerHeight = containerSize.height.toFloat()

    // 1. Boundary interpolation (card position to full container)
    val currentLeft = lerp(startBounds.bounds.left, 0f, progress)
    val currentTop = lerp(startBounds.bounds.top, 0f, progress)
    val currentRight = lerp(startBounds.bounds.right, containerWidth, progress)
    val currentBottom = lerp(startBounds.bounds.bottom, containerHeight, progress)

    val currentWidth = (currentRight - currentLeft).coerceAtLeast(0f)
    val currentHeight = (currentBottom - currentTop).coerceAtLeast(0f)

    val widthDp = with(density) { currentWidth.toDp() }
    val heightDp = with(density) { currentHeight.toDp() }

    // 2. Corner radius: Constant default card curvature (28dp on all 4 corners)
    val cardShape = RoundedCornerShape(28.dp)

    // 3. Color morphing (no shadow on card edges)
    val startContainerColor = MaterialTheme.colorScheme.surfaceContainerHigh
    val targetContainerColor = MaterialTheme.colorScheme.surface
    val currentColor = lerp(startContainerColor, targetContainerColor, progress)

    // 4. Content crossfade values (phased progression over 1000ms)
    val cardContentAlpha = (1f - progress / 0.35f).coerceIn(0f, 1f)
    val revealAlpha = ((progress - 0.35f) / 0.45f).coerceIn(0f, 1f)

    val modeAccent = when (mode) {
        AppWorkMode.NORMAL -> MaterialTheme.colorScheme.primary
        AppWorkMode.EXPRESS -> MaterialTheme.colorScheme.secondary
        AppWorkMode.DNS -> MaterialTheme.colorScheme.tertiary
    }

    Box(
        modifier = modifier
            .offset { IntOffset(currentLeft.roundToInt(), currentTop.roundToInt()) }
            .size(widthDp, heightDp)
    ) {
        Surface(
            shape = cardShape,
            color = currentColor,
            shadowElevation = 0.dp,
            modifier = Modifier.fillMaxSize()
        ) {
            Box(
                modifier = Modifier.fillMaxSize(),
                contentAlignment = Alignment.Center
            ) {
                // Layer 1: Dissolving original card content
                if (cardContentAlpha > 0.01f) {
                    Row(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(horizontal = 20.dp, vertical = 18.dp)
                            .graphicsLayer {
                                alpha = cardContentAlpha
                                scaleX = 1f + 0.04f * progress
                                scaleY = 1f + 0.04f * progress
                            },
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Icon(
                            imageVector = mode.icon,
                            contentDescription = null,
                            tint = modeAccent,
                            modifier = Modifier.size(26.dp)
                        )

                        Spacer(modifier = Modifier.width(16.dp))

                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                text = localizedText(mode.title),
                                style = MaterialTheme.typography.titleMedium,
                                fontWeight = FontWeight.SemiBold,
                                color = MaterialTheme.colorScheme.onSurface
                            )
                            Spacer(modifier = Modifier.height(4.dp))
                            Text(
                                text = localizedText(mode.summary),
                                style = MaterialTheme.typography.bodySmall.copy(
                                    fontSize = 11.sp,
                                    lineHeight = 15.sp
                                ),
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                }

                // Layer 2: Revealing target mode destination preview
                if (revealAlpha > 0.01f) {
                    Column(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(24.dp)
                            .graphicsLayer {
                                alpha = revealAlpha
                                scaleX = 0.94f + 0.06f * progress
                                scaleY = 0.94f + 0.06f * progress
                            },
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.Center
                    ) {
                        Surface(
                            shape = CircleShape,
                            color = modeAccent.copy(alpha = 0.12f),
                            modifier = Modifier.size(72.dp)
                        ) {
                            Box(
                                contentAlignment = Alignment.Center,
                                modifier = Modifier.fillMaxSize()
                            ) {
                                Icon(
                                    imageVector = mode.icon,
                                    contentDescription = null,
                                    tint = modeAccent,
                                    modifier = Modifier.size(36.dp)
                                )
                            }
                        }

                        Spacer(modifier = Modifier.height(18.dp))

                        Text(
                            text = localizedText(mode.title),
                            style = MaterialTheme.typography.titleLarge,
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.onSurface
                        )

                        Spacer(modifier = Modifier.height(6.dp))

                        Text(
                            text = localizedText("正在进入..."),
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }
        }
    }
}
