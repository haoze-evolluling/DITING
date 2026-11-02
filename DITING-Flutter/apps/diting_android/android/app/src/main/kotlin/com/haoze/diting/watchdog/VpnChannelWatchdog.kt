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
/// no VPN network follows within [CONFIRM_WINDOW_MS] is treated as the user's choice.
///
/// Never call `VpnService.prepare` while the slot is occupied: for a pre-consented app it
/// silently re-prepares this package and tears the other VPN down. [Listener.onReleased] only
/// fires after the slot stayed free for [RELEASE_DEBOUNCE_MS].
///
/// All callbacks run on the main thread.
class VpnChannelWatchdog(context: Context, private val listener: Listener) {
    interface Listener {
        /// Another VPN holds the slot.
        fun onOccupied()

        /// The slot has been free long enough; the owner may try to reclaim it.
        fun onReleased()

        /// No other VPN showed up after the revoke: the user turned the tunnel off.
        fun onUserDisconnect()
    }

    private enum class Phase { CONFIRMING, OCCUPIED, RELEASED }

    private val handler = Handler(Looper.getMainLooper())
    private val connectivity = context.applicationContext
        .getSystemService(ConnectivityManager::class.java)
    private var callback: ConnectivityManager.NetworkCallback? = null
    private var phase = Phase.CONFIRMING
    private var confirmDeadline = 0L
    private var freeSince = 0L
    private var active = false

    private val tick = object : Runnable {
        override fun run() {
            evaluate()
            if (active) handler.postDelayed(this, intervalMs())
        }
    }

    fun start() {
        if (active) return
        active = true
        phase = Phase.CONFIRMING
        freeSince = 0L
        confirmDeadline = SystemClock.elapsedRealtime() + CONFIRM_WINDOW_MS
        registerCallback()
        // Our own network is torn down asynchronously; reading it now would count as "occupied".
        handler.postDelayed(tick, GRACE_MS)
    }

    fun stop() {
        active = false
        handler.removeCallbacksAndMessages(null)
        callback?.let { cb -> runCatching { connectivity?.unregisterNetworkCallback(cb) } }
        callback = null
    }

    private fun intervalMs(): Long =
        if (phase == Phase.CONFIRMING) CONFIRM_POLL_MS else WATCH_POLL_MS

    private fun evaluate() {
        if (!active) return
        val now = SystemClock.elapsedRealtime()
        val occupied = otherVpnActive()
        when (phase) {
            Phase.CONFIRMING -> when {
                occupied -> enterOccupied()
                now >= confirmDeadline -> {
                    Log.i(TAG, "no VPN took the slot; treating the revoke as a user disconnect")
                    stop()
                    listener.onUserDisconnect()
                }
            }
            Phase.OCCUPIED -> {
                if (occupied) {
                    freeSince = 0L
                    return
                }
                if (freeSince == 0L) {
                    freeSince = now
                    // The poll interval is longer than the debounce; check again right on time.
                    handler.postDelayed({ evaluate() }, RELEASE_DEBOUNCE_MS)
                    return
                }
                if (now - freeSince >= RELEASE_DEBOUNCE_MS) {
                    Log.i(TAG, "VPN slot released")
                    phase = Phase.RELEASED
                    listener.onReleased()
                }
            }
            // Waiting for consent; another VPN coming up sends the owner back to "occupied".
            Phase.RELEASED -> if (occupied) enterOccupied()
        }
    }

    private fun enterOccupied() {
        phase = Phase.OCCUPIED
        freeSince = 0L
        listener.onOccupied()
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

        private const val GRACE_MS = 2_000L
        private const val CONFIRM_WINDOW_MS = 15_000L
        private const val CONFIRM_POLL_MS = 1_000L
        private const val WATCH_POLL_MS = 5_000L
        private const val RELEASE_DEBOUNCE_MS = 3_000L

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
