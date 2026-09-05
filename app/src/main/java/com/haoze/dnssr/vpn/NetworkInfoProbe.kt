package com.haoze.dnssr.vpn

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import java.net.Inet4Address
import java.net.Inet6Address

/**
 * 当前网络信息快照，供网络调试工具展示与 DNS 查询选取系统 DNS 服务器。
 *
 * 物理网络判定与 DnsVpnTunnelManager.hasPhysicalIpv6Support 保持一致：
 * 忽略 VPN transport 与 tun 接口，优先使用默认活动网络，必要时回退枚举所有物理网络。
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
