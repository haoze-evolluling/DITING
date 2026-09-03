package com.haoze.dnssr.ui.component.liquid

import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Outline
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.drawOutline
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

@Immutable
data class LightPosition(val x: Float, val y: Float, val z: Float)

@Immutable
data class LightSource(
    val position: LightPosition,
    val color: Color = Color.White,
    val intensity: Float = 1f
)

@Immutable
data class BloomStroke(
    val color: Color = Color.White.copy(alpha = 0.12f),
    val innerBlurRadius: Dp = 2.0.dp,
    val primaryLight: LightSource = LightSource(LightPosition(0.5f, -0.3f, -0.05f), Color.White, 1f),
    val secondaryLight: LightSource = LightSource(LightPosition(0.5f, 0.8f, -0.5f), Color.White, 0.4f),
    val dualPeak: Boolean = true
)

@Immutable
data class SpecularHighlight(
    val width: Dp = 1.dp,
    val alpha: Float = 1f,
    val style: BloomStroke = BloomStroke()
)

val IosIndicatorSpecular = SpecularHighlight(
    width = 1.dp,
    alpha = 1f,
    style = BloomStroke(
        color = Color.White.copy(alpha = 0.12f),
        innerBlurRadius = 2.0.dp,
        primaryLight = LightSource(
            position = LightPosition(0.5f, -0.3f, -0.05f),
            color = Color.White,
            intensity = 1f,
        ),
        secondaryLight = LightSource(
            position = LightPosition(0.5f, 0.8f, -0.5f),
            color = Color.White,
            intensity = 0.4f,
        ),
        dualPeak = true,
    )
)

private const val LIGHT_REF_X = 0.5f
private const val LIGHT_REF_Y = 0.7f
private const val GRAVITY_DIR_THRESHOLD_SQ = 0.01f

@Composable
fun rememberGravityRotatedHighlight(
    base: SpecularHighlight,
    extraDegrees: Float = 0f,
): SpecularHighlight {
    val baseStyle = base.style
    val tilt by rememberDeviceTilt()
    val rotatedPrimary = remember(tilt, baseStyle.primaryLight, extraDegrees) {
        val basePrimary = baseStyle.primaryLight
        val gx = tilt.gravityX
        val gy = tilt.gravityY
        val gMagSq = gx * gx + gy * gy
        val (lx0, ly0) = if (gMagSq > GRAVITY_DIR_THRESHOLD_SQ) {
            val invMag = 1f / sqrt(gMagSq)
            (gx * invMag) to (gy * invMag)
        } else {
            0f to -1f
        }
        val rad = extraDegrees * PI / 180.0
        val c = cos(rad).toFloat()
        val s = sin(rad).toFloat()
        val lx = c * lx0 - s * ly0
        val ly = s * lx0 + c * ly0
        basePrimary.copy(
            position = LightPosition(
                x = LIGHT_REF_X + lx,
                y = LIGHT_REF_Y + ly,
                z = basePrimary.position.z,
            ),
        )
    }
    return remember(base, rotatedPrimary) {
        base.copy(style = baseStyle.copy(primaryLight = rotatedPrimary))
    }
}

fun Modifier.drawSpecularHighlight(
    shape: Shape,
    highlight: SpecularHighlight,
    alpha: Float = 1f
): Modifier = this.drawWithContent {
    drawContent()
    if (alpha <= 0f) return@drawWithContent

    val strokeWidthPx = highlight.width.toPx()
    val outline = shape.createOutline(size, layoutDirection, this)

    val primaryPos = highlight.style.primaryLight.position
    val primaryIntensity = highlight.style.primaryLight.intensity * highlight.alpha * alpha
    val secondaryIntensity = if (highlight.style.dualPeak) {
        highlight.style.secondaryLight.intensity * highlight.alpha * alpha
    } else 0f

    // Calculate dynamic gradient angle from light position
    val startOffset = Offset(
        x = size.width * (0.5f - (primaryPos.x - 0.5f) * 0.8f),
        y = size.height * (0.5f - (primaryPos.y - 0.5f) * 0.8f)
    )
    val endOffset = Offset(
        x = size.width * (0.5f + (primaryPos.x - 0.5f) * 0.8f),
        y = size.height * (0.5f + (primaryPos.y - 0.5f) * 0.8f)
    )

    val brush = Brush.linearGradient(
        colors = listOf(
            Color.White.copy(alpha = (0.55f * primaryIntensity).coerceIn(0f, 1f)),
            Color.White.copy(alpha = (0.12f * primaryIntensity).coerceIn(0f, 1f)),
            Color.White.copy(alpha = (0.05f * secondaryIntensity).coerceIn(0f, 1f)),
            Color.White.copy(alpha = (0.35f * secondaryIntensity).coerceIn(0f, 1f))
        ),
        start = startOffset,
        end = endOffset
    )

    drawOutline(
        outline = outline,
        brush = brush,
        style = Stroke(width = strokeWidthPx),
        blendMode = BlendMode.Plus
    )
}
