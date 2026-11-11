package com.haoze.diting

import android.app.Activity
import android.content.ComponentName
import android.content.pm.PackageManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/// Switches the home-screen icon by enabling exactly one of the `activity-alias` entries declared
/// in `AndroidManifest.xml` (`.LauncherDefault`, `.LauncherAdguard`).
///
/// Android has no API to repaint an installed activity's icon at runtime; the supported pattern is
/// one alias per style with only one enabled at a time. PackageManager persists those component
/// flags across restarts, but Dart also mirrors the choice into preferences and re-applies it on
/// launch, in case an update or a manifest change reset the flags.
class LauncherIconBridge(private val activity: Activity) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.haoze.diting/launcher_icon"

        private const val STYLE_DEFAULT = "default"
        private const val STYLE_ADGUARD = "adguard"

        /// Full class names of the manifest aliases. They resolve against the manifest package
        /// (`com.haoze.diting`), not the applicationId.
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

    private fun componentName(alias: String) =
        ComponentName(activity.packageName, alias)

    /// The AdGuard alias is the only one ever explicitly enabled, so a non-enabled value means the
    /// manifest default (`LauncherDefault`) is in effect.
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
        // A renamed/removed alias must never crash the settings page.
        STYLE_DEFAULT
    }

    private fun applyStyle(style: String): Boolean = try {
        val packageManager = activity.packageManager
        val target = STYLES.getValue(style)
        // Enable the target first so the launcher always has exactly one entry, then retire the
        // rest. DONT_KILL_APP keeps this session (and a running tunnel) alive.
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
