package com.haoze.diting.normal

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.VpnService
import android.os.ParcelFileDescriptor
import android.util.Log
import com.haoze.diting.vpn.VpnPlanNative
import com.haoze.diting.vpn.applyTo
import java.net.Inet6Address

/// TUN parameters and routing. The plan (addresses, DNS, routes, MTU, IPv6 decision and the
/// excluded-package union) comes from `rust/diting-vpn-config-core`; this object keeps the
/// Android interface label, `VpnService.Builder` and the physical-IPv6 probe.
object VpnRouteConfig {
    private const val TAG = "VpnRouteConfig"

    fun establish(
        service: VpnService,
        excludedPackages: Set<String>,
        proxyPackage: String?,
        bypassLan: Boolean,
        ipv6Mode: String,
    ): Pair<ParcelFileDescriptor?, Boolean> {
        val plan = VpnPlanNative.routePlan(
            mode = "normal",
            ipv6Mode = ipv6Mode,
            ipv6Supported = ipv6SupportFor(service, ipv6Mode),
            bypassLan = bypassLan,
            excludedPackages = excludedPackages,
            selfPackage = service.packageName,
            proxyPackage = proxyPackage.orEmpty(),
        )
        Log.i(TAG, "establish: ipv6Mode=$ipv6Mode, enableIpv6=${plan.enableIpv6}, bypassLan=$bypassLan")

        val builder = service.Builder()
            .setSession(service.applicationInfo.loadLabel(service.packageManager).toString())
        plan.applyTo(builder, TAG)
        val fd = try {
            builder.establish()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to establish VPN interface", e)
            null
        }
        // `enableIpv6` is the resolved decision (explicit mode, or the AUTO probe), not the raw
        // mode: when the tunnel carries no IPv6 the DNS side must suppress AAAA too.
        return fd to plan.enableIpv6
    }

    /// The ConnectivityManager walk only runs for `auto`; explicit modes answer without it.
    fun ipv6SupportFor(service: VpnService, ipv6Mode: String): Boolean =
        VpnPlanNative.ipv6ProbeNeeded(ipv6Mode) && hasPhysicalIpv6Support(service)

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
}
