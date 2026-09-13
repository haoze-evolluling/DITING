package com.haoze.dnssr.vpn

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import java.net.Inet4Address
import java.net.Inet6Address

/**
 * Snapshot of the current network, used for network diagnostics display and
 * for picking system DNS servers for DNS queries.
 *
 * Physical-network detection stays consistent with
 * DnsVpnTunnelManager.hasPhysicalIpv6Support: VPN transports and tun
 * interfaces are ignored, the default active network is preferred, and the
 * probe falls back to enumerating all physical networks when necessary.
 */
data class NetworkSnapshot(
    val networkType: String,
    val interfaceName: String?,
    val gateway: String?,
    val ipv4Addresses: List<String>,
    val ipv6Addresses: List<String>,
    val dnsServers: List<String>,
    val isVpnActive: Boolean
)

object NetworkInfoProbe {

    fun probe(context: Context): NetworkSnapshot? {
        val cm = context.getSystemService(ConnectivityManager::class.java) ?: return null
        return runCatching { probe(cm) }.getOrNull()
    }

    // allNetworks is deprecated since API 31 with no synchronous replacement; this is a
    // one-shot snapshot probe, consistent with how DnsVpnTunnelManager handles it.
    @Suppress("DEPRECATION")
    private fun probe(cm: ConnectivityManager): NetworkSnapshot? {
        val isVpnActive = cm.allNetworks.any { network ->
            cm.getNetworkCapabilities(network)?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true
        }

        val activeNetwork = cm.activeNetwork
        val candidate = if (activeNetwork != null && isPhysicalNetwork(cm, activeNetwork)) {
            activeNetwork
        } else {
            cm.allNetworks
                .filter { it != activeNetwork && isPhysicalNetwork(cm, it) }
                .firstOrNull {
                    cm.getNetworkCapabilities(it)?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true
                }
                ?: cm.allNetworks.firstOrNull { isPhysicalNetwork(cm, it) }
        }

        val linkProperties = candidate?.let { cm.getLinkProperties(it) } ?: return null
        val capabilities = candidate.let { cm.getNetworkCapabilities(it) }

        val ipv4 = mutableListOf<String>()
        val ipv6 = mutableListOf<String>()
        linkProperties.linkAddresses.forEach { linkAddress ->
            val address = linkAddress.address
            val host = address.hostAddress ?: return@forEach
            if (address.isLoopbackAddress) return@forEach
            when (address) {
                is Inet4Address -> ipv4.add(host)
                is Inet6Address -> if (!address.isLinkLocalAddress) ipv6.add(host)
            }
        }

        return NetworkSnapshot(
            networkType = networkTypeLabel(capabilities),
            interfaceName = linkProperties.interfaceName,
            gateway = linkProperties.routes.firstOrNull { it.gateway != null }?.gateway?.hostAddress,
            ipv4Addresses = ipv4,
            ipv6Addresses = ipv6,
            dnsServers = linkProperties.dnsServers.mapNotNull { it.hostAddress },
            isVpnActive = isVpnActive
        )
    }

    private fun isPhysicalNetwork(cm: ConnectivityManager, network: Network): Boolean {
        val caps = cm.getNetworkCapabilities(network) ?: return false
        if (caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) return false
        return caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) ||
            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)
    }

    private fun networkTypeLabel(caps: NetworkCapabilities?): String = when {
        caps == null -> "未知网络"
        caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "WLAN"
        caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "蜂窝网络"
        caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "以太网"
        else -> "其他网络"
    }
}
