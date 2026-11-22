package com.haoze.diting.watchdog

import android.content.Intent
import android.net.VpnService
import android.os.Handler
import android.os.Looper
import android.util.Log

class VpnReclaimer(
    private val service: VpnService,
    private val workMode: String,
    private val modeTitle: String,
    private val channelId: String,
    private val notificationId: Int,
    private val stopIntent: () -> Intent,
    private val restoreIntent: () -> Intent?,
    private val onWaitingChanged: (Boolean) -> Unit,
    private val onGiveUp: () -> Unit,
) : VpnChannelWatchdog.Listener {

    private var waiting = false
        set(value) {
            field = value
            onWaitingChanged(value)
        }

    private var watchdog: VpnChannelWatchdog? = null
    private val main = Handler(Looper.getMainLooper())

    @Volatile
    private var generation = 0

    fun shouldFollow(): Boolean = VpnWatchdogNative.shouldFollow(
        enabled = VpnChannelWatchdog.enabled(service),
        currentMode = VpnChannelWatchdog.workMode(service),
        expectedMode = workMode,
        hasIntent = restoreIntent() != null,
    )

    fun begin() {
        cancel()
        val token = generation
        show(VpnWatchNotification.Phase.CHECKING)
        main.post {
            if (token != generation) return@post
            waiting = true
            watchdog = VpnChannelWatchdog(service, this).also { it.start() }
            Log.i(TAG, "VPN revoked; watching the slot ($workMode)")
        }
    }

    fun cancel() {
        generation++
        watchdog?.stop()
        watchdog = null
        if (waiting) waiting = false
    }

    override fun onOccupied() = show(VpnWatchNotification.Phase.OCCUPIED)

    override fun onReleased() {
        val enabled = VpnChannelWatchdog.enabled(service)
        val currentMode = VpnChannelWatchdog.workMode(service)
        if (!VpnWatchdogNative.reclaimAllowed(enabled, currentMode, workMode)) {
            onUserDisconnect()
            return
        }
        val consentMissing = VpnService.prepare(service) != null
        val intent = if (consentMissing) null else restoreIntent()
        when (VpnWatchdogNative.reconnectDecision(
            enabled = enabled,
            currentMode = currentMode,
            expectedMode = workMode,
            consentMissing = consentMissing,
            hasIntent = intent != null,
        )) {
            VpnReconnectAction.NEEDS_CONSENT -> {
                Log.i(TAG, "slot free but consent is gone; waiting for the user")
                show(VpnWatchNotification.Phase.NEEDS_CONSENT)
            }
            VpnReconnectAction.GIVE_UP -> {
                cancel()
                onGiveUp()
            }
            VpnReconnectAction.RECONNECT -> {
                cancel()
                Log.i(TAG, "slot free; reconnecting")
                runCatching { service.startService(intent!!) }
                    .onFailure {
                        Log.w(TAG, "reconnect failed", it)
                        onGiveUp()
                    }
            }
            VpnReconnectAction.USER_DISCONNECT -> onUserDisconnect()
        }
    }

    override fun onUserDisconnect() {
        cancel()
        onGiveUp()
    }

    private fun show(phase: VpnWatchNotification.Phase) {
        VpnWatchNotification.show(
            context = service,
            channelId = channelId,
            notificationId = notificationId,
            modeTitle = modeTitle,
            stopIntent = stopIntent(),
            phase = phase,
        )
    }

    private companion object {
        const val TAG = "VpnReclaimer"
    }
}
