package com.haoze.diting.vpn

import android.content.Context
import android.content.Intent

/** 一次隧道启动的完整参数集合，普通模式与简洁模式共用。 */
internal data class TunnelStartArgs(
    val dnsConfig: String,
    val proxyJson: String,
    val proxyAppPackage: String,
    val bypassLan: Boolean,
    val tunnelIpv6: Boolean,
    val dnsAaaa: Boolean,
    val routeAddress: Set<String>,
    val routeExcludeAddress: Set<String>,
    val excludedPackages: Set<String>,
    val blockedPackages: Set<String>,
    val inspectionPackages: Set<String>,
    val inspectionEnabled: Boolean,
)

/**
 * 记录最近一次启动参数，供磁贴/小组件/自动化冷启动与 VpnReclaimer 重连使用。
 *
 * 两种模式各自使用自己的偏好容器（普通 `dns_vpn_prefs`、简洁 `express_vpn_prefs`），
 * 因此需要记忆的字段完全一致。
 */
internal class VpnStartConfigStore(private val prefsName: String) {
    fun remember(context: Context, args: TunnelStartArgs) {
        context.getSharedPreferences(prefsName, Context.MODE_PRIVATE).edit()
            .putString(KEY_LAST_DNS_CONFIG, args.dnsConfig)
            .putString(KEY_LAST_OUTBOUND_PROXY, args.proxyJson)
            .putString(KEY_LAST_PROXY_APP, args.proxyAppPackage)
            .putBoolean(KEY_LAST_BYPASS_LAN, args.bypassLan)
            .putBoolean(KEY_LAST_TUNNEL_IPV6, args.tunnelIpv6)
            .putBoolean(KEY_LAST_DNS_AAAA, args.dnsAaaa)
            .putStringSet(KEY_LAST_ROUTE_ADDRESS, args.routeAddress)
            .putStringSet(KEY_LAST_ROUTE_EXCLUDE_ADDRESS, args.routeExcludeAddress)
            .putStringSet(KEY_LAST_EXCLUDED_PACKAGES, args.excludedPackages)
            .putStringSet(KEY_LAST_BLOCKED_PACKAGES, args.blockedPackages)
            .putStringSet(KEY_LAST_INSPECTION_PACKAGES, args.inspectionPackages)
            .putBoolean(KEY_LAST_INSPECTION_ENABLED, args.inspectionEnabled)
            .apply()
    }

    fun restoreIntent(
        context: Context,
        buildIntent: (TunnelStartArgs) -> Intent,
    ): Intent? {
        val prefs = context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
        val dnsConfig = prefs.getString(KEY_LAST_DNS_CONFIG, null)
        if (dnsConfig.isNullOrBlank()) return null
        val defaults = VpnPlanNative.startDefaults
        val legacyPrefer =
            prefs.getString(KEY_LAST_IPV6_MODE, null)?.trim()?.lowercase() == "prefer"
        return buildIntent(
            TunnelStartArgs(
                dnsConfig = dnsConfig,
                proxyJson = prefs.getString(KEY_LAST_OUTBOUND_PROXY, null)
                    ?: defaults.outboundProxy,
                proxyAppPackage = prefs.getString(KEY_LAST_PROXY_APP, null).orEmpty(),
                bypassLan = prefs.getBoolean(KEY_LAST_BYPASS_LAN, defaults.bypassLan),
                tunnelIpv6 = if (prefs.contains(KEY_LAST_TUNNEL_IPV6)) {
                    prefs.getBoolean(KEY_LAST_TUNNEL_IPV6, defaults.tunnelIpv6)
                } else {
                    legacyPrefer
                },
                dnsAaaa = if (prefs.contains(KEY_LAST_DNS_AAAA)) {
                    prefs.getBoolean(KEY_LAST_DNS_AAAA, defaults.dnsAaaa)
                } else {
                    legacyPrefer
                },
                routeAddress = prefs.getStringSet(KEY_LAST_ROUTE_ADDRESS, null)
                    ?: defaults.routeAddress.toSet(),
                routeExcludeAddress = prefs.getStringSet(KEY_LAST_ROUTE_EXCLUDE_ADDRESS, null)
                    ?: defaults.routeExcludeAddress.toSet(),
                excludedPackages = prefs.getStringSet(KEY_LAST_EXCLUDED_PACKAGES, null)
                    .orEmpty(),
                blockedPackages = prefs.getStringSet(KEY_LAST_BLOCKED_PACKAGES, null)
                    .orEmpty(),
                inspectionPackages = prefs.getStringSet(KEY_LAST_INSPECTION_PACKAGES, null)
                    .orEmpty(),
                inspectionEnabled = prefs.getBoolean(
                    KEY_LAST_INSPECTION_ENABLED,
                    defaults.inspectionEnabled,
                ),
            ),
        )
    }

    companion object {
        const val KEY_LAST_DNS_CONFIG = "last_dns_config"

        private const val KEY_LAST_OUTBOUND_PROXY = "last_outbound_proxy"
        private const val KEY_LAST_PROXY_APP = "last_outbound_proxy_app"
        private const val KEY_LAST_BYPASS_LAN = "last_bypass_lan"
        private const val KEY_LAST_TUNNEL_IPV6 = "last_tunnel_ipv6"
        private const val KEY_LAST_DNS_AAAA = "last_dns_aaaa"
        private const val KEY_LAST_ROUTE_ADDRESS = "last_route_address"
        private const val KEY_LAST_ROUTE_EXCLUDE_ADDRESS = "last_route_exclude_address"
        private const val KEY_LAST_IPV6_MODE = "last_ipv6_mode"
        private const val KEY_LAST_EXCLUDED_PACKAGES = "last_excluded_packages"
        private const val KEY_LAST_BLOCKED_PACKAGES = "last_blocked_packages"
        private const val KEY_LAST_INSPECTION_PACKAGES = "last_inspection_packages"
        private const val KEY_LAST_INSPECTION_ENABLED = "last_inspection_enabled"
    }
}
