package com.haoze.dnssr.notification

import android.content.Context
import android.os.PowerManager
import com.haoze.dnssr.vpn.traffic.TrafficStatsManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * 负责在通知栏启用网速显示时，生命周期安全、带灭屏感知的网速变动采样控制器。
 */
class VpnSpeedMonitor(private val context: Context) {

    private var monitorJob: Job? = null

    /**
     * 启动网速变动监听协程。
     * @param scope 运行协程的 CoroutineScope（通常为 DnsVpnService 的 serviceScope）
     * @param isVpnActive 判断 VPN 是否仍处于活动状态
     * @param onSpeedChanged 当网速有实质变动时触发的回调
     */
    fun start(
        scope: CoroutineScope,
        isVpnActive: () -> Boolean,
        onSpeedChanged: () -> Unit
    ) {
        stop()
        if (!NotificationSettingsStore.isTrafficSpeedEnabled(context)) return

        monitorJob = scope.launch {
            val initialSnap = TrafficStatsManager.uiSnapshot.value
            var lastFormattedSpeed = VpnNotificationBuilder.formatTrafficSpeed(
                initialSnap.totalTxSpeedBps,
                initialSnap.totalRxSpeedBps
            )
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager

            while (isActive && isVpnActive()) {
                val isScreenOn = powerManager?.isInteractive ?: true
                if (!isScreenOn) {
                    delay(SCREEN_OFF_POLL_INTERVAL_MS)
                    continue
                }

                delay(SCREEN_ON_SAMPLE_INTERVAL_MS)

                val snap = TrafficStatsManager.uiSnapshot.value
                val formatted = VpnNotificationBuilder.formatTrafficSpeed(snap.totalTxSpeedBps, snap.totalRxSpeedBps)
                if (formatted != lastFormattedSpeed) {
                    lastFormattedSpeed = formatted
                    onSpeedChanged()
                }
            }
        }
    }

    /**
     * 停止网速变动监听。
     */
    fun stop() {
        monitorJob?.cancel()
        monitorJob = null
    }

    companion object {
        private const val SCREEN_ON_SAMPLE_INTERVAL_MS = 2000L
        private const val SCREEN_OFF_POLL_INTERVAL_MS = 15000L
    }
}
