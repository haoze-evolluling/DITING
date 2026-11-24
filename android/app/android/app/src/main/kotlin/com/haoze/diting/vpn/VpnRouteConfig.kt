package com.haoze.diting.vpn

import android.content.Context
import android.net.ConnectivityManager
import android.net.VpnService
import android.os.ParcelFileDescriptor
import android.util.Log

internal data class VpnEstablishResult(
    val fd: ParcelFileDescriptor?,
    val clatOnly: Boolean,
)

internal object VpnRouteConfig {
    fun establish(
        service: VpnService,
        excludedPackages: Set<String>,
        proxyPackage: String?,
        bypassPrivate: Boolean,
        tunnelIpv6: Boolean,
        clat: Boolean,
        routeAddress: Collection<String>,
        routeExcludeAddress: Collection<String>,
        logTag: String = "VpnRouteConfig",
    ): VpnEstablishResult {
        val plan = VpnPlanNative.routePlan(
            tunnelIpv6 = tunnelIpv6,
            routeAddress = routeAddress,
            routeExcludeAddress = routeExcludeAddress,
            bypassPrivate = bypassPrivate,
            clat = clat,
            excludedPackages = excludedPackages,
            selfPackage = service.packageName,
            proxyPackage = proxyPackage.orEmpty(),
        )
        Log.i(
            logTag,
            "establish: tunnelIpv6=$tunnelIpv6, enableIpv6=${plan.enableIpv6}, " +
                "clat=$clat, bypassPrivate=$bypassPrivate",
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
        return VpnEstablishResult(fd, clat)
    }

    /** 物理网络是否只能在 CLAT 之上提供 IPv4。 */
    fun clatDetected(context: Context): Boolean = runCatching {
        val manager = context.getSystemService(ConnectivityManager::class.java) ?: return false
        NetworkTopology.physicalLinks(manager).any(NetworkTopology::clatOnly)
    }.getOrDefault(false)
}
