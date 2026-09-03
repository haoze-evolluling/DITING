package com.haoze.dnssr.vpn

import android.content.Context
import android.net.VpnService
import android.os.ParcelFileDescriptor
import android.system.OsConstants
import android.util.Log
import com.haoze.dnssr.R
import com.haoze.dnssr.ui.AppSettings
import com.haoze.dnssr.ui.DnsResolutionMode
import com.haoze.dnssr.ui.OutboundProxyConfig
import com.haoze.dnssr.vpn.cache.DnsCachePolicy
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking

/**
 * 负责 TUN 虚拟网卡创建、Go 用户态隧道生命周期管理及 CA 证书就绪状态检查。
 */
class DnsVpnTunnelManager {

    var vpnInterface: ParcelFileDescriptor? = null
        private set
    var goInspectionTunnel: GoInspectionTunnel? = null
        private set
    @Volatile
    var activeInspectionPackages: Set<String> = emptySet()
        private set

    /**
     * 检查 HTTPS MITM 证书是否已在系统受信任凭据中安装。
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
     * 构建并建立 [VpnService] TUN 虚拟网卡接口。
     */
    fun establishVpnInterface(
        vpnService: VpnService,
        excludedPackages: Set<String>,
        proxyPackage: String?,
        bypassLan: Boolean = true
    ): ParcelFileDescriptor? {
        val builder = vpnService.Builder()
            .setSession(vpnService.getString(R.string.app_name))
            .addAddress(VPN_ADDRESS_V4, 30)
            .addAddress(VPN_ADDRESS_V6, 128)
            .addDnsServer(DNS_SERVER_V4)
            .addDnsServer(DNS_SERVER_V6)
            .allowFamily(OsConstants.AF_INET)
            .allowFamily(OsConstants.AF_INET6)
            .setMtu(1500)
            .setBlocking(true)

        if (bypassLan) {
            IPV4_BYPASS_LAN_ROUTES.forEach { (address, prefixLength) ->
                try {
                    builder.addRoute(address, prefixLength)
                } catch (e: Exception) {
                    Log.w(TAG, "addRoute failed for $address/$prefixLength", e)
                }
            }
            try {
                builder.addRoute("2000::", 3)
            } catch (e: Exception) {
                Log.w(TAG, "addRoute failed for 2000::/3", e)
            }
        } else {
            builder.addRoute("0.0.0.0", 0)
            builder.addRoute("::", 0)
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
        return pfd
    }

    /**
     * 初始化并启动 Go 隧道数据面。
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
     * 停止 Go 隧道数据面。
     */
    fun stopInspectionDataPlane() {
        goInspectionTunnel?.stop()
        goInspectionTunnel = null
        activeInspectionPackages = emptySet()
    }

    /**
     * 释放 TUN 并关闭虚拟网卡描述符。
     */
    fun disconnectVpnInterface() {
        goInspectionTunnel?.releaseTun()
        try {
            vpnInterface?.close()
        } catch (_: Exception) {
        }
        vpnInterface = null
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
