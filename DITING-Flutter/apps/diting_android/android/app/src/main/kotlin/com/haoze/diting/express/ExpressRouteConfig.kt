package com.haoze.diting.express

import android.content.Context
import android.net.VpnService
import android.os.ParcelFileDescriptor
import android.util.Log
import com.haoze.diting.normal.VpnRouteConfig

/// Narrow-route TUN: only DNS subnet and public resolvers enter it; other traffic keeps OS routing.
object ExpressRouteConfig {
    private const val TAG = "ExpressRouteConfig"

    private const val VPN_ADDRESS_V4 = "10.0.0.2"
    private const val DNS_SERVER_V4 = "10.0.0.1"
    private const val VPN_ADDRESS_V6 = "fd00:abcd::2"
    private const val DNS_SERVER_V6 = "fd00:abcd::1"
    private const val VPN_MTU = 1400

    val IPV4_HIJACK_IPS = listOf(
        "8.8.8.8",
        "8.8.4.4",
        "1.1.1.1",
        "1.0.0.1",
        "9.9.9.9",
        "149.112.112.112",
        "208.67.222.222",
        "208.67.220.220",
        "223.5.5.5",
        "223.6.6.6",
        "119.29.29.29",
        "114.114.114.114",
        "114.114.115.115",
        "180.76.76.76",
        "77.88.8.8",
        "77.88.8.1",
        "94.140.14.14",
        "94.140.14.15",
        "185.228.168.9",
        "185.228.169.9",
        "64.6.64.6",
        "64.6.65.6",
    )

    val IPV6_HIJACK_IPS = listOf(
        "2001:4860:4860::8888",
        "2001:4860:4860::8844",
        "2606:4700:4700::1111",
        "2606:4700:4700::1001",
        "2620:fe::fe",
        "2620:fe::9",
        "2400:3200::1",
        "2400:3200:baba::1",
    )

    fun establish(
        service: VpnService,
        excludedPackages: Set<String>,
        proxyPackage: String?,
        ipv6Mode: String,
    ): ParcelFileDescriptor? {
        val enableIpv6 = when (ipv6Mode.lowercase()) {
            "enabled" -> true
            "disabled" -> false
            else -> VpnRouteConfig.hasPhysicalIpv6Support(service)
        }
        Log.i(TAG, "establish: ipv6Mode=$ipv6Mode, enableIpv6=$enableIpv6")

        val builder = service.Builder()
            .setSession(service.applicationInfo.loadLabel(service.packageManager).toString())
            .addAddress(VPN_ADDRESS_V4, 30)
            .addDnsServer(DNS_SERVER_V4)
            .allowFamily(android.system.OsConstants.AF_INET)
            .setMtu(VPN_MTU)
            .setBlocking(true)
            .addRoute("10.0.0.0", 30)

        IPV4_HIJACK_IPS.forEach { address ->
            try {
                builder.addRoute(address, 32)
            } catch (e: Exception) {
                Log.w(TAG, "addRoute failed for $address/32", e)
            }
        }

        if (enableIpv6) {
            builder.addAddress(VPN_ADDRESS_V6, 64)
            builder.addDnsServer(DNS_SERVER_V6)
            builder.allowFamily(android.system.OsConstants.AF_INET6)
            try {
                builder.addRoute(DNS_SERVER_V6, 128)
            } catch (e: Exception) {
                Log.w(TAG, "addRoute failed for $DNS_SERVER_V6/128", e)
            }
            IPV6_HIJACK_IPS.forEach { address ->
                try {
                    builder.addRoute(address, 128)
                } catch (e: Exception) {
                    Log.w(TAG, "addRoute failed for $address/128", e)
                }
            }
        }

        // The proxy app must stay outside the tunnel: its own DNS/resolver sockets would
        // otherwise be hijacked by this TUN and sent back through the proxy.
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
            Log.e(TAG, "Failed to establish express VPN interface", e)
            null
        }
    }
}
