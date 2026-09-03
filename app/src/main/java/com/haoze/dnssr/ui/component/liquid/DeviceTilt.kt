package com.haoze.dnssr.ui.component.liquid

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.State
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext

data class DeviceTilt(
    val gravityX: Float = 0f,
    val gravityY: Float = -1f,
    val gravityZ: Float = 0f
)

// 传感器降频（视觉等效降耗）：tilt 仅驱动高光视差这类慢速动效，
// 10Hz 采样 + 指数低通即可保留原有的"液体阻尼"跟随感，
// 相比 SENSOR_DELAY_UI 减少约 40% 的传感器事件与随之而来的重组/重绘。
private const val TILT_SAMPLE_PERIOD_US = 100_000 // 10 Hz
private const val TILT_SMOOTHING_ALPHA = 0.45f

@Composable
fun rememberDeviceTilt(): State<DeviceTilt> {
    val context = LocalContext.current
    val tiltState = remember { mutableStateOf(DeviceTilt()) }
    DisposableEffect(context) {
        val sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as? SensorManager
        val sensor = sensorManager?.getDefaultSensor(Sensor.TYPE_GRAVITY)
            ?: sensorManager?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        if (sensorManager == null || sensor == null) {
            return@DisposableEffect onDispose {}
        }
        val listener = object : SensorEventListener {
            override fun onSensorChanged(event: SensorEvent?) {
                if (event != null && event.values.size >= 2) {
                    val rawX = event.values[0] / SensorManager.GRAVITY_EARTH
                    val rawY = event.values[1] / SensorManager.GRAVITY_EARTH
                    val rawZ = if (event.values.size >= 3) event.values[2] / SensorManager.GRAVITY_EARTH else 0f
                    // 低通滤波：降频后平滑过渡，稳态收敛到真实重力方向
                    val prev = tiltState.value
                    tiltState.value = DeviceTilt(
                        gravityX = prev.gravityX + (-rawX - prev.gravityX) * TILT_SMOOTHING_ALPHA,
                        gravityY = prev.gravityY + (rawY - prev.gravityY) * TILT_SMOOTHING_ALPHA,
                        gravityZ = prev.gravityZ + (rawZ - prev.gravityZ) * TILT_SMOOTHING_ALPHA
                    )
                }
            }
            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
        }
        sensorManager.registerListener(listener, sensor, TILT_SAMPLE_PERIOD_US)
        onDispose {
            sensorManager.unregisterListener(listener)
        }
    }
    return tiltState
}
