package com.haoze.dnssr.notification

import android.content.Context

/**
 * Persistent store for notification settings.
 */
object NotificationSettingsStore {

    private const val PREFS_NAME = "notification_settings_prefs"

    const val KEY_PERSISTENT_NOTIFICATION_ENABLED = "notification_persistent_enabled"
    const val KEY_TRAFFIC_SPEED_ENABLED = "notification_traffic_speed_enabled"
    const val KEY_CUSTOM_RUNNING_TEXT = "notification_custom_running_text"
    const val KEY_CUSTOM_STOPPED_TEXT = "notification_custom_stopped_text"

    const val DEFAULT_PERSISTENT_NOTIFICATION_ENABLED = true
    const val DEFAULT_TRAFFIC_SPEED_ENABLED = false

    private const val LEGACY_PREFS_NAME = "dns_vpn_prefs"
    private const val LEGACY_KEY_PERSISTENT_NOTIFICATION_ENABLED = "persistent_notification_enabled"
    private const val LEGACY_KEY_TRAFFIC_SPEED_ENABLED = "traffic_notification_speed_enabled"
    private const val LEGACY_KEY_CUSTOM_RUNNING_TEXT = "notification_text_running"
    private const val LEGACY_KEY_CUSTOM_STOPPED_TEXT = "notification_text_stopped"

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    /**
     * Returns whether the persistent "VPN disconnected" reminder notification is enabled.
     */
    fun isPersistentNotificationEnabled(context: Context): Boolean {
        val p = prefs(context)
        if (p.contains(KEY_PERSISTENT_NOTIFICATION_ENABLED)) {
            return p.getBoolean(
                KEY_PERSISTENT_NOTIFICATION_ENABLED,
                DEFAULT_PERSISTENT_NOTIFICATION_ENABLED
            )
        }
        val legacyPrefs = context.getSharedPreferences(LEGACY_PREFS_NAME, Context.MODE_PRIVATE)
        if (legacyPrefs.contains(LEGACY_KEY_PERSISTENT_NOTIFICATION_ENABLED)) {
            val legacyValue = legacyPrefs.getBoolean(
                LEGACY_KEY_PERSISTENT_NOTIFICATION_ENABLED,
                DEFAULT_PERSISTENT_NOTIFICATION_ENABLED
            )
            p.edit().putBoolean(KEY_PERSISTENT_NOTIFICATION_ENABLED, legacyValue).apply()
            return legacyValue
        }
        return DEFAULT_PERSISTENT_NOTIFICATION_ENABLED
    }

    /**
     * Enables or disables the persistent "VPN disconnected" reminder notification.
     */
    fun setPersistentNotificationEnabled(context: Context, enabled: Boolean) {
        prefs(context).edit()
            .putBoolean(KEY_PERSISTENT_NOTIFICATION_ENABLED, enabled)
            .apply()
    }

    /**
     * Returns whether the live transfer speed is shown in the notification.
     */
    fun isTrafficSpeedEnabled(context: Context): Boolean {
        val p = prefs(context)
        if (p.contains(KEY_TRAFFIC_SPEED_ENABLED)) {
            return p.getBoolean(
                KEY_TRAFFIC_SPEED_ENABLED,
                DEFAULT_TRAFFIC_SPEED_ENABLED
            )
        }
        val legacyPrefs = context.getSharedPreferences(LEGACY_PREFS_NAME, Context.MODE_PRIVATE)
        if (legacyPrefs.contains(LEGACY_KEY_TRAFFIC_SPEED_ENABLED)) {
            val legacyValue = legacyPrefs.getBoolean(
                LEGACY_KEY_TRAFFIC_SPEED_ENABLED,
                DEFAULT_TRAFFIC_SPEED_ENABLED
            )
            p.edit().putBoolean(KEY_TRAFFIC_SPEED_ENABLED, legacyValue).apply()
            return legacyValue
        }
        return DEFAULT_TRAFFIC_SPEED_ENABLED
    }

    /**
     * Sets whether the live transfer speed is shown in the notification.
     */
    fun setTrafficSpeedEnabled(context: Context, enabled: Boolean) {
        prefs(context).edit()
            .putBoolean(KEY_TRAFFIC_SPEED_ENABLED, enabled)
            .apply()
    }

    /**
     * Returns the user-defined "service running" notification text
     * (empty means the default status text is used).
     */
    fun getCustomRunningText(context: Context): String {
        val p = prefs(context)
        if (p.contains(KEY_CUSTOM_RUNNING_TEXT)) {
            return p.getString(KEY_CUSTOM_RUNNING_TEXT, "").orEmpty()
        }
        val legacyPrefs = context.getSharedPreferences(LEGACY_PREFS_NAME, Context.MODE_PRIVATE)
        if (legacyPrefs.contains(LEGACY_KEY_CUSTOM_RUNNING_TEXT)) {
            val legacyValue = legacyPrefs.getString(LEGACY_KEY_CUSTOM_RUNNING_TEXT, "").orEmpty()
            p.edit().putString(KEY_CUSTOM_RUNNING_TEXT, legacyValue).apply()
            return legacyValue
        }
        return ""
    }

    /**
     * Returns the user-defined "service stopped" notification text
     * (empty means the default status text is used).
     */
    fun getCustomStoppedText(context: Context): String {
        val p = prefs(context)
        if (p.contains(KEY_CUSTOM_STOPPED_TEXT)) {
            return p.getString(KEY_CUSTOM_STOPPED_TEXT, "").orEmpty()
        }
        val legacyPrefs = context.getSharedPreferences(LEGACY_PREFS_NAME, Context.MODE_PRIVATE)
        if (legacyPrefs.contains(LEGACY_KEY_CUSTOM_STOPPED_TEXT)) {
            val legacyValue = legacyPrefs.getString(LEGACY_KEY_CUSTOM_STOPPED_TEXT, "").orEmpty()
            p.edit().putString(KEY_CUSTOM_STOPPED_TEXT, legacyValue).apply()
            return legacyValue
        }
        return ""
    }

    /**
     * Sets the custom notification texts.
     */
    fun setCustomTexts(context: Context, running: String, stopped: String) {
        prefs(context).edit()
            .putString(KEY_CUSTOM_RUNNING_TEXT, running.trim())
            .putString(KEY_CUSTOM_STOPPED_TEXT, stopped.trim())
            .apply()
    }
}
