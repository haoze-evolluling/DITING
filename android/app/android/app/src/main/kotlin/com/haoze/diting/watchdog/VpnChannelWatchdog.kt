package com.haoze.diting.watchdog

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log

/// Watches the system VPN slot after `onRevoke`, so a tunnel displaced by another app can come
/// back once that app lets go of it.
///
/// `onRevoke` fires both when another app takes the slot and when the user disconnects us from
/// the system settings. Only the first one is followed by a foreign VPN network, so a revoke that
/// no VPN network follows within the confirmation window is treated as the user's choice.
///
/// Never call `VpnService.prepare` while the slot is occupied: for a pre-consented app it
/// silently re-prepares this package and tears the other VPN down. [Listener.onReleased] only
/// fires after the slot stayed free for the debounce window.
///
/// The phases, deadlines, debounce and next-poll delays live in
/// `rust/diting-vpn-config-core/src/watchdog.rs`; this class keeps the Handler, the
/// ConnectivityManager callback and the listener calls. All callbacks run on the main thread.
class VpnChannelWatchdog(context: Context, private val listener: Listener) {
    interface Listener {
        /// Another VPN holds the slot.
        fun onOccupied()

        /// The slot has been free long enough; the owner may try to reclaim it.
        fun onReleased()

        /// No other VPN showed up after the revoke: the user turned the tunnel off.
        fun onUserDisconnect()
    }

    private val handler = Handler(Looper.getMainLooper())
    private val connectivity = context.applicationContext
        .getSystemService(ConnectivityManager::class.java)
    private var callback: ConnectivityManager.NetworkCallback? = null
    private var handle = 0L
    private var active = false

    private val tick = object : Runnable {
        override fun run() {
            val delay = evaluate()
            if (active && delay > 0) handler.postDelayed(this, delay)
        }
    }

    fun start() {
        if (active) return
        val newHandle = VpnWatchdogNative.newHandle()
        handle = newHandle
        active = true
        val grace = VpnWatchdogNative.start(newHandle, SystemClock.elapsedRealtime())
        registerCallback()
        // Our own network is torn down asynchronously; reading it now would count as "occupied".
        handler.postDelayed(tick, grace)
    }

    fun stop() {
        active = false
        handler.removeCallbacksAndMessages(null)
        callback?.let { cb -> runCatching { connectivity?.unregisterNetworkCallback(cb) } }
        callback = null
        if (handle != 0L) {
            VpnWatchdogNative.stop(handle)
            VpnWatchdogNative.free(handle)
            handle = 0L
        }
    }

    /// One native poll; returns the next delay. A user disconnect stops the watchdog first.
    private fun evaluate(): Long {
        if (!active) return 0
        val step = VpnWatchdogNative.evaluate(
            handle = handle,
            nowMs = SystemClock.elapsedRealtime(),
            occupied = otherVpnActive(),
        )
        when (step.event) {
            VpnWatchdogEvent.NONE -> {}
            VpnWatchdogEvent.OCCUPIED -> listener.onOccupied()
            VpnWatchdogEvent.RELEASED -> listener.onReleased()
            VpnWatchdogEvent.USER_DISCONNECT -> {
                Log.i(TAG, "no VPN took the slot; treating the revoke as a user disconnect")
                stop()
                listener.onUserDisconnect()
                return 0
            }
        }
        return if (active) step.nextDelayMs else 0
    }

    /// Polling covers VPNs whose callbacks this UID is not sent; the callback only makes it faster.
    private fun registerCallback() {
        val manager = connectivity ?: return
        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_VPN)
            .removeCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
            .build()
        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                handler.post { evaluate() }
            }

            override fun onLost(network: Network) {
                handler.post { evaluate() }
            }
        }
        runCatching { manager.registerNetworkCallback(request, cb) }
            .onSuccess { callback = cb }
            .onFailure { Log.w(TAG, "registerNetworkCallback failed; polling only", it) }
    }

    @Suppress("DEPRECATION")
    private fun otherVpnActive(): Boolean {
        val manager = connectivity ?: return false
        return runCatching {
            manager.allNetworks.any { network ->
                manager.getNetworkCapabilities(network)
                    ?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true
            }
        }.getOrDefault(false)
    }

    companion object {
        private const val TAG = "VpnChannelWatchdog"

        private const val UI_PREFS = "dns_vpn_prefs"
        private const val KEY_ENABLED = "vpn_watchdog_enabled"
        private const val WORK_MODE_PREFS = "diting_settings"
        private const val KEY_WORK_MODE = "app_work_mode"

        /// Settings page switch, written by Flutter; on unless the user turned it off.
        fun enabled(context: Context): Boolean =
            context.getSharedPreferences(UI_PREFS, Context.MODE_PRIVATE)
                .getBoolean(KEY_ENABLED, true)

        /// Legacy `app_work_mode`: `normal` / `express` / `dns`; missing means normal.
        fun workMode(context: Context): String =
            context.getSharedPreferences(WORK_MODE_PREFS, Context.MODE_PRIVATE)
                .getString(KEY_WORK_MODE, null) ?: "normal"
    }
}
