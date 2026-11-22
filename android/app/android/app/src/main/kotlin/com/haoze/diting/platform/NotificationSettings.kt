package com.haoze.diting.platform

import android.content.Context

enum class NotificationMode(internal val defaultKey: String) {
    NORMAL("default_running_text"),
    EXPRESS("default_express_text"),
}

object NotificationSettings {
    private const val PREFS = "notification_settings_prefs"

    private const val KEY_PERSISTENT = "persistent"
    private const val KEY_SPEED = "speed"
    private const val KEY_RUNNING_TEXT = "custom_running_text"
    private const val KEY_STATS_ITEMS = "stats_items"
    private const val KEY_STATS_LABELS = "stats_labels"

    fun persistent(context: Context): Boolean =
        prefs(context).getBoolean(KEY_PERSISTENT, true)

    fun showSpeed(context: Context): Boolean = "speed" in statsItems(context)

    fun statsItems(context: Context): List<String> {
        val prefs = prefs(context)
        val raw = prefs.getString(KEY_STATS_ITEMS, null)
        return NotificationNative.statsItems(
            raw = raw.orEmpty(),
            hasRaw = raw != null,
            legacySpeed = prefs.getBoolean(KEY_SPEED, false),
        )
    }

    fun hasLiveItems(context: Context): Boolean = statsItems(context).isNotEmpty()

    fun statsLabelsJson(context: Context): String? =
        prefs(context).getString(KEY_STATS_LABELS, null)

    fun runningText(context: Context, mode: NotificationMode, fallback: String): String {
        val prefs = prefs(context)
        return NotificationNative.runningText(
            custom = prefs.getString(KEY_RUNNING_TEXT, null).orEmpty(),
            modeDefault = prefs.getString(mode.defaultKey, null).orEmpty(),
            fallback = fallback,
        )
    }

    private fun prefs(context: Context) = context.getSharedPreferences(
        PREFS,
        Context.MODE_PRIVATE,
    )
}
