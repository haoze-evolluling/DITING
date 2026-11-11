package com.haoze.diting.express

import android.net.VpnService
import android.os.ParcelFileDescriptor
import android.util.Log
import com.haoze.diting.normal.VpnRouteConfig
import com.haoze.diting.vpn.VpnPlanNative
import com.haoze.diting.vpn.applyTo

/// Narrow-route TUN: only the DNS subnet and public resolvers enter it; other traffic keeps OS
/// routing. The address/DNS/route plan comes from `rust/diting-vpn-config-core`.
object ExpressRouteConfig {
    private const val TAG = "ExpressRouteConfig"

    fun establish(
        service: VpnService,
        excludedPackages: Set<String>,
        proxyPackage: String?,
        ipv6Mode: String,
    ): Pair<ParcelFileDescriptor?, Boolean> {
        val plan = VpnPlanNative.routePlan(
            mode = "express",
            ipv6Mode = ipv6Mode,
            ipv6Supported = VpnRouteConfig.ipv6SupportFor(service, ipv6Mode),
            bypassLan = false,
            excludedPackages = excludedPackages,
            selfPackage = service.packageName,
            proxyPackage = proxyPackage.orEmpty(),
        )
        Log.i(TAG, "establish: ipv6Mode=$ipv6Mode, enableIpv6=${plan.enableIpv6}")

        val builder = service.Builder()
            .setSession(service.applicationInfo.loadLabel(service.packageManager).toString())
        plan.applyTo(builder, TAG)
        val fd = try {
            builder.establish()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to establish express VPN interface", e)
            null
        }
        return fd to plan.enableIpv6
    }
}
