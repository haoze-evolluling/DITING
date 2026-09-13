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
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner

data class DeviceTilt(
    val gravityX: Float = 0f,
    val gravityY: Float = -1f,
    val gravityZ: Float = 0f
)

/**
 * Normalized (by GRAVITY_EARTH) squared delta below which a reading is dropped.
 * Keeps a resting device from triggering recompositions for invisible jitter.
 */
private const val TILT_UPDATE_THRESHOLD_SQ = 1e-5f

/**
 * Gravity-driven tilt state used to steer the specular highlight light source.
 *
 * Sensor usage is strictly bounded to keep the cost negligible:
 * - the listener is registered only while [enabled] is true AND the host lifecycle
 *   is at least RESUMED (the consumer is composed on screen and the app is in
 *   the foreground);
 * - it is unregistered on ON_PAUSE and re-registered on ON_RESUME, so nothing
 *   listens while the app is backgrounded;
 * - registration is guarded (single listener per effect instance) and the
 *   effect is keyed on [enabled]/lifecycleOwner, so recompositions never stack
 *   duplicate registrations;
 * - readings below [TILT_UPDATE_THRESHOLD_SQ] are dropped to avoid redundant
 *   recompositions while the device rests.
 */
@Composable
fun rememberDeviceTilt(enabled: Boolean = true): State<DeviceTilt> {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val tiltState = remember { mutableStateOf(DeviceTilt()) }

    DisposableEffect(enabled, lifecycleOwner) {
        val sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as? SensorManager
        val sensor = sensorManager?.getDefaultSensor(Sensor.TYPE_GRAVITY)
            ?: sensorManager?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)

        var listener: SensorEventListener? = null

        fun register() {
            if (listener != null || sensorManager == null || sensor == null) return
            val newListener = object : SensorEventListener {
                override fun onSensorChanged(event: SensorEvent?) {
                    if (event == null || event.values.size < 2) return
                    val rawX = -event.values[0] / SensorManager.GRAVITY_EARTH
                    val rawY = event.values[1] / SensorManager.GRAVITY_EARTH
                    val rawZ = if (event.values.size >= 3) event.values[2] / SensorManager.GRAVITY_EARTH else 0f
                    val current = tiltState.value
                    val deltaX = rawX - current.gravityX
                    val deltaY = rawY - current.gravityY
                    if (deltaX * deltaX + deltaY * deltaY < TILT_UPDATE_THRESHOLD_SQ) return
                    tiltState.value = DeviceTilt(rawX, rawY, rawZ)
                }

                override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
            }
            listener = newListener
            sensorManager.registerListener(newListener, sensor, SensorManager.SENSOR_DELAY_UI)
        }

        fun unregister() {
            listener?.let { sensorManager?.unregisterListener(it) }
            listener = null
        }

        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_RESUME -> register()
                Lifecycle.Event.ON_PAUSE -> unregister()
                else -> Unit
            }
        }

        if (enabled) {
            lifecycleOwner.lifecycle.addObserver(observer)
            if (lifecycleOwner.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) {
                register()
            }
        }

        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
            unregister()
        }
    }
    return tiltState
}
