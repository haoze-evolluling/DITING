package com.haoze.dnssr.vpn

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.VpnService
import android.os.ParcelFileDescriptor
import android.system.OsConstants
import android.util.Log
import com.haoze.dnssr.R
import com.haoze.dnssr.ui.AppSettings
import com.haoze.dnssr.ui.DnsResolutionMode
import com.haoze.dnssr.ui.Ipv6Mode
import com.haoze.dnssr.ui.OutboundProxyConfig
import com.haoze.dnssr.vpn.cache.DnsCachePolicy
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import java.net.Inet6Address

/**
 * Owns TUN virtual network interface creation, the Go userspace tunnel
 * lifecycle, and the CA certificate readiness check.
 */
class DnsVpnTunnelManager {

    var vpnInterface: ParcelFileDescriptor? = null
        private set
    var goInspectionTunnel: GoInspectionTunnel? = null
        private set
    @Volatile
    var activeInspectionPackages: Set<String> = emptySet()
        private set

    @Volatile
    var isIpv6Active: Boolean = false
        private set

    /**
     * Checks whether the HTTPS MITM certificate is installed in the system
     * trusted credentials.
     */
    fun isHttpsInspectionCertificateInstalled(context: Context): Boolean {
        val installed = runBlocking(Dispatchers.IO) {
            runCatching { GoInspectionCaManager.isInstalled(context) }.getOrDefault(false)
        }
        AppSettings.setHttpsInspectionReady(context, installed)
        if (!installed) {
            AppSettings.setHttpInspectionEnabled(context, false)
        }
        return installed
    }

    /**
     * Probes whether the underlying physical network (excluding the VPN
     * itself) has a valid public IPv6 address and gateway route.
     */
    @Suppress("DEPRECATION")
    fun hasPhysicalIpv6Support(context: Context): Boolean {
        return runCatching {
            val cm = context.getSystemService(ConnectivityManager::class.java) ?: return false
            val activeNetwork = cm.activeNetwork
            val candidateNetworks = mutableListOf<Network>()

            fun isPhysicalNetwork(network: Network): Boolean {
                val caps = cm.getNetworkCapabilities(network) ?: return false
                if (caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) return false
                return caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) ||
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)
            }

            if (activeNetwork != null && isPhysicalNetwork(activeNetwork)) {
                candidateNetworks.add(activeNetwork)
            }

            cm.allNetworks.forEach { network ->
                if (network != activeNetwork && isPhysicalNetwork(network)) {
                    val caps = cm.getNetworkCapabilities(network)
                    if (caps != null && caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) {
                        candidateNetworks.add(network)
                    }
                }
            }

            if (candidateNetworks.isEmpty()) {
                cm.allNetworks.forEach { network ->
                    if (isPhysicalNetwork(network)) {
                        candidateNetworks.add(network)
                    }
                }
            }

