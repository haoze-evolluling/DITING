package com.haoze.diting.ui.mode

import android.content.Context

object WorkModeStore {
    private const val PREFS_NAME = "diting_settings"
    private const val KEY_APP_WORK_MODE = "app_work_mode"
    private const val KEY_WORK_MODE_INITIAL_SELECTED = "work_mode_initial_selected"

    fun getAppWorkMode(context: Context): AppWorkMode {
        val value = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_APP_WORK_MODE, null)
        return AppWorkMode.fromStorageValue(value)
    }

    fun setAppWorkMode(context: Context, mode: AppWorkMode) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_APP_WORK_MODE, mode.storageValue)
            .apply()
    }

    fun hasSelectedWorkMode(context: Context): Boolean {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_WORK_MODE_INITIAL_SELECTED, false)
    }

    fun setWorkModeSelected(context: Context, selected: Boolean = true) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_WORK_MODE_INITIAL_SELECTED, selected)
            .apply()
    }

    fun resetWorkModeSelection(context: Context) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .remove(KEY_APP_WORK_MODE)
            .remove(KEY_WORK_MODE_INITIAL_SELECTED)
            .apply()
    }
}
