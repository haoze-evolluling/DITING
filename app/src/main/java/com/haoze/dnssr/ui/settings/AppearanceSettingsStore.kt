package com.haoze.dnssr.ui.settings

import android.content.Context
import com.haoze.dnssr.ui.AppThemeMode
import com.haoze.dnssr.ui.theme.ThemeColorStyle
import org.json.JSONArray

object AppearanceSettingsStore {
    const val DEFAULT_HOME_COMPONENT_OPACITY = 1f

    private const val KEY_APP_THEME_MODE = "app_theme_mode"
    private const val KEY_THEME_COLOR_STYLE = "theme_color_style"
    private const val KEY_HOME_COMPONENT_OPACITY = "home_component_opacity"
    private const val KEY_HOME_POWER_BUTTON_OPACITY = "home_power_button_opacity"
    private const val KEY_HOME_PROVIDER_SELECTOR_OPACITY = "home_provider_selector_opacity"
    private const val KEY_HOME_MODE_BUTTON_OPACITY = "home_mode_button_opacity"
    private const val KEY_HOME_POEM_OPACITY = "home_poem_opacity"
    private const val KEY_HOME_DNS_DETAIL_OPACITY = "home_dns_detail_opacity"
    private const val KEY_HOME_SENTENCE_RUNNING = "home_sentence_running"
    private const val KEY_HOME_SENTENCE_STOPPED = "home_sentence_stopped"
    private const val KEY_CUSTOM_BACKGROUND_ENABLED = "custom_background_enabled"
    private const val KEY_CUSTOM_BACKGROUND_URI = "custom_background_uri"
    private const val KEY_CUSTOM_BACKGROUND_URIS = "custom_background_uris"

