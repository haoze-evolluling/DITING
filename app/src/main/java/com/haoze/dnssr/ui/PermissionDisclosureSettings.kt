package com.haoze.dnssr.ui

import android.content.Context

object PermissionDisclosureSettings {
    private const val PREFS_NAME = "permission_disclosures"
    private const val KEY_APP_LIST_EXPLAINED = "app_list_explained"
    private const val KEY_APP_LIST_EVER_AVAILABLE = "app_list_ever_available"
    private const val KEY_NOTIFICATION_EXPLAINED = "notification_explained"
    private const val KEY_NOTIFICATION_REQUESTED = "notification_requested"
    private const val KEY_NOTIFICATION_WAS_GRANTED = "notification_was_granted"
    private const val KEY_VPN_EXPLAINED = "vpn_explained"
    private const val KEY_VPN_WAS_GRANTED = "vpn_was_granted"

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun isAppListExplained(context: Context): Boolean =
        prefs(context).getBoolean(KEY_APP_LIST_EXPLAINED, false)

    fun setAppListExplained(context: Context, explained: Boolean) {
        prefs(context).edit().putBoolean(KEY_APP_LIST_EXPLAINED, explained).apply()
    }

    fun wasAppListAvailable(context: Context): Boolean =
        prefs(context).getBoolean(KEY_APP_LIST_EVER_AVAILABLE, false)

    fun markAppListAvailable(context: Context) {
        prefs(context).edit().putBoolean(KEY_APP_LIST_EVER_AVAILABLE, true).apply()
    }

    fun isNotificationExplained(context: Context): Boolean =
        prefs(context).getBoolean(KEY_NOTIFICATION_EXPLAINED, false)

    fun setNotificationExplained(context: Context, explained: Boolean) {
        prefs(context).edit().putBoolean(KEY_NOTIFICATION_EXPLAINED, explained).apply()
    }

    fun wasNotificationRequested(context: Context): Boolean =
        prefs(context).getBoolean(KEY_NOTIFICATION_REQUESTED, false)

    fun markNotificationRequested(context: Context) {
        prefs(context).edit().putBoolean(KEY_NOTIFICATION_REQUESTED, true).apply()
    }

    fun updateNotificationGrant(context: Context, granted: Boolean) {
        val preferences = prefs(context)
        if (!granted && preferences.getBoolean(KEY_NOTIFICATION_WAS_GRANTED, false)) {
            preferences.edit()
                .putBoolean(KEY_NOTIFICATION_WAS_GRANTED, false)
                .putBoolean(KEY_NOTIFICATION_EXPLAINED, false)
                .putBoolean(KEY_NOTIFICATION_REQUESTED, false)
                .apply()
        } else if (granted) {
            preferences.edit().putBoolean(KEY_NOTIFICATION_WAS_GRANTED, true).apply()
        }
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

    fun wasVpnGranted(context: Context): Boolean =
        prefs(context).getBoolean(KEY_VPN_WAS_GRANTED, false)
}
