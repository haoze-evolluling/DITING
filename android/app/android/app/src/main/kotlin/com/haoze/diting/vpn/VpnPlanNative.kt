package com.haoze.diting.vpn

import android.net.VpnService
import android.system.OsConstants
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject

internal data class VpnAddress(val address: String, val prefix: Int)

internal data class VpnRoute(val address: String, val prefix: Int)

internal data class VpnPlan(
    val enableIpv6: Boolean,
    val mtu: Int,
    val blocking: Boolean,
    val addresses: List<VpnAddress>,
    val dnsServers: List<String>,
    val routes: List<VpnRoute>,
    val excludedPackages: List<String>,
)

internal data class VpnStartDefaults(
    val outboundProxy: String,
    val proxyAppPackage: String,
    val bypassLan: Boolean,
    val ipv6Mode: String,
    val excludedPackages: List<String>,
    val blockedPackages: List<String>,
    val inspectionPackages: List<String>,
    val inspectionEnabled: Boolean,
)

/// Native VPN plan kernel (`rust/diting-vpn-config-core`).
///
/// Kotlin still builds the interface and runs the ConnectivityManager probe; every TUN address,
/// DNS server, route, MTU, IPv6 decision and excluded-package union comes from here. The library is
/// required: a build that forgot `python rust/build_android.py` throws before `establish()`.
internal class VpnPlanNative private constructor() {
    external fun routePlan(
        mode: String,
        ipv6Mode: String,
        ipv6Supported: Boolean,
        bypassLan: Boolean,
        excluded: String,
        selfPackage: String,
        proxyPackage: String,
    ): String?

    external fun ipv6ProbeNeeded(ipv6Mode: String): Boolean

    external fun startDefaults(): String?

    companion object {
        private val instance: VpnPlanNative by lazy {
            try {
                System.loadLibrary("diting_kernels")
                VpnPlanNative()
            } catch (error: Throwable) {
                throw IllegalStateException(
                    "native VPN plan kernel unavailable; build it with " +
                        "`python rust/build_android.py`",
                    error,
                )
            }
        }

        fun routePlan(
            mode: String,
            ipv6Mode: String,
            ipv6Supported: Boolean,
            bypassLan: Boolean,
            excludedPackages: Collection<String>,
            selfPackage: String,
            proxyPackage: String,
        ): VpnPlan {
            val raw = requireNotNull(
                instance.routePlan(
                    mode = mode,
                    ipv6Mode = ipv6Mode,
                    ipv6Supported = ipv6Supported,
                    bypassLan = bypassLan,
                    excluded = excludedPackages.joinToString("\n"),
                    selfPackage = selfPackage,
                    proxyPackage = proxyPackage,
                ),
            ) { "native VPN route plan rejected the request" }
            return parsePlan(raw)
        }

        /// False for explicit `enabled` / `disabled`, so no ConnectivityManager walk is needed.
        fun ipv6ProbeNeeded(ipv6Mode: String): Boolean = instance.ipv6ProbeNeeded(ipv6Mode)

        /// Defaults the quick-settings tile replays before the user has ever started a tunnel.
        val startDefaults: VpnStartDefaults by lazy {
            val raw = requireNotNull(instance.startDefaults()) {
                "native VPN start defaults returned no value"
            }
            parseStartDefaults(raw)
        }

        private fun parsePlan(raw: String): VpnPlan {
            val json = JSONObject(raw)
            return VpnPlan(
                enableIpv6 = json.getBoolean("enableIpv6"),
                mtu = json.getInt("mtu"),
                blocking = json.getBoolean("blocking"),
                addresses = json.getJSONArray("addresses").objects { item ->
                    VpnAddress(item.getString("address"), item.getInt("prefix"))
                },
                dnsServers = json.getJSONArray("dnsServers").strings(),
                routes = json.getJSONArray("routes").objects { item ->
                    VpnRoute(item.getString("address"), item.getInt("prefix"))
                },
                excludedPackages = json.getJSONArray("excludedPackages").strings(),
            )
        }

        private fun parseStartDefaults(raw: String): VpnStartDefaults {
            val json = JSONObject(raw)
            return VpnStartDefaults(
                outboundProxy = json.getString("outboundProxy"),
                proxyAppPackage = json.optString("proxyAppPackage", ""),
                bypassLan = json.optBoolean("bypassLan", true),
                ipv6Mode = json.optString("ipv6Mode", "auto"),
                excludedPackages = json.optJSONArray("excludedPackages").strings(),
                blockedPackages = json.optJSONArray("blockedPackages").strings(),
                inspectionPackages = json.optJSONArray("inspectionPackages").strings(),
                inspectionEnabled = json.optBoolean("inspectionEnabled", false),
            )
        }
    }
}

/// Applies one native plan to a `VpnService.Builder`; per-route failures keep the legacy logs and
/// let the rest of the tunnel come up.
internal fun VpnPlan.applyTo(builder: VpnService.Builder, tag: String) {
    addresses.forEach { builder.addAddress(it.address, it.prefix) }
    dnsServers.forEach(builder::addDnsServer)
    builder.allowFamily(OsConstants.AF_INET)
    if (enableIpv6) builder.allowFamily(OsConstants.AF_INET6)
    builder.setMtu(mtu)
    builder.setBlocking(blocking)
    routes.forEach { route ->
        try {
            builder.addRoute(route.address, route.prefix)
        } catch (e: Exception) {
            Log.w(tag, "addRoute failed for ${route.address}/${route.prefix}", e)
        }
    }
    excludedPackages.forEach { packageName ->
        try {
            builder.addDisallowedApplication(packageName)
        } catch (e: Exception) {
            Log.w(tag, "addDisallowedApplication failed for $packageName", e)
        }
    }
}

private fun JSONArray?.strings(): List<String> =
    if (this == null) emptyList() else List(length()) { getString(it) }

private fun <T> JSONArray.objects(transform: (JSONObject) -> T): List<T> =
    List(length()) { transform(getJSONObject(it)) }
