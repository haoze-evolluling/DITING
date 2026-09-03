package com.haoze.dnssr.ui

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager

object LauncherIconManager {
    private const val CURRENT_ALIAS = "com.haoze.dnssr.MainActivityCurrentIconAlias"

    fun applyPreferredIcon(context: Context) {
        val packageManager = context.packageManager
        val currentAlias = ComponentName(context.packageName, CURRENT_ALIAS)
        if (packageManager.getComponentEnabledSetting(currentAlias) != PackageManager.COMPONENT_ENABLED_STATE_ENABLED) {
            packageManager.setComponentEnabledSetting(
                currentAlias,
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                PackageManager.DONT_KILL_APP
            )
        }
    }
}
