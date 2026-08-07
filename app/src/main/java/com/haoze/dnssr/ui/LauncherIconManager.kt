package com.haoze.dnssr.ui

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager

object LauncherIconManager {
    private const val CURRENT_ALIAS = "com.haoze.dnssr.MainActivityCurrentIconAlias"
    private const val LEGACY_ALIAS = "com.haoze.dnssr.MainActivityLegacyIconAlias"

    fun applyPreferredIcon(context: Context) {
        setLegacyIconEnabled(
            context = context,
            enabled = AppSettings.isLegacyIconEnabled(context)
        )
    }

    fun setLegacyIconEnabled(
        context: Context,
        enabled: Boolean
    ) {
        val packageManager = context.packageManager
        val currentAlias = ComponentName(context.packageName, CURRENT_ALIAS)
        val legacyAlias = ComponentName(context.packageName, LEGACY_ALIAS)

        if (enabled) {
            setComponentEnabled(packageManager, legacyAlias, true)
            setComponentEnabled(packageManager, currentAlias, false)
        } else {
            setComponentEnabled(packageManager, currentAlias, true)
            setComponentEnabled(packageManager, legacyAlias, false)
        }
    }

    private fun setComponentEnabled(
        packageManager: PackageManager,
        componentName: ComponentName,
        enabled: Boolean
    ) {
        val targetState = if (enabled) {
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED
        } else {
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED
        }
        if (packageManager.getComponentEnabledSetting(componentName) == targetState) return

        packageManager.setComponentEnabledSetting(
            componentName,
            targetState,
            PackageManager.DONT_KILL_APP
        )
    }
}
