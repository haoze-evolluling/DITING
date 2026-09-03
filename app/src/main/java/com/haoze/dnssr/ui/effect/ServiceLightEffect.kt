package com.haoze.dnssr.ui.effect

import android.graphics.RuntimeShader
import android.os.Build
import androidx.annotation.RequiresApi
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.ShaderBrush
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.platform.LocalConfiguration
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.sin

const val SERVICE_LIGHT_EFFECT_MIN_API = Build.VERSION_CODES.TIRAMISU

fun isServiceLightEffectSupported(): Boolean = Build.VERSION.SDK_INT >= SERVICE_LIGHT_EFFECT_MIN_API

// 帧率治理（视觉等效降耗，无 UI 开关）
// 特效在巡航态（reveal 展开完成、持续显示）是慢速渐变 + 极慢光点漂移
// （角速度 ≤ 0.4 rad/s），20fps 步进与逐帧渲染无可感知差异，GPU 负载大幅下降。
// reveal 展开/收起动画（<1s，视觉焦点）保持逐帧，避免扩散边缘出现台阶感。
// 若验证发现可感知差异，将 FRAME_THROTTLING 置 false 一键回退原逐帧路径。
private const val SERVICE_LIGHT_EFFECT_FRAME_THROTTLING = true
private const val SERVICE_LIGHT_EFFECT_CRUISE_FRAME_INTERVAL_MS = 50L // 20fps

/**
 * Full-screen moving light adapted from Hyper-pick-up-code's OS3 background effect.
 * The reveal mask is centered on the service button so start and stop feel spatially connected.
 */
@Composable
fun ServiceLightEffect(
    visible: Boolean,
    revealOrigin: Offset,
    modifier: Modifier = Modifier
) {
    if (!isServiceLightEffectSupported()) return
    ServiceLightEffectApi33(
        visible = visible,
        revealOrigin = revealOrigin,
        modifier = modifier
    )
}

@RequiresApi(Build.VERSION_CODES.TIRAMISU)
@Composable
private fun ServiceLightEffectApi33(
    visible: Boolean,
    revealOrigin: Offset,
    modifier: Modifier
) {
    val reveal = remember { Animatable(if (visible) 1f else 0f) }
    var animationTime by remember { mutableFloatStateOf(0f) }
    // 节流后的渲染快照：Canvas 只读这两个状态，巡航态 20fps 步进时
    // 中间的 Choreographer 帧不再触发重组/重绘（GPU 零工作）
    var renderedColorStage by remember { mutableFloatStateOf(0f) }
    // Use the app's resolved Material theme, which may differ from the system theme.
    val darkTheme = MaterialTheme.colorScheme.surface.luminance() < 0.5f
    val configuration = LocalConfiguration.current
    val deviceType = if (configuration.screenWidthDp >= 600) {
        ServiceLightDeviceType.PAD
    } else {
        ServiceLightDeviceType.PHONE
    }
    val preset = remember(deviceType, darkTheme) {
        ServiceLightConfigs.get(deviceType, darkTheme)
    }
    val painter = remember { ServiceLightPainter() }
    val colorStage = remember { Animatable(0f) }
    val lifecycleOwner = LocalLifecycleOwner.current

    LaunchedEffect(visible) {
        reveal.animateTo(
            targetValue = if (visible) 1f else 0f,
            animationSpec = tween(
                durationMillis = if (visible) 720 else 520,
                easing = FastOutSlowInEasing
            )
        )
    }

    LaunchedEffect(preset, visible, lifecycleOwner) {
        if (!visible) return@LaunchedEffect
        lifecycleOwner.lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) {
            var targetStage = floor(colorStage.value) + 1f
            while (isActive) {
                delay((preset.colorInterpPeriod * 500).toLong())
                colorStage.animateTo(
                    targetValue = targetStage,
                    animationSpec = spring(dampingRatio = 0.9f, stiffness = 35f)
                )
                targetStage += 1f
            }
        }
    }

    val shouldAnimate = visible || reveal.value > 0f
    LaunchedEffect(shouldAnimate, lifecycleOwner) {
        if (!shouldAnimate) return@LaunchedEffect
        lifecycleOwner.lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) {
            val startNanos = withFrameNanos { it }
            val startTime = animationTime
            var lastRenderNanos = 0L
            while (isActive) {
                // reveal 过渡态全帧率；巡航态用 delay 休眠步进，避免 Choreographer 逐帧唤醒
                val settled = visible && reveal.value >= 1f
                if (SERVICE_LIGHT_EFFECT_FRAME_THROTTLING && settled) {
                    delay(SERVICE_LIGHT_EFFECT_CRUISE_FRAME_INTERVAL_MS)
                    val now = System.nanoTime()
                    animationTime = startTime + (now - startNanos) / 1_000_000_000f
                    renderedColorStage = colorStage.value
                } else {
                    val now = withFrameNanos { it }
                    animationTime = startTime + (now - startNanos) / 1_000_000_000f
                    renderedColorStage = colorStage.value
                }
            }
        }
    }

    if (reveal.value <= 0f && !visible) return

    Canvas(modifier = modifier) {
        painter.draw(
            scope = this,
            time = animationTime,
            revealProgress = reveal.value,
            revealOrigin = revealOrigin.takeIf { it.x.isFinite() && it.y.isFinite() } ?: center,
            preset = preset,
            colorStage = renderedColorStage
        )
    }
}

