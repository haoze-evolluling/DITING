package com.haoze.diting.normal

import android.content.Context
import android.os.PowerManager

/// Ticks the notification's speed line; a daemon thread, as this module has no coroutines.
internal class SpeedTicker(
    private val context: Context,
    private val active: () -> Boolean,
    private val onTick: () -> Unit,
) {
    @Volatile
    private var thread: Thread? = null

    fun start() {
        if (thread != null) return
        thread = Thread({
            val power = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
            while (active()) {
                val onScreen = power?.isInteractive ?: true
                try {
                    Thread.sleep(if (onScreen) SCREEN_ON_INTERVAL_MS else SCREEN_OFF_INTERVAL_MS)
                } catch (interrupted: InterruptedException) {
                    return@Thread
                }
                onTick()
            }
        }, "diting-speed-ticker").apply {
            isDaemon = true
            start()
        }
    }

    fun stop() {
        thread?.interrupt()
        thread = null
    }

    private companion object {
        /// Speed refresh cadence: 1 s with the screen on (the readout is per-second), 10 s off
        const val SCREEN_ON_INTERVAL_MS = 1000L
        const val SCREEN_OFF_INTERVAL_MS = 10_000L
    }
}
