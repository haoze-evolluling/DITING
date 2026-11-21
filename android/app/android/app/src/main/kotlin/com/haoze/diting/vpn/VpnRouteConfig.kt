package com.haoze.diting.vpn

import android.content.Context
import android.net.ConnectivityManager
import android.net.VpnService
import android.os.ParcelFileDescriptor
import android.util.Log

internal data class VpnEstablishResult(
    val fd: ParcelFileDescriptor?,
    val ipv6Enabled: Boolean,
    val clatOnly: Boolean,
)

internal object VpnRouteConfig {
    fun establish(
        service: VpnService,
        excludedPackages: Set<String>,
        proxyPackage: String?,
        bypassLan: Boolean,
        ipv6Mode: String,
        routeMode: String = VpnModeProfile.ROUTE_MODE_FULL_TUNNEL,
        logTag: String = "VpnRouteConfig",
    ): VpnEstablishResult {
        val clat = clatDetected(service)
        val plan = VpnPlanNative.routePlan(
            mode = routeMode,
            ipv6Mode = ipv6Mode,
            ipv6Supported = ipv6SupportFor(service, ipv6Mode, clat),
            clat = clat,
            bypassLan = bypassLan,
            excludedPackages = excludedPackages,
            selfPackage = service.packageName,
            proxyPackage = proxyPackage.orEmpty(),
        )
        Log.i(
            logTag,
            "establish: mode=$routeMode, ipv6Mode=$ipv6Mode, enableIpv6=${plan.enableIpv6}, " +
                "clat=$clat, bypassLan=$bypassLan",
        )

        val builder = service.Builder()
            .setSession(service.applicationInfo.loadLabel(service.packageManager).toString())
        plan.applyTo(builder, logTag)
        val fd = try {
            builder.establish()
        } catch (e: Exception) {
            Log.e(logTag, "Failed to establish VPN interface", e)
            null
        }
        return VpnEstablishResult(fd, plan.enableIpv6, clat)
    }

    fun ipv6SupportFor(service: VpnService, ipv6Mode: String, clat: Boolean): Boolean =
        clat ||
            (VpnPlanNative.ipv6ProbeNeeded(ipv6Mode) && hasPhysicalIpv6Support(service))

    fun hasPhysicalIpv6Support(context: Context): Boolean = runCatching {
        val manager = context.getSystemService(ConnectivityManager::class.java) ?: return false
        NetworkTopology.physicalLinks(manager).any { link ->
            NetworkTopology.hasGlobalIpv6(link) && NetworkTopology.hasIpv6DefaultRoute(link)
        }
    }.getOrDefault(false)

    /** 物理网络是否只能在 CLAT 之上提供 IPv4。 */
    fun clatDetected(context: Context): Boolean = runCatching {
        val manager = context.getSystemService(ConnectivityManager::class.java) ?: return false
        NetworkTopology.physicalLinks(manager).any(NetworkTopology::clatOnly)
    }.getOrDefault(false)
}
