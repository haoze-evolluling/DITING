package com.haoze.diting.express

import android.content.Context
import android.content.Intent
import com.haoze.diting.vpn.VpnPlanNative

internal object ExpressStartConfig {
    private const val KEY_LAST_OUTBOUND_PROXY = "last_outbound_proxy"
    private const val KEY_LAST_PROXY_APP = "last_outbound_proxy_app"
    private const val KEY_LAST_IPV6_MODE = "last_ipv6_mode"
    private const val KEY_LAST_EXCLUDED_PACKAGES = "last_excluded_packages"

    fun remember(
        context: Context,
        dnsConfig: String,
        proxyJson: String,
        proxyAppPackage: String,
        ipv6Mode: String,
        excludedPackages: Set<String>,
    ) {
        context.getSharedPreferences(ExpressVpnService.PREFS_NAME, Context.MODE_PRIVATE).edit()
            .putString(ExpressVpnService.KEY_LAST_DNS_CONFIG, dnsConfig)
            .putString(KEY_LAST_OUTBOUND_PROXY, proxyJson)
            .putString(KEY_LAST_PROXY_APP, proxyAppPackage)
            .putString(KEY_LAST_IPV6_MODE, ipv6Mode)
            .putStringSet(KEY_LAST_EXCLUDED_PACKAGES, excludedPackages)
            .apply()
    }

    fun restoreIntent(context: Context): Intent? {
        val prefs = context.getSharedPreferences(ExpressVpnService.PREFS_NAME, Context.MODE_PRIVATE)
        val dnsConfig = prefs.getString(ExpressVpnService.KEY_LAST_DNS_CONFIG, null)
        if (dnsConfig.isNullOrBlank()) return null
        val defaults = VpnPlanNative.startDefaults
        return ExpressVpnService.startIntent(
            context = context,
            dnsConfig = dnsConfig,
            proxyJson = prefs.getString(KEY_LAST_OUTBOUND_PROXY, null)
                ?: defaults.outboundProxy,
            ipv6Mode = prefs.getString(KEY_LAST_IPV6_MODE, null) ?: defaults.ipv6Mode,
            excludedPackages = prefs.getStringSet(KEY_LAST_EXCLUDED_PACKAGES, null)
                .orEmpty().toList(),
            proxyAppPackage = prefs.getString(KEY_LAST_PROXY_APP, null).orEmpty(),
        )
    }
}
