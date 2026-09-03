package com.haoze.dnssr.ui.component.liquid

import android.graphics.RuntimeShader
import android.os.Build
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.VectorConverter
import androidx.compose.animation.core.VisibilityThreshold
import androidx.compose.animation.core.spring
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ShaderBrush
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.util.fastCoerceIn
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/**
 * KernelSU Interactive Highlight with AGSL luminous touch tracking.
 */
class InteractiveHighlight(
    val animationScope: CoroutineScope,
    val position: (size: Size, offset: Offset) -> Offset = { _, offset -> offset }
) {
    private val pressProgressAnimationSpec = spring(0.5f, 300f, 0.001f)
    private val positionAnimationSpec = spring(0.5f, 300f, Offset.VisibilityThreshold)

    private val pressProgressAnimation = Animatable(0f, 0.001f)
    private val positionAnimation = Animatable(Offset.Zero, Offset.VectorConverter, Offset.VisibilityThreshold)

    private var startPosition = Offset.Zero
    val offset: Offset get() = positionAnimation.value - startPosition
    val pressProgress: Float get() = pressProgressAnimation.value
    val currentPosition: Offset get() = positionAnimation.value

    private val shader: RuntimeShader? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        runCatching {
            RuntimeShader(
                """
                uniform float2 size;
                layout(color) uniform half4 color;
                uniform float radius;
                uniform float2 position;
                
                half4 main(float2 coord) {
                    float dist = distance(coord, position);
                    float intensity = smoothstep(radius, radius * 0.4, dist);
                    return color * intensity;
                }
                """.trimIndent()
            )
        }.getOrNull()
    } else null

    fun press(downPosition: Offset) {
        startPosition = downPosition
        animationScope.launch {
            launch { pressProgressAnimation.animateTo(1f, pressProgressAnimationSpec) }
            launch { positionAnimation.snapTo(downPosition) }
        }
    }

    fun updatePosition(pos: Offset) {
        animationScope.launch {
            positionAnimation.snapTo(pos)
        }
    }

    fun release(targetPosition: Offset? = null) {
        val target = targetPosition ?: startPosition
        animationScope.launch {
            launch { pressProgressAnimation.animateTo(0f, pressProgressAnimationSpec) }
            launch { positionAnimation.animateTo(target, positionAnimationSpec) }
        }
    }

    fun cancel() {
        animationScope.launch {
            launch { pressProgressAnimation.animateTo(0f, pressProgressAnimationSpec) }
            launch { positionAnimation.animateTo(startPosition, positionAnimationSpec) }
        }
    }

    val modifier: Modifier = Modifier.drawWithContent {
        val progress = pressProgressAnimation.value
        if (progress > 0.001f) {
            drawRect(
                Color.White.copy(0.06f * progress),
                blendMode = BlendMode.Plus
            )
            val pos = position(size, positionAnimation.value)
            val clampedPos = Offset(
                pos.x.fastCoerceIn(0f, size.width),
                pos.y.fastCoerceIn(0f, size.height)
            )
            val radius = size.minDimension * 1.35f

            if (shader != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                shader.apply {
                    setFloatUniform("size", size.width, size.height)
                    setColorUniform("color", Color.White.copy(0.18f * progress).toArgb())
                    setFloatUniform("radius", radius)
                    setFloatUniform("position", clampedPos.x, clampedPos.y)
                }
                drawRect(
                    ShaderBrush(shader),
                    blendMode = BlendMode.Plus
                )
            } else {
                drawCircle(
                    brush = Brush.radialGradient(
                        colors = listOf(
                            Color.White.copy(alpha = 0.18f * progress),
                            Color.Transparent
                        ),
                        center = clampedPos,
                        radius = radius
                    ),
                    radius = radius,
                    center = clampedPos,
                    blendMode = BlendMode.Plus
                )
            }
        }
        drawContent()
    }

    val gestureModifier: Modifier = Modifier.pointerInput(animationScope) {
        inspectDragGestures(
            onDragStart = { down ->
                press(down.position)
            },
            onDragEnd = {
                release()
            },
            onDragCancel = {
                cancel()
            }
        ) { change, _ ->
            updatePosition(change.position)
        }
    }
}
