package com.haoze.dnssr.ui

import android.content.Context
import android.content.res.Configuration
import java.util.Locale

enum class AppLanguageMode(
    val storageValue: String,
    val displayName: String,
    val locale: Locale?
) {
    SYSTEM("system", "跟随系统", null),
    CHINESE("zh", "中文", Locale.SIMPLIFIED_CHINESE),
    ENGLISH("en", "English", Locale.ENGLISH);

    companion object {
        fun fromStorageValue(value: String?): AppLanguageMode =
            entries.firstOrNull { it.storageValue == value } ?: SYSTEM
    }
}

object AppLanguageManager {
    private const val PREFS_NAME = "dns_vpn_prefs"
    private const val KEY_LANGUAGE_MODE = "app_language_mode"

    fun getMode(context: Context): AppLanguageMode = AppLanguageMode.fromStorageValue(
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_LANGUAGE_MODE, AppLanguageMode.SYSTEM.storageValue)
    )

    fun setMode(context: Context, mode: AppLanguageMode) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_LANGUAGE_MODE, mode.storageValue)
            .apply()
    }

    fun wrap(context: Context): Context {
        val locale = getMode(context).locale ?: run {
            val systemLocale = context.resources.configuration.locales[0]
            if (systemLocale.language.equals(Locale.CHINESE.language, ignoreCase = true)) {
                Locale.SIMPLIFIED_CHINESE
            } else {
                Locale.ENGLISH
            }
        }
        val configuration = Configuration(context.resources.configuration)
        configuration.setLocale(locale)
        return context.createConfigurationContext(configuration)
    }
}
