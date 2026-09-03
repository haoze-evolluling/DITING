package com.haoze.dnssr.notification

import android.content.Context

/**
 * 通知配置持久化存储。
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
     * 查询是否启用未连接状态常驻提醒通知。
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
     * 设置是否启用未连接状态常驻提醒通知。
     */
    fun setPersistentNotificationEnabled(context: Context, enabled: Boolean) {
        prefs(context).edit()
            .putBoolean(KEY_PERSISTENT_NOTIFICATION_ENABLED, enabled)
            .apply()
    }

    /**
     * 查询是否在通知栏中展示实时网速。
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
     * 设置是否在通知栏中展示实时网速。
     */
    fun setTrafficSpeedEnabled(context: Context, enabled: Boolean) {
        prefs(context).edit()
            .putBoolean(KEY_TRAFFIC_SPEED_ENABLED, enabled)
            .apply()
    }

    /**
     * 获取用户自定义的服务运行中文案（留空表示使用默认状态文案）。
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
     * 获取用户自定义的服务停止中文案（留空表示使用默认状态文案）。
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
     * 设置自定义文案。
     */
    fun setCustomTexts(context: Context, running: String, stopped: String) {
        prefs(context).edit()
            .putString(KEY_CUSTOM_RUNNING_TEXT, running.trim())
            .putString(KEY_CUSTOM_STOPPED_TEXT, stopped.trim())
            .apply()
    }
}
