package com.haoze.diting.normal

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.VpnService
import android.os.ParcelFileDescriptor
import android.util.Log
import java.net.Inet6Address

/// TUN parameters and routing. MTU must stay in sync with the Go engine's `defaultTunMTU`
object VpnRouteConfig {
    private const val TAG = "VpnRouteConfig"

    const val VPN_ADDRESS_V4 = "10.0.0.2"
    const val DNS_SERVER_V4 = "10.0.0.1"
    const val VPN_ADDRESS_V6 = "fd00:abcd::2"
    const val DNS_SERVER_V6 = "fd00:abcd::1"
    const val VPN_MTU = 1400

    fun establish(
        service: VpnService,
        excludedPackages: Set<String>,
        proxyPackage: String?,
        bypassLan: Boolean,
        ipv6Mode: String,
    ): ParcelFileDescriptor? {
        val enableIpv6 = when (ipv6Mode.lowercase()) {
            "enabled" -> true
            "disabled" -> false
            else -> hasPhysicalIpv6Support(service)
        }
        Log.i(TAG, "establish: ipv6Mode=$ipv6Mode, enableIpv6=$enableIpv6, bypassLan=$bypassLan")

        val builder = service.Builder()
            .setSession(service.applicationInfo.loadLabel(service.packageManager).toString())
            .addAddress(VPN_ADDRESS_V4, 30)
            .addDnsServer(DNS_SERVER_V4)
            .allowFamily(android.system.OsConstants.AF_INET)
            .setMtu(VPN_MTU)
            .setBlocking(true)

        if (enableIpv6) {
            builder.addAddress(VPN_ADDRESS_V6, 64)
            builder.addDnsServer(DNS_SERVER_V6)
            builder.allowFamily(android.system.OsConstants.AF_INET6)
        }

        if (bypassLan) {
            IPV4_BYPASS_LAN_ROUTES.forEach { (address, prefixLength) ->
                try {
                    builder.addRoute(address, prefixLength)
                } catch (e: Exception) {
                    Log.w(TAG, "addRoute failed for $address/$prefixLength", e)
                }
            }
            try {
                builder.addRoute(DNS_SERVER_V4, 32)
            } catch (e: Exception) {
                Log.w(TAG, "addRoute failed for $DNS_SERVER_V4/32", e)
            }
            if (enableIpv6) {
                try {
                    builder.addRoute("2000::", 3)
                } catch (e: Exception) {
                    Log.w(TAG, "addRoute failed for 2000::/3", e)
                }
                try {
                    builder.addRoute(DNS_SERVER_V6, 128)
                } catch (e: Exception) {
                    Log.w(TAG, "addRoute failed for $DNS_SERVER_V6/128", e)
                }
            }
        } else {
            builder.addRoute("0.0.0.0", 0)
            if (enableIpv6) {
                builder.addRoute("::", 0)
            }
        }

        // The proxy app must stay outside the tunnel: its upstream sockets would otherwise be
        // captured by this TUN, re-dialed through the proxy and loop until the handshake dies.
        val allExcluded = (excludedPackages + service.packageName + listOfNotNull(proxyPackage))
            .filter { it.isNotBlank() }
            .toSet()
        allExcluded.forEach { excluded ->
            try {
                builder.addDisallowedApplication(excluded)
            } catch (e: Exception) {
                Log.w(TAG, "addDisallowedApplication failed for $excluded", e)
            }
        }

        return try {
            builder.establish()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to establish VPN interface", e)
            null
        }
    }

    @Suppress("DEPRECATION")
    fun hasPhysicalIpv6Support(context: Context): Boolean {
        return runCatching {
            val cm = context.getSystemService(ConnectivityManager::class.java) ?: return false
            val activeNetwork = cm.activeNetwork
            val candidates = mutableListOf<Network>()

            fun isPhysical(network: Network): Boolean {
                val caps = cm.getNetworkCapabilities(network) ?: return false
                if (caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) return false
                return caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) ||
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)
            }

            if (activeNetwork != null && isPhysical(activeNetwork)) {
                candidates.add(activeNetwork)
            }
            cm.allNetworks.forEach { network ->
                if (network != activeNetwork && isPhysical(network)) {
                    val caps = cm.getNetworkCapabilities(network)
                    if (caps != null && caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) {
                        candidates.add(network)
                    }
                }
            }
            if (candidates.isEmpty()) {
                cm.allNetworks.forEach { network -> if (isPhysical(network)) candidates.add(network) }
            }

            candidates.any { network ->
                val lp = cm.getLinkProperties(network) ?: return@any false
                val iface = lp.interfaceName.orEmpty().lowercase()
                if (iface.startsWith("tun") || iface.startsWith("vpn")) return@any false

                val hasGlobalIpv6 = lp.linkAddresses.any { linkAddr ->
                    val addr = linkAddr.address
                    if (addr !is Inet6Address) return@any false
                    val firstByte = addr.address[0].toInt() and 0xff
                    firstByte in 0x20..0x3f &&
                        !addr.isAnyLocalAddress &&
                        !addr.isLinkLocalAddress &&
                        !addr.isLoopbackAddress &&
                        !addr.isMulticastAddress
                }
                if (!hasGlobalIpv6) return@any false

                val hasIpv6Route = lp.routes.any { route ->
                    val destAddr = route.destination.address
                    (destAddr is Inet6Address && route.isDefaultRoute) ||
                        (destAddr is Inet6Address && route.hasGateway()) ||
                        (destAddr is Inet6Address && route.destination.prefixLength == 0)
                }
                hasGlobalIpv6 && hasIpv6Route
            }
        }.getOrDefault(false)
    }

    val IPV4_BYPASS_LAN_ROUTES = listOf(
        "1.0.0.0" to 8,
        "2.0.0.0" to 7,
        "4.0.0.0" to 6,
        "8.0.0.0" to 7,
        "11.0.0.0" to 8,
        "12.0.0.0" to 6,
        "16.0.0.0" to 4,
        "32.0.0.0" to 3,
        "64.0.0.0" to 3,
        "96.0.0.0" to 4,
        "112.0.0.0" to 7,
        "114.0.0.0" to 8,
        "115.0.0.0" to 8,
        "116.0.0.0" to 6,
        "120.0.0.0" to 7,
        "122.0.0.0" to 7,
        "124.0.0.0" to 7,
        "126.0.0.0" to 8,
        "128.0.0.0" to 3,
        "160.0.0.0" to 5,
        "168.0.0.0" to 8,
        "169.0.0.0" to 9,
        "169.128.0.0" to 10,
        "169.192.0.0" to 11,
        "169.224.0.0" to 12,
        "169.240.0.0" to 13,
        "169.248.0.0" to 14,
        "169.252.0.0" to 15,
        "169.255.0.0" to 16,
        "170.0.0.0" to 7,
        "172.0.0.0" to 12,
        "172.32.0.0" to 11,
        "172.64.0.0" to 10,
        "172.128.0.0" to 9,
        "173.0.0.0" to 8,
        "174.0.0.0" to 7,
        "176.0.0.0" to 4,
        "192.0.0.0" to 9,
        "192.128.0.0" to 11,
        "192.160.0.0" to 13,
        "192.169.0.0" to 16,
        "192.170.0.0" to 15,
        "192.172.0.0" to 14,
        "192.176.0.0" to 12,
        "192.192.0.0" to 10,
        "193.0.0.0" to 8,
        "194.0.0.0" to 7,
        "196.0.0.0" to 6,
        "200.0.0.0" to 5,
        "208.0.0.0" to 4,
    )
}
