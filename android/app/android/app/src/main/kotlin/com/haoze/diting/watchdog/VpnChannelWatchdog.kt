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

class VpnChannelWatchdog(context: Context, private val listener: Listener) {
    interface Listener {
        fun onOccupied()

        fun onReleased()

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

        fun enabled(context: Context): Boolean =
            context.getSharedPreferences(UI_PREFS, Context.MODE_PRIVATE)
                .getBoolean(KEY_ENABLED, true)

        fun workMode(context: Context): String =
            context.getSharedPreferences(WORK_MODE_PREFS, Context.MODE_PRIVATE)
                .getString(KEY_WORK_MODE, null) ?: "normal"
    }
}