            candidateNetworks.any { network ->
                val lp = cm.getLinkProperties(network) ?: return@any false
                val iface = lp.interfaceName.orEmpty().lowercase()
                if (iface.startsWith("tun") || iface.startsWith("vpn")) {
                    return@any false
                }

                val hasGlobalIpv6 = lp.linkAddresses.any { linkAddr ->
                    val addr = linkAddr.address
                    if (addr !is Inet6Address) return@any false
                    val firstByte = addr.address[0].toInt() and 0xff
                    // Strictly require a global unicast address 2000::/3
                    // (first byte 0x20..0x3f). This fully excludes ULA
                    // (fc00::/7, i.e. fd00::/8), link-local (fe80::/10),
                    // loopback (::1), multicast, and similar ranges.
                    (firstByte in 0x20..0x3f) &&
                        !addr.isAnyLocalAddress &&
                        !addr.isLinkLocalAddress &&
                        !addr.isLoopbackAddress &&
                        !addr.isMulticastAddress
                }
                if (!hasGlobalIpv6) return@any false

                val hasIpv6Route = lp.routes.any { route ->
                    val destAddr = route.destination?.address
                    (destAddr is Inet6Address && route.isDefaultRoute) ||
                        (destAddr is Inet6Address && route.hasGateway())
                }
                hasIpv6Route
            }
        }.getOrDefault(false)
    }

    /**
     * Builds and establishes the [VpnService] TUN interface.
     */
    fun establishVpnInterface(
        vpnService: VpnService,
        excludedPackages: Set<String>,
        proxyPackage: String?,
        bypassLan: Boolean = true,
        ipv6Mode: Ipv6Mode = Ipv6Mode.AUTO
    ): ParcelFileDescriptor? {
        val enableIpv6 = when (ipv6Mode) {
            Ipv6Mode.ENABLED -> true
            Ipv6Mode.DISABLED -> false
            Ipv6Mode.AUTO -> hasPhysicalIpv6Support(vpnService)
        }
        Log.i(TAG, "establishVpnInterface: ipv6Mode=$ipv6Mode, enableIpv6=$enableIpv6, bypassLan=$bypassLan")

        val builder = vpnService.Builder()
            .setSession(vpnService.getString(R.string.app_name))
            .addAddress(VPN_ADDRESS_V4, 30)
            .addDnsServer(DNS_SERVER_V4)
            .allowFamily(OsConstants.AF_INET)
            .setMtu(1500)
            .setBlocking(true)

        if (enableIpv6) {
            builder.addAddress(VPN_ADDRESS_V6, 64)
            builder.addDnsServer(DNS_SERVER_V6)
            builder.allowFamily(OsConstants.AF_INET6)
        }

        if (bypassLan) {
            IPV4_BYPASS_LAN_ROUTES.forEach { (address, prefixLength) ->
                try {
                    builder.addRoute(address, prefixLength)
                } catch (e: Exception) {
                    Log.w(TAG, "addRoute failed for $address/$prefixLength", e)
                }
            }
            if (enableIpv6) {
                try {
                    builder.addRoute("2000::", 3)
                } catch (e: Exception) {
                    Log.w(TAG, "addRoute failed for 2000::/3", e)
                }
                try {
                    builder.addRoute(DNS_SERVER_V6, 128)
                } catch (e: Exception) {
                    Log.w(TAG, "addRoute failed for $DNS_SERVER_V6/128", e)
                }
            }
        } else {
            builder.addRoute("0.0.0.0", 0)
            if (enableIpv6) {
                builder.addRoute("::", 0)
            }
        }

        val allExcluded = excludedPackages + vpnService.packageName + listOfNotNull(proxyPackage)
        allExcluded.forEach { excluded ->
            try {
                builder.addDisallowedApplication(excluded)
            } catch (e: Exception) {
                Log.w(TAG, "addDisallowedApplication failed for $excluded", e)
            }
        }

        val pfd = builder.establish()
        vpnInterface = pfd
        isIpv6Active = if (pfd != null) enableIpv6 else false
        return pfd
    }

    /**
     * Initializes and starts the Go tunnel data plane.
     */
    fun startTunnel(
        service: DnsVpnService,
        scope: CoroutineScope,
        providers: List<DnsProvider>,
        resolutionMode: DnsResolutionMode,
        blockResponseMode: BlockResponseMode,
        dynamicBlockResponseConfig: DynamicBlockResponseConfig,
        cachePolicy: DnsCachePolicy,
        bootstrapEnabled: Boolean,
        bootstrapIps: List<BootstrapIpEntry>,
        inspectionRequested: Boolean,
        inspectionPackages: Set<String>,
        blockedPackages: Set<String>,
        appAllowlistRules: Map<String, Set<String>>,
        outboundProxyConfig: OutboundProxyConfig,
        dbComponents: DnsVpnDatabaseComponents
    ): Boolean {
        val pfd = vpnInterface ?: return false
        activeInspectionPackages = inspectionPackages

        val tunnel = GoInspectionTunnel(
            context = service,
            vpnService = service,
            scope = scope,
            dnsConfig = HttpsDnsConfigSnapshot.create(
                providers = providers,
                mode = resolutionMode,
                blockResponseMode = blockResponseMode,
                dynamicBlockResponseConfig = dynamicBlockResponseConfig,
                cachePolicy = cachePolicy,
                bootstrapEnabled = bootstrapEnabled,
                bootstrapIps = bootstrapIps
            ),
            inspectionEnabled = inspectionRequested,
            selectedPackages = activeInspectionPackages,
            blockedPackages = blockedPackages,
            appAllowlistRules = appAllowlistRules,
            dnsPolicy = dbComponents.domainPolicy,
            allowListManager = dbComponents.allowListManager,
            cnameRewriteRuleManager = dbComponents.rewriteRuleManager,
            goUrlRuleManager = dbComponents.goUrlRuleManager,
            dnsLogger = dbComponents.dnsLogger,
            httpRequestLogger = dbComponents.httpRequestLogger,
            raceLogger = dbComponents.raceLogger,
            bootstrapLogger = dbComponents.bootstrapLogger,
            bootstrapHealthEngine = dbComponents.bootstrapHealthEngine,
            dnsCache = dbComponents.dnsCache,
            filterHttp3 = AppSettings.isHttp3InspectionEnabled(service),
            blockEncryptedDns = AppSettings.isEncryptedDnsBlockingEnabled(service),
            outboundProxyConfig = outboundProxyConfig
        )

        if (!tunnel.start(pfd.fd)) {
            Log.e(TAG, "Go tunnel failed to start")
            disconnectVpnInterface()
            return false
        }
        goInspectionTunnel = tunnel
        return true
    }

    /**
     * Stops the Go tunnel data plane.
     */
    fun stopInspectionDataPlane() {
        goInspectionTunnel?.stop()
        goInspectionTunnel = null
        activeInspectionPackages = emptySet()
    }

    /**
     * Releases the TUN and closes the virtual interface descriptor.
     */
    fun disconnectVpnInterface() {
        goInspectionTunnel?.releaseTun()
        try {
            vpnInterface?.close()
        } catch (_: Exception) {
        }
        vpnInterface = null
        isIpv6Active = false
    }

    companion object {
        private const val TAG = "DnsVpnTunnelManager"
        const val VPN_ADDRESS_V4 = "10.0.0.2"
        const val DNS_SERVER_V4 = "10.0.0.1"
        const val VPN_ADDRESS_V6 = "fd00:abcd::2"
        const val DNS_SERVER_V6 = "fd00:abcd::1"

        val IPV4_BYPASS_LAN_ROUTES = listOf(
            "1.0.0.0" to 8,
            "2.0.0.0" to 7,
            "4.0.0.0" to 6,
            "8.0.0.0" to 7,
            "11.0.0.0" to 8,
            "12.0.0.0" to 6,
            "16.0.0.0" to 4,
            "32.0.0.0" to 3,
            "64.0.0.0" to 3,
            "96.0.0.0" to 4,
            "112.0.0.0" to 6,
            "120.0.0.0" to 7,
            "124.0.0.0" to 7,
            "126.0.0.0" to 8,
            "128.0.0.0" to 3,
            "160.0.0.0" to 5,
            "168.0.0.0" to 8,
            "169.0.0.0" to 9,
            "169.128.0.0" to 10,
            "169.192.0.0" to 11,
            "169.224.0.0" to 12,
            "169.240.0.0" to 13,
            "169.248.0.0" to 14,
            "169.252.0.0" to 15,
            "169.255.0.0" to 16,
            "170.0.0.0" to 7,
            "172.0.0.0" to 12,
            "172.32.0.0" to 11,
            "172.64.0.0" to 10,
            "172.128.0.0" to 9,
            "173.0.0.0" to 8,
            "174.0.0.0" to 7,
            "176.0.0.0" to 4,
            "192.0.0.0" to 9,
            "192.128.0.0" to 11,
            "192.160.0.0" to 13,
            "192.169.0.0" to 16,
            "192.170.0.0" to 15,
            "192.172.0.0" to 14,
            "192.176.0.0" to 12,
            "192.192.0.0" to 10,
            "193.0.0.0" to 8,
            "194.0.0.0" to 7,
            "196.0.0.0" to 6,
            "200.0.0.0" to 5,
            "208.0.0.0" to 4
        )
    }
}
