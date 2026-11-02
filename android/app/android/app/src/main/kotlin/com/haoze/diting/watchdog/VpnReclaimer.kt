package com.haoze.diting.watchdog

import android.content.Intent
import android.net.VpnService
import android.os.Handler
import android.os.Looper
import android.util.Log

/// Glue between a VpnService and [VpnChannelWatchdog]: decides whether a revoke is followed, keeps
/// the waiting notification current and replays the last start intent once the slot is free.
///
/// The owning service tears its tunnel down but stays started and in the foreground while
/// [waiting], so it is still alive when the slot comes back.
class VpnReclaimer(
    private val service: VpnService,
    /// `app_work_mode` value this service belongs to; a revoke in another mode is not followed.
    private val workMode: String,
    private val modeTitle: String,
    private val channelId: String,
    private val notificationId: Int,
    private val stopIntent: () -> Intent,
    private val restoreIntent: () -> Intent?,
    /// Mirrors [waiting] into the service's static status, read by the Dart side.
    private val onWaitingChanged: (Boolean) -> Unit,
    /// Called on the main thread when the wait ends without a reconnect; the service stops.
    private val onGiveUp: () -> Unit,
) : VpnChannelWatchdog.Listener {

    private var waiting = false
        set(value) {
            field = value
            onWaitingChanged(value)
        }

    private var watchdog: VpnChannelWatchdog? = null
    private val main = Handler(Looper.getMainLooper())

    /// Bumped by [cancel], so a [begin] still queued from the binder thread cannot outlive it.
    @Volatile
    private var generation = 0

    /// Whether a revoke should be followed: the switch is on, this service belongs to the
    /// current mode and there is a start config to replay. When true the caller tears the tunnel
    /// down without stopping the service, skips `super.onRevoke()` (it calls stopSelf) and then
    /// calls [begin].
    fun shouldFollow(): Boolean =
        VpnChannelWatchdog.enabled(service) &&
            VpnChannelWatchdog.workMode(service) == workMode &&
            restoreIntent() != null

    /// Safe from any thread: `onRevoke` arrives on a binder thread, the watchdog lives on main.
    fun begin() {
        cancel()
        val token = generation
        // Posted before the hop so the foreground notification changes right away.
        show(VpnWatchNotification.Phase.CHECKING)
        main.post {
            if (token != generation) return@post
            waiting = true
            watchdog = VpnChannelWatchdog(service, this).also { it.start() }
            Log.i(TAG, "VPN revoked; watching the slot ($workMode)")
        }
    }

    /// Any explicit start or stop ends the wait. Main thread only, apart from the no-op case.
    fun cancel() {
        generation++
        watchdog?.stop()
        watchdog = null
        if (waiting) waiting = false
    }

    override fun onOccupied() = show(VpnWatchNotification.Phase.OCCUPIED)

    override fun onReleased() {
        // The user switched modes meanwhile; reconnecting would start the wrong data plane.
        if (VpnChannelWatchdog.workMode(service) != workMode || !VpnChannelWatchdog.enabled(service)) {
            onUserDisconnect()
            return
        }
        // Pre-consented apps are silently re-prepared here, which is what makes the reconnect
        // automatic. The watchdog only calls this once the slot is free, so nobody is displaced.
        if (VpnService.prepare(service) != null) {
            Log.i(TAG, "slot free but consent is gone; waiting for the user")
            show(VpnWatchNotification.Phase.NEEDS_CONSENT)
            return
        }
        val intent = restoreIntent()
        cancel()
        if (intent == null) {
            onGiveUp()
            return
        }
        Log.i(TAG, "slot free; reconnecting")
        runCatching { service.startService(intent) }
            .onFailure {
                Log.w(TAG, "reconnect failed", it)
                onGiveUp()
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
