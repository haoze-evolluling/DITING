package com.haoze.diting.normal

import android.content.Context
import android.content.Intent

/// Last start configuration of the full tunnel, replayed by the quick settings tile. Rules are not
/// part of it: the service rebuilds the engine snapshot from the rule database.
internal object VpnStartConfig {
    private const val KEY_LAST_OUTBOUND_PROXY = "last_outbound_proxy"
    private const val KEY_LAST_PROXY_APP = "last_outbound_proxy_app"
    private const val KEY_LAST_BYPASS_LAN = "last_bypass_lan"
    private const val KEY_LAST_IPV6_MODE = "last_ipv6_mode"
    private const val KEY_LAST_EXCLUDED_PACKAGES = "last_excluded_packages"
    private const val KEY_LAST_BLOCKED_PACKAGES = "last_blocked_packages"
    private const val KEY_LAST_INSPECTION_PACKAGES = "last_inspection_packages"
    private const val KEY_LAST_INSPECTION_ENABLED = "last_inspection_enabled"

    // Not wired from Flutter yet; an explicit disabled config stops Go logging a parse failure.
    const val DEFAULT_OUTBOUND_PROXY =
        """{"enabled":false,"protocol":"SOCKS5","host":"127.0.0.1","port":7890,"username":"","password":""}"""

    fun remember(
        context: Context,
        dnsConfig: String,
        proxyJson: String,
        proxyAppPackage: String,
        bypassLan: Boolean,
        ipv6Mode: String,
        excludedPackages: Set<String>,
        blockedPackages: Set<String>,
        inspectionPackages: Set<String>,
        inspectionEnabled: Boolean,
    ) {
        context.getSharedPreferences(DitingVpnService.PREFS_NAME, Context.MODE_PRIVATE).edit()
            .putString(DitingVpnService.KEY_LAST_DNS_CONFIG, dnsConfig)
            .putString(KEY_LAST_OUTBOUND_PROXY, proxyJson)
            .putString(KEY_LAST_PROXY_APP, proxyAppPackage)
            .putBoolean(KEY_LAST_BYPASS_LAN, bypassLan)
            .putString(KEY_LAST_IPV6_MODE, ipv6Mode)
            .putStringSet(KEY_LAST_EXCLUDED_PACKAGES, excludedPackages)
            .putStringSet(KEY_LAST_BLOCKED_PACKAGES, blockedPackages)
            .putStringSet(KEY_LAST_INSPECTION_PACKAGES, inspectionPackages)
            .putBoolean(KEY_LAST_INSPECTION_ENABLED, inspectionEnabled)
            .apply()
    }

    /// Null until the service was started at least once.
    fun restoreIntent(context: Context): Intent? {
        val prefs = context.getSharedPreferences(DitingVpnService.PREFS_NAME, Context.MODE_PRIVATE)
        val dnsConfig = prefs.getString(DitingVpnService.KEY_LAST_DNS_CONFIG, null)
        if (dnsConfig.isNullOrBlank()) return null
        return DitingVpnService.startIntent(
            context = context,
            dnsConfig = dnsConfig,
            proxyJson = prefs.getString(KEY_LAST_OUTBOUND_PROXY, null)
                ?: DEFAULT_OUTBOUND_PROXY,
            bypassLan = prefs.getBoolean(KEY_LAST_BYPASS_LAN, true),
            ipv6Mode = prefs.getString(KEY_LAST_IPV6_MODE, null) ?: "auto",
            excludedPackages = prefs.getStringSet(KEY_LAST_EXCLUDED_PACKAGES, null)
                .orEmpty().toList(),
            proxyAppPackage = prefs.getString(KEY_LAST_PROXY_APP, null).orEmpty(),
            blockedPackages = prefs.getStringSet(KEY_LAST_BLOCKED_PACKAGES, null)
                .orEmpty().toList(),
            inspectionPackages = prefs.getStringSet(KEY_LAST_INSPECTION_PACKAGES, null)
                .orEmpty().toList(),
            inspectionEnabled = prefs.getBoolean(KEY_LAST_INSPECTION_ENABLED, false),
        )
    }
}
