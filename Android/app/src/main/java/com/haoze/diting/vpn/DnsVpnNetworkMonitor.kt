package com.haoze.diting.vpn

import android.content.Context
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.util.Log
import kotlinx.coroutines.Job

/**
 * Monitors physical network interface changes (WiFi, Cellular, Ethernet) to
 * detect connectivity switches and handle IPv6 adaptation checks.
 */
class DnsVpnNetworkMonitor(
    private val context: Context,
    private val onNetworkChanged: ((reason: String) -> Unit)? = null
) {
    private var physicalNetworkCallback: ConnectivityManager.NetworkCallback? = null
    private var networkChangeDebounceJob: Job? = null

    fun start() {
        if (physicalNetworkCallback != null) return
        val cm = context.getSystemService(ConnectivityManager::class.java) ?: return
        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .addTransportType(NetworkCapabilities.TRANSPORT_CELLULAR)
            .addTransportType(NetworkCapabilities.TRANSPORT_ETHERNET)
            .build()

        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                scheduleIpv6AdaptationCheck("network_available")
            }

            override fun onLost(network: Network) {
                scheduleIpv6AdaptationCheck("network_lost")
            }

            override fun onLinkPropertiesChanged(network: Network, linkProperties: LinkProperties) {
                scheduleIpv6AdaptationCheck("link_properties_changed")
            }

            override fun onCapabilitiesChanged(network: Network, networkCapabilities: NetworkCapabilities) {
                scheduleIpv6AdaptationCheck("capabilities_changed")
            }
        }

        runCatching {
            cm.registerNetworkCallback(request, callback)
            physicalNetworkCallback = callback
            Log.d(TAG, "Registered physical network callback for dynamic IPv6 adaptation")
        }.onFailure {
            Log.w(TAG, "Failed to register physical network callback", it)
        }
    }

    fun stop() {
        networkChangeDebounceJob?.cancel()
        networkChangeDebounceJob = null
        val callback = physicalNetworkCallback ?: return
        physicalNetworkCallback = null
        val cm = context.getSystemService(ConnectivityManager::class.java) ?: return
        runCatching { cm.unregisterNetworkCallback(callback) }
            .onFailure { Log.w(TAG, "Failed to unregister physical network callback", it) }
    }

    private fun scheduleIpv6AdaptationCheck(reason: String) {
        // In AUTO mode, IPv6 is always stably configured on the virtual interface to prevent IPv6 DNS leaks.
        // Physical network changes do not require disruptive VPN interface reconnections.
        onNetworkChanged?.invoke(reason)
    }

    companion object {
        private const val TAG = "DnsVpnNetworkMonitor"
    }
}
