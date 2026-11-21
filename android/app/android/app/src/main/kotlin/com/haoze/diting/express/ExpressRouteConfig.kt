package com.haoze.diting.express

import android.net.VpnService
import android.util.Log
import com.haoze.diting.normal.VpnEstablishResult
import com.haoze.diting.normal.VpnRouteConfig
import com.haoze.diting.vpn.VpnPlanNative
import com.haoze.diting.vpn.applyTo

object ExpressRouteConfig {
    private const val TAG = "ExpressRouteConfig"

    internal fun establish(
        service: VpnService,
        excludedPackages: Set<String>,
        proxyPackage: String?,
        ipv6Mode: String,
    ): VpnEstablishResult {
        val clat = VpnRouteConfig.clatDetected(service)
        val plan = VpnPlanNative.routePlan(
            mode = "express",
            ipv6Mode = ipv6Mode,
            ipv6Supported = VpnRouteConfig.ipv6SupportFor(service, ipv6Mode, clat),
            clat = clat,
            bypassLan = false,
            excludedPackages = excludedPackages,
            selfPackage = service.packageName,
            proxyPackage = proxyPackage.orEmpty(),
        )
        Log.i(TAG, "establish: ipv6Mode=$ipv6Mode, enableIpv6=${plan.enableIpv6}, clat=$clat")

        val builder = service.Builder()
            .setSession(service.applicationInfo.loadLabel(service.packageManager).toString())
        plan.applyTo(builder, TAG)
        val fd = try {
            builder.establish()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to establish express VPN interface", e)
            null
        }
        return VpnEstablishResult(fd, plan.enableIpv6, clat)
    }
}
