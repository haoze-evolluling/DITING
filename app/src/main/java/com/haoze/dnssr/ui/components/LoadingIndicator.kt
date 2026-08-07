package com.haoze.dnssr.ui.components

import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.unit.dp

@Composable
fun MagSafeLoadingIndicator(
    trackColor: Color,
    modifier: Modifier = Modifier
) {
    val transition = rememberInfiniteTransition(label = "loadingRing")
    val rotation by transition.animateFloat(
        initialValue = 0f,
        targetValue = 360f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 2400),
            repeatMode = RepeatMode.Restart
        ),
        label = "ringRotation"
    )
    val pulse by transition.animateFloat(
        initialValue = 0.94f,
        targetValue = 1.04f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 1100, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse
        ),
        label = "ringPulse"
    )
    val haloAlpha by transition.animateFloat(
        initialValue = 0.18f,
        targetValue = 0.42f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 1100, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse
        ),
        label = "haloAlpha"
    )

    Canvas(
        modifier = modifier
            .size(176.dp)
            .graphicsLayer {
                scaleX = pulse
                scaleY = pulse
            }
    ) {
        val ringWidth = 12.dp.toPx()
        val radius = (size.minDimension - ringWidth) / 2f
        drawCircle(
            brush = Brush.radialGradient(
                colors = listOf(
                    Color(0xFF67FFD3).copy(alpha = haloAlpha),
                    Color(0xFF2DE7C0).copy(alpha = haloAlpha * 0.35f),
                    Color.Transparent
                )
            ),
            radius = size.minDimension / 2f
        )
        drawCircle(
            color = trackColor.copy(alpha = 0.12f),
            radius = radius,
            style = Stroke(width = ringWidth)
        )
        drawArc(
            brush = Brush.sweepGradient(
                colors = listOf(
                    Color(0xFF6CFFD5),
                    Color(0xFF31E8C3),
                    Color(0xFF1AA7FF),
                    Color(0xFF6CFFD5)
                )
            ),
            startAngle = rotation,
            sweepAngle = 285f,
            useCenter = false,
            style = Stroke(width = ringWidth, cap = StrokeCap.Round)
        )
    }
}
