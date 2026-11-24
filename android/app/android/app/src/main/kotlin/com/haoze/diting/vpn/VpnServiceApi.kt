package com.haoze.diting.vpn

import android.content.Context
import android.content.Intent

/** 两种模式的静态门面：报文构造、状态查询与通知刷新。 */
internal object VpnServiceApi {
    const val EXTRA_DNS_CONFIG = "dns_config"
    const val EXTRA_OUTBOUND_PROXY = "outbound_proxy"
    const val EXTRA_PROXY_APP = "proxy_app_package"
    const val EXTRA_BYPASS_LAN = "bypass_lan"
    const val EXTRA_IPV6_MODE = "ipv6_mode"
    const val EXTRA_ROUTE_ADDRESS = "route_address"
    const val EXTRA_ROUTE_EXCLUDE_ADDRESS = "route_exclude_address"
    const val EXTRA_EXCLUDED_PACKAGES = "excluded_packages"
    const val EXTRA_BLOCKED_PACKAGES = "blocked_packages"
    const val EXTRA_INSPECTION_PACKAGES = "inspection_packages"
    const val EXTRA_INSPECTION_ENABLED = "inspection_enabled"

    fun startIntent(
        context: Context,
        profile: VpnModeProfile,
        args: TunnelStartArgs,
    ): Intent = Intent(context, profile.serviceClass).apply {
        action = profile.startAction
        putExtra(EXTRA_DNS_CONFIG, args.dnsConfig)
        putExtra(EXTRA_OUTBOUND_PROXY, args.proxyJson)
        putExtra(EXTRA_PROXY_APP, args.proxyAppPackage)
        putExtra(EXTRA_BYPASS_LAN, args.bypassLan)
        putExtra(EXTRA_IPV6_MODE, args.ipv6Mode)
        putStringArrayListExtra(EXTRA_ROUTE_ADDRESS, ArrayList(args.routeAddress))
        putStringArrayListExtra(EXTRA_ROUTE_EXCLUDE_ADDRESS, ArrayList(args.routeExcludeAddress))
        putStringArrayListExtra(EXTRA_EXCLUDED_PACKAGES, ArrayList(args.excludedPackages))
        putStringArrayListExtra(EXTRA_BLOCKED_PACKAGES, ArrayList(args.blockedPackages))
        putStringArrayListExtra(EXTRA_INSPECTION_PACKAGES, ArrayList(args.inspectionPackages))
        putExtra(EXTRA_INSPECTION_ENABLED, args.inspectionEnabled)
    }

    fun stopIntent(context: Context, profile: VpnModeProfile): Intent =
        Intent(context, profile.serviceClass).setAction(profile.stopAction)

    fun reloadIntent(context: Context, profile: VpnModeProfile): Intent =
        Intent(context, profile.serviceClass).setAction(profile.reloadAction)

    fun requestReload(context: Context, profile: VpnModeProfile) {
        if (!profile.runtime.isRunning) return
        runCatching { context.startService(reloadIntent(context, profile)) }
    }

    fun restoreIntent(context: Context, profile: VpnModeProfile): Intent? =
        profile.startConfig.restoreIntent(context) { args -> startIntent(context, profile, args) }

    fun status(context: Context, profile: VpnModeProfile): Map<String, Any?> =
        profile.runtime.status(context)

    fun trafficRates(profile: VpnModeProfile): Map<String, Any?> =
        profile.runtime.trafficRates()

    fun refreshNotification(context: Context, profile: VpnModeProfile): Boolean =
        profile.runtime.isRunning && VpnModeNotification.rerender(context, profile)
}
