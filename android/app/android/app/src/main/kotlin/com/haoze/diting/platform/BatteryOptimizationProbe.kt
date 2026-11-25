package com.haoze.diting.platform

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.PowerManager

/**
 * 部分 ROM（如 HyperOS）从系统设置页返回的瞬间尚未把“忽略电池优化”同步给
 * PowerManager，立即读取会得到旧值。这里在有限时间内短间隔轮询，等待状态稳定。
 */
internal object BatteryOptimizationProbe {

    private const val POLL_INTERVAL_MS = 100L

    private const val POLL_TIMEOUT_MS = 1200L

    fun isIgnoring(context: Context): Boolean {
        val power = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
            ?: return false
        return power.isIgnoringBatteryOptimizations(context.packageName)
    }

    fun awaitSettled(context: Context, onSettled: (Boolean) -> Unit) {
        val handler = Handler(Looper.getMainLooper())
        val deadline = System.currentTimeMillis() + POLL_TIMEOUT_MS

        fun poll() {
            val granted = isIgnoring(context)
            if (granted || System.currentTimeMillis() >= deadline) {
                onSettled(granted)
            } else {
                handler.postDelayed(::poll, POLL_INTERVAL_MS)
            }
        }

        poll()
    }
}
