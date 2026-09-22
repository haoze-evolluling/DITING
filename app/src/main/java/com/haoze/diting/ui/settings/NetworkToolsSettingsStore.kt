package com.haoze.diting.ui.settings

import android.content.Context

/**
 * Persists the per-tool "resolve via Go tunnel" toggles of the network
 * diagnostics screen. Defaults to off so tools keep probing the physical
 * network directly.
 */
object NetworkToolsSettingsStore {
    private const val PREFS_NAME = "network_tools_settings"
    private const val KEY_PING_VIA_TUNNEL = "ping_via_tunnel"
    private const val KEY_DNS_LOOKUP_VIA_TUNNEL = "dns_lookup_via_tunnel"
    private const val KEY_TRACEROUTE_VIA_TUNNEL = "traceroute_via_tunnel"

    fun isPingViaTunnel(context: Context): Boolean =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_PING_VIA_TUNNEL, false)

    fun setPingViaTunnel(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit().putBoolean(KEY_PING_VIA_TUNNEL, enabled).apply()
    }

    fun isDnsLookupViaTunnel(context: Context): Boolean =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_DNS_LOOKUP_VIA_TUNNEL, false)

    fun setDnsLookupViaTunnel(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit().putBoolean(KEY_DNS_LOOKUP_VIA_TUNNEL, enabled).apply()
    }

    fun isTracerouteViaTunnel(context: Context): Boolean =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_TRACEROUTE_VIA_TUNNEL, false)

    fun setTracerouteViaTunnel(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit().putBoolean(KEY_TRACEROUTE_VIA_TUNNEL, enabled).apply()
    }
}