    fun getAppThemeMode(context: Context): AppThemeMode {
        val value = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_APP_THEME_MODE, null)
        return AppThemeMode.fromStorageValue(value)
    }

    fun setAppThemeMode(context: Context, mode: AppThemeMode) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_APP_THEME_MODE, mode.storageValue)
            .apply()
    }

    fun getThemeColorStyle(context: Context): ThemeColorStyle {
        val value = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_THEME_COLOR_STYLE, null)
        return ThemeColorStyle.fromStorageValue(value)
    }

    fun setThemeColorStyle(context: Context, style: ThemeColorStyle) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_THEME_COLOR_STYLE, style.storageValue)
            .apply()
    }

    fun getHomeComponentOpacity(context: Context): Float {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getFloat(KEY_HOME_COMPONENT_OPACITY, DEFAULT_HOME_COMPONENT_OPACITY)
            .coerceIn(0.1f, 1f)
    }

    fun setHomeComponentOpacity(context: Context, opacity: Float) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putFloat(KEY_HOME_COMPONENT_OPACITY, opacity.coerceIn(0.1f, 1f))
            .apply()
    }

    private fun getHomeOpacity(context: Context, key: String): Float {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getFloat(key, prefs.getFloat(KEY_HOME_COMPONENT_OPACITY, DEFAULT_HOME_COMPONENT_OPACITY))
            .coerceIn(0.1f, 1f)
    }

    private fun setHomeOpacity(context: Context, key: String, opacity: Float) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putFloat(key, opacity.coerceIn(0.1f, 1f))
            .apply()
    }

    fun getHomePowerButtonOpacity(context: Context) = getHomeOpacity(context, KEY_HOME_POWER_BUTTON_OPACITY)
    fun setHomePowerButtonOpacity(context: Context, opacity: Float) =
        setHomeOpacity(context, KEY_HOME_POWER_BUTTON_OPACITY, opacity)

    fun getHomeProviderSelectorOpacity(context: Context) = getHomeOpacity(context, KEY_HOME_PROVIDER_SELECTOR_OPACITY)
    fun setHomeProviderSelectorOpacity(context: Context, opacity: Float) =
        setHomeOpacity(context, KEY_HOME_PROVIDER_SELECTOR_OPACITY, opacity)

    fun getHomeModeButtonOpacity(context: Context) = getHomeOpacity(context, KEY_HOME_MODE_BUTTON_OPACITY)
    fun setHomeModeButtonOpacity(context: Context, opacity: Float) =
        setHomeOpacity(context, KEY_HOME_MODE_BUTTON_OPACITY, opacity)

    fun getHomePoemOpacity(context: Context) = getHomeOpacity(context, KEY_HOME_POEM_OPACITY)
    fun setHomePoemOpacity(context: Context, opacity: Float) =
        setHomeOpacity(context, KEY_HOME_POEM_OPACITY, opacity)

    fun getHomeDnsDetailOpacity(context: Context) = getHomeOpacity(context, KEY_HOME_DNS_DETAIL_OPACITY)
    fun setHomeDnsDetailOpacity(context: Context, opacity: Float) =
        setHomeOpacity(context, KEY_HOME_DNS_DETAIL_OPACITY, opacity)

    fun getHomeSentenceRunning(context: Context): String {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_HOME_SENTENCE_RUNNING, "谛听万象，明察清浊")
            .orEmpty()
    }

    fun getHomeSentenceStopped(context: Context): String {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_HOME_SENTENCE_STOPPED, "收耳静眠，归于无声")
            .orEmpty()
    }

    fun setHomeSentences(context: Context, running: String, stopped: String) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_HOME_SENTENCE_RUNNING, running)
            .putString(KEY_HOME_SENTENCE_STOPPED, stopped)
            .apply()
    }

    fun isCustomBackgroundEnabled(context: Context): Boolean {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getBoolean(KEY_CUSTOM_BACKGROUND_ENABLED, false) &&
            getCustomBackgroundUri(context) in getCustomBackgroundUris(context)
    }

    fun getCustomBackgroundUri(context: Context): String? {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_CUSTOM_BACKGROUND_URI, null)
    }

    fun getCustomBackgroundUris(context: Context): List<String> {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val stored = prefs.getString(KEY_CUSTOM_BACKGROUND_URIS, null) ?: return emptyList()
        return try {
            val array = JSONArray(stored)
            buildList {
                for (index in 0 until array.length()) {
                    array.optString(index).takeIf { it.isNotBlank() }?.let(::add)
                }
            }.distinct()
        } catch (_: Exception) {
            emptyList()
        }
    }

    fun addCustomBackgroundUri(context: Context, uri: String) {
        val normalizedUri = uri.takeIf { it.isNotBlank() } ?: return
        val uris = getCustomBackgroundUris(context)
        if (normalizedUri !in uris) {
            saveCustomBackgroundUris(context, uris + normalizedUri)
        }
    }

    fun removeCustomBackgroundUri(context: Context, uri: String) {
        val remainingUris = getCustomBackgroundUris(context).filterNot { it == uri }
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val isCurrentUri = prefs.getString(KEY_CUSTOM_BACKGROUND_URI, null) == uri
        saveCustomBackgroundUris(context, remainingUris)
        if (isCurrentUri) {
            prefs.edit()
                .putBoolean(KEY_CUSTOM_BACKGROUND_ENABLED, false)
                .putString(KEY_CUSTOM_BACKGROUND_URI, null)
                .apply()
        }
    }

    fun setCustomBackground(context: Context, enabled: Boolean, uri: String?) {
        val normalizedUri = uri?.takeIf { it.isNotBlank() }
        if (normalizedUri != null) addCustomBackgroundUri(context, normalizedUri)
        val actualEnabled = enabled && normalizedUri != null
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_CUSTOM_BACKGROUND_ENABLED, actualEnabled)
            .putString(KEY_CUSTOM_BACKGROUND_URI, normalizedUri)
            .apply()
    }

    private fun saveCustomBackgroundUris(context: Context, uris: List<String>) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_CUSTOM_BACKGROUND_URIS, JSONArray(uris.distinct()).toString())
            .apply()
    }

}
