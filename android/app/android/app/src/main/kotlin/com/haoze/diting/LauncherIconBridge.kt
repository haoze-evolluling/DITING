package com.haoze.diting

import android.app.Activity
import android.content.ComponentName
import android.content.pm.PackageManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class LauncherIconBridge(private val activity: Activity) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.haoze.diting/launcher_icon"

        private const val STYLE_DEFAULT = "default"
        private const val STYLE_ADGUARD = "adguard"

        private const val DEFAULT_ALIAS = "com.haoze.diting.LauncherDefault"
        private const val ADGUARD_ALIAS = "com.haoze.diting.LauncherAdguard"

        private val STYLES = linkedMapOf(
            STYLE_DEFAULT to DEFAULT_ALIAS,
            STYLE_ADGUARD to ADGUARD_ALIAS,
        )
    }

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "get" -> result.success(currentStyle())
            "set" -> {
                val style = call.argument<String>("style")
                if (style == null || !STYLES.containsKey(style)) {
                    result.error("bad-style", "unknown launcher icon style: $style", null)
                    return
                }
                result.success(applyStyle(style))
            }
            else -> result.notImplemented()
        }
    }

    private fun componentName(alias: String): ComponentName =
        ComponentName(activity.packageName, alias)

    private fun currentStyle(): String = try {
        val state = activity.packageManager.getComponentEnabledSetting(
            componentName(ADGUARD_ALIAS)
        )
        if (state == PackageManager.COMPONENT_ENABLED_STATE_ENABLED) {
            STYLE_ADGUARD
        } else {
            STYLE_DEFAULT
        }
    } catch (error: Exception) {
        STYLE_DEFAULT
    }

    private fun applyStyle(style: String): Boolean = try {
        val packageManager = activity.packageManager
        val target = STYLES.getValue(style)
        packageManager.setComponentEnabledSetting(
            componentName(target),
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
            PackageManager.DONT_KILL_APP
        )
        for ((otherStyle, alias) in STYLES) {
            if (otherStyle == style) continue
            packageManager.setComponentEnabledSetting(
                componentName(alias),
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                PackageManager.DONT_KILL_APP
            )
        }
        currentStyle() == style
    } catch (error: Exception) {
        false
    }
}
