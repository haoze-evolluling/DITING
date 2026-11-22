package com.haoze.diting.normal

import android.content.Context
import android.content.Intent
import com.haoze.diting.engine.Engine
import com.haoze.diting.vpn.FullTunnelVpnService
import com.haoze.diting.vpn.TunnelStartArgs
import com.haoze.diting.vpn.VpnModeProfile
import com.haoze.diting.vpn.VpnServiceApi
import com.haoze.diting.vpn.VpnStartConfigStore

/** 普通模式（全隧道），与简洁模式共用 [FullTunnelVpnService]。 */
internal class DitingVpnService : FullTunnelVpnService() {
    override fun modeProfile(): VpnModeProfile = VpnModeProfile.NORMAL

    companion object {
        private val PROFILE get() = VpnModeProfile.NORMAL

        internal const val PREFS_NAME = "dns_vpn_prefs"

        internal const val KEY_LAST_DNS_CONFIG = VpnStartConfigStore.KEY_LAST_DNS_CONFIG

        val isRunning: Boolean get() = PROFILE.runtime.isRunning

        fun status(context: Context): Map<String, Any?> = VpnServiceApi.status(context, PROFILE)

        fun trafficRates(): Map<String, Any?> = VpnServiceApi.trafficRates(PROFILE)

        fun isPersistedRunning(context: Context): Boolean =
            PROFILE.runtime.isPersistedRunning(context)

        fun setPersistedRunning(context: Context, value: Boolean) =
            PROFILE.runtime.setPersistedRunning(context, value)

        fun refreshNotification(context: Context): Boolean =
            VpnServiceApi.refreshNotification(context, PROFILE)

        /** 供诊断与自动化使用：当前运行的引擎实例。 */
        fun engineForDiagnostics(): Engine? = PROFILE.runtime.engine

        fun startIntent(
            context: Context,
            dnsConfig: String,
            proxyJson: String,
            bypassLan: Boolean,
            tunnelIpv6: Boolean,
            dnsAaaa: Boolean,
            routeAddress: List<String>,
            routeExcludeAddress: List<String>,
            excludedPackages: List<String>,
            proxyAppPackage: String = "",
            blockedPackages: List<String> = emptyList(),
            inspectionPackages: List<String> = emptyList(),
            inspectionEnabled: Boolean = false,
        ): Intent = VpnServiceApi.startIntent(
            context,
            PROFILE,
            TunnelStartArgs(
                dnsConfig = dnsConfig,
                proxyJson = proxyJson,
                proxyAppPackage = proxyAppPackage,
                bypassLan = bypassLan,
                tunnelIpv6 = tunnelIpv6,
                dnsAaaa = dnsAaaa,
                routeAddress = routeAddress.toSet(),
                routeExcludeAddress = routeExcludeAddress.toSet(),
                excludedPackages = excludedPackages.toSet(),
                blockedPackages = blockedPackages.toSet(),
                inspectionPackages = inspectionPackages.toSet(),
                inspectionEnabled = inspectionEnabled,
            ),
        )

        fun stopIntent(context: Context): Intent = VpnServiceApi.stopIntent(context, PROFILE)

        fun reloadIntent(context: Context): Intent = VpnServiceApi.reloadIntent(context, PROFILE)

        fun requestReload(context: Context) = VpnServiceApi.requestReload(context, PROFILE)

        fun restoreIntent(context: Context): Intent? = VpnServiceApi.restoreIntent(context, PROFILE)
    }
}