@RequiresApi(Build.VERSION_CODES.TIRAMISU)
private class ServiceLightPainter {
    private val shader = RuntimeShader(SERVICE_LIGHT_SHADER)
    private val brush = ShaderBrush(shader)
    private val points = FloatArray(12)
    private val movingPoints = FloatArray(8)
    private val colors = FloatArray(16)

    fun draw(
        scope: DrawScope,
        time: Float,
        revealProgress: Float,
        revealOrigin: Offset,
        preset: ServiceLightConfig,
        colorStage: Float
    ) = with(scope) {
        val origin = Offset(
            x = revealOrigin.x.coerceIn(0f, size.width),
            y = revealOrigin.y.coerceIn(0f, size.height)
        )
        val maxRadius = maxOf(
            hypot(origin.x, origin.y),
            hypot(size.width - origin.x, origin.y),
            hypot(origin.x, size.height - origin.y),
            hypot(size.width - origin.x, size.height - origin.y)
        )

        updatePoints(time, preset)
        updateColors(preset, colorStage)
        shader.setFloatUniform("uResolution", size.width, size.height)
        shader.setFloatUniform("uAnimTime", time)
        shader.setFloatUniform("uBound", 0f, 0f, 1f, 1f)
        shader.setFloatUniform("uTranslateY", 0f)
        shader.setFloatUniform("uPoints", points)
        shader.setFloatUniform("uPointsAnim", movingPoints)
        shader.setFloatUniform("uColors", colors)
        shader.setFloatUniform("uAlphaMulti", 1f)
        shader.setFloatUniform("uPointRadiusMulti", 1f)
        shader.setFloatUniform("uRevealOrigin", origin.x, origin.y)
        shader.setFloatUniform("uRevealRadius", maxRadius * revealProgress)
        shader.setFloatUniform("uRevealFeather", 42f)
        shader.setFloatUniform("uNoiseScale", 1.5f)
        shader.setFloatUniform("uLightOffset", preset.lightOffset)
        shader.setFloatUniform("uSaturateOffset", preset.saturateOffset)

        drawRect(brush = brush)
    }

    private fun updatePoints(time: Float, preset: ServiceLightConfig) {
        preset.points.copyInto(points)
        for (i in 0 until 4) {
            val baseX = preset.points[i * 3]
            val baseY = preset.points[i * 3 + 1]
            val angle = time * (1f + i * 0.3f) * preset.pointOffset
            movingPoints[i * 2] = baseX + sin(angle) * 0.1f
            movingPoints[i * 2 + 1] = baseY + cos(angle) * 0.1f
        }
    }

