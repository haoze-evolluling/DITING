package com.haoze.diting.notification

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

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    /**
     * Returns whether the persistent "VPN disconnected" reminder notification is enabled.
     */
    fun isPersistentNotificationEnabled(context: Context): Boolean =
        prefs(context).getBoolean(
            KEY_PERSISTENT_NOTIFICATION_ENABLED,
            DEFAULT_PERSISTENT_NOTIFICATION_ENABLED
        )

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
    fun isTrafficSpeedEnabled(context: Context): Boolean =
        prefs(context).getBoolean(
            KEY_TRAFFIC_SPEED_ENABLED,
            DEFAULT_TRAFFIC_SPEED_ENABLED
        )

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
    fun getCustomRunningText(context: Context): String =
        prefs(context).getString(KEY_CUSTOM_RUNNING_TEXT, "").orEmpty()

    /**
     * Returns the user-defined "service stopped" notification text
     * (empty means the default status text is used).
     */
    fun getCustomStoppedText(context: Context): String =
        prefs(context).getString(KEY_CUSTOM_STOPPED_TEXT, "").orEmpty()

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
