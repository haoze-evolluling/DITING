package com.haoze.diting.ui

import android.content.Context

object PermissionDisclosureSettings {
    private const val PREFS_NAME = "permission_disclosures"
    private const val KEY_APP_LIST_EXPLAINED = "app_list_explained"
    private const val KEY_APP_LIST_EVER_AVAILABLE = "app_list_ever_available"
    private const val KEY_VPN_EXPLAINED = "vpn_explained"
    private const val KEY_VPN_WAS_GRANTED = "vpn_was_granted"

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun isAppListExplained(context: Context): Boolean =
        com.haoze.diting.permission.AppListPermissionHelper.isDisclosureAccepted(context)

    fun setAppListExplained(context: Context, explained: Boolean) {
        com.haoze.diting.permission.AppListPermissionHelper.setDisclosureAccepted(context, explained)
    }

    fun wasAppListAvailable(context: Context): Boolean =
        com.haoze.diting.permission.AppListPermissionHelper.isGranted(context)

    fun markAppListAvailable(context: Context) {
        // AppListPermissionHelper manages live detection dynamically
    }

    fun isVpnExplained(context: Context): Boolean =
        prefs(context).getBoolean(KEY_VPN_EXPLAINED, false)

    fun setVpnExplained(context: Context, explained: Boolean) {
        prefs(context).edit().putBoolean(KEY_VPN_EXPLAINED, explained).apply()
    }

    fun updateVpnGrant(context: Context, granted: Boolean) {
        val preferences = prefs(context)
        if (!granted && preferences.getBoolean(KEY_VPN_WAS_GRANTED, false)) {
            preferences.edit()
                .putBoolean(KEY_VPN_WAS_GRANTED, false)
                .putBoolean(KEY_VPN_EXPLAINED, false)
                .apply()
        } else if (granted) {
            preferences.edit().putBoolean(KEY_VPN_WAS_GRANTED, true).apply()
        }
    }
}