    private fun updateColors(preset: ServiceLightConfig, stage: Float) {
        val intStage = stage.toInt()
        val fraction = stage - intStage
        val paletteA = when (intStage % 3) {
            0 -> preset.colors1
            1 -> preset.colors2
            else -> preset.colors3
        }
        val paletteB = when ((intStage + 1) % 3) {
            0 -> preset.colors1
            1 -> preset.colors2
            else -> preset.colors3
        }
        for (i in colors.indices) {
            colors[i] = paletteA[i] + (paletteB[i] - paletteA[i]) * fraction
        }
    }
}

private const val SERVICE_LIGHT_SHADER = """
uniform vec2 uResolution;
uniform float uAnimTime;
uniform vec4 uBound;
uniform float uTranslateY;
uniform vec3 uPoints[4];
uniform vec2 uPointsAnim[4];
uniform vec4 uColors[4];
uniform float uAlphaMulti;
uniform float uPointRadiusMulti;
uniform vec2 uRevealOrigin;
uniform float uRevealRadius;
uniform float uRevealFeather;
uniform float uNoiseScale;
uniform float uSaturateOffset;
uniform float uLightOffset;

vec3 rgb2hsv(vec3 c) {
    vec4 K = vec4(0.0, -0.3333333, 0.6666667, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
}

vec3 hsv2rgb(vec3 c) {
    vec3 p = abs(fract(c.xxx + vec3(1.0, 0.6666667, 0.3333333)) * 6.0 - 3.0);
    return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

float hash(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.13);
    p3 += dot(p3, p3.yzx + 3.333);
    return fract((p3.x + p3.y) * p3.z);
}

float perlin(vec2 x) {
    vec2 i = floor(x);
    vec2 f = fract(x);
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) +
        (d - b) * u.x * u.y;
}

float gradientNoise(vec2 uv) {
    return fract(52.9829189 * fract(dot(uv, vec2(0.06711056, 0.00583715))));
}

vec4 main(vec2 fragCoord) {
    vec2 vUv = fragCoord / uResolution;
    vUv.y = 1.0 - vUv.y;
    vec2 uv = vUv;
    uv -= vec2(0.0, uTranslateY);
    uv.xy -= uBound.xy;
    uv.xy /= uBound.zw;

    vec4 color = vec4(0.0);
    float noiseValue = perlin(vUv * uNoiseScale + vec2(-uAnimTime, -uAnimTime));

    for (int i = 0; i < 4; i++) {
        vec4 pointColor = uColors[i];
        pointColor.rgb *= pointColor.a;
        vec2 point = uPointsAnim[i];
        float radius = uPoints[i].z * uPointRadiusMulti;
        float influence = smoothstep(radius, 0.0, distance(uv, point));
        color.rgb = mix(color.rgb, pointColor.rgb, influence);
        color.a = mix(color.a, pointColor.a, influence);
    }

    color.rgb /= color.a;
    float oppositeNoise = smoothstep(0.0, 1.0, noiseValue);
    vec3 hsv = rgb2hsv(color.rgb);
    hsv.y = mix(hsv.y, 0.0, oppositeNoise * uSaturateOffset);
    color.rgb = hsv2rgb(hsv);
    color.rgb += oppositeNoise * uLightOffset;

    float reveal = smoothstep(
        uRevealRadius + uRevealFeather,
        uRevealRadius - uRevealFeather,
        distance(fragCoord, uRevealOrigin)
    );
    color.a = clamp(color.a, 0.0, 1.0) * uAlphaMulti * reveal;
    color += (10.0 / 255.0) * gradientNoise(fragCoord) - (5.0 / 255.0);
    return vec4(color.rgb * color.a, color.a);
}
"""
