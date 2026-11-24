package com.haoze.diting.vpn

import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Build
import java.net.Inet4Address
import java.net.Inet6Address

internal object NetworkTopology {
    /** Android 464XLAT 使用的固定 CLAT 地址（192.0.0.4/29）。 */
    const val CLAT_ADDRESS = "192.0.0.4"

    fun physicalLinks(manager: ConnectivityManager): List<LinkProperties> {
        val networks = mutableListOf<Network>()
        manager.activeNetwork?.let(networks::add)
        networks.addAll(manager.allNetworks)
        val seen = mutableSetOf<Network>()
        return networks.mapNotNull { network ->
            if (!seen.add(network)) return@mapNotNull null
            val caps = manager.getNetworkCapabilities(network) ?: return@mapNotNull null
            if (caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) return@mapNotNull null
            if (!isPhysical(caps)) return@mapNotNull null
            manager.getLinkProperties(network)
        }
    }

    fun isPhysical(caps: NetworkCapabilities): Boolean =
        caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) ||
            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)

    fun hasGlobalIpv6(link: LinkProperties): Boolean =
        link.linkAddresses.any { linkAddress ->
            val address = linkAddress.address
            address is Inet6Address &&
                !address.isAnyLocalAddress &&
                !address.isLoopbackAddress &&
                !address.isLinkLocalAddress &&
                !address.isMulticastAddress
        }

    /** 有全局 IPv6 地址，且有默认或非链路本地的 IPv6 路由。 */
    fun hasRoutableIpv6(link: LinkProperties): Boolean =
        hasGlobalIpv6(link) && link.routes.any { route ->
            val address = route.destination.address
            address is Inet6Address &&
                (route.isDefaultRoute || !address.isLinkLocalAddress)
        }

    /**
     * 物理网络是否只在 CLAT 之上提供 IPv4：有全局 IPv6、没有原生 IPv4，
     * 且存在 NAT64 前缀或 192.0.0.4/29 / v4- 虚拟接口。
     */
    fun clatOnly(link: LinkProperties): Boolean {
        if (!hasGlobalIpv6(link)) return false
        val nativeIpv4 = link.linkAddresses.any { linkAddress ->
            val address = linkAddress.address
            address is Inet4Address &&
                !address.isAnyLocalAddress &&
                !address.isLoopbackAddress &&
                !address.isLinkLocalAddress &&
                address.hostAddress != CLAT_ADDRESS
        }
        if (nativeIpv4) return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && link.nat64Prefix != null) {
            return true
        }
        val clatAddress = link.linkAddresses.any { linkAddress ->
            linkAddress.address.hostAddress == CLAT_ADDRESS && linkAddress.prefixLength == 29
        }
        val clatRoute = link.routes.any { route ->
            route.`interface`?.startsWith("v4-") == true
        }
        return clatAddress || clatRoute
    }
}
