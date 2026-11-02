package com.haoze.diting

import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/// Exposes the legacy SharedPreferences containers; shared_preferences would prefix file names.
class LegacyPrefsBridge(private val context: Context) :
    MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.haoze.diting/legacy_prefs"

        /// Legacy upgrade contracts; the whitelist makes a typo fail, not create a dead file
        val CONTAINERS = setOf(
            "dns_vpn_prefs",
            "diting_express_prefs",
            "diting_dns_mode_prefs",
            "express_vpn_prefs",
            "diting_settings",
            "permission_disclosures",
            "mode_permission_preferences",
            "notification_settings_prefs",
            "diting_crash_state",
            "network_tools_settings",
            "recognition_members",
            // Port-specific, no legacy equivalent.
            "diting_config_resources",
        )
    }

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        // Single source of versions: the Gradle plugin stamps pubspec.yaml's version in.
        if (call.method == "versionInfo") {
            result.success(versionInfo())
            return
        }
        // Startup reads every container at once; twelve serial `readAll` calls paid a channel
        // round trip each and parsed the XML files on the main thread.
        if (call.method == "readAllAll") {
            readAllAll(result)
            return
        }
        val container = call.argument<String>("container")
        if (container == null || container !in CONTAINERS) {
            result.error("invalid_container", "Unknown SharedPreferences container", container)
            return
        }
        val prefs = context.getSharedPreferences(container, Context.MODE_PRIVATE)
        when (call.method) {
            "readAll" -> result.success(readable(prefs.all))
            "put" -> put(call, prefs, result)
            "remove" -> {
                val key = call.argument<String>("key")
                if (key == null) {
                    result.error("invalid_key", "Missing key", null)
                } else {
                    prefs.edit().remove(key).apply()
                    result.success(null)
                }
            }
            else -> result.notImplemented()
        }
    }

    /// name comes from flutter.versionName, code from flutter.versionCode
    private fun versionInfo(): Map<String, Any> {
        @Suppress("DEPRECATION")
        val info = context.packageManager.getPackageInfo(context.packageName, 0)
        val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            info.versionCode.toLong()
        }
        return mapOf(
            "name" to (info.versionName ?: ""),
            "code" to code,
        )
    }

    /// Snapshot of every container, read off the main thread so the XML parses do not stall
    /// the first frames; the reply hops back to the main looper, as the channel requires.
    private fun readAllAll(result: MethodChannel.Result) {
        val main = Handler(Looper.getMainLooper())
        Thread {
            val snapshot = HashMap<String, Map<String, Any?>>()
            for (container in CONTAINERS) {
                val prefs = context.getSharedPreferences(container, Context.MODE_PRIVATE)
                snapshot[container] = readable(prefs.all)
            }
            main.post { result.success(snapshot) }
        }.start()
    }

    private fun put(call: MethodCall, prefs: SharedPreferences, result: MethodChannel.Result) {
        val key = call.argument<String>("key")
        val type = call.argument<String>("type")
        val value = call.argument<Any>("value")
        if (key == null || type == null) {
            result.error("invalid_argument", "Missing key or type", null)
            return
        }
        val editor = prefs.edit()
        try {
            when (type) {
                "string" -> editor.putString(key, value as String)
                "bool" -> editor.putBoolean(key, value as Boolean)
                "int" -> editor.putInt(key, (value as Number).toInt())
                "long" -> editor.putLong(key, (value as Number).toLong())
                // SharedPreferences stores floats; the channel carries doubles, so cast explicitly.
                "float" -> editor.putFloat(key, (value as Number).toFloat())
                "string_set" -> editor.putStringSet(key, (value as List<*>).map { it.toString() }.toSet())
                else -> {
                    result.error("invalid_type", "Unsupported value type", type)
                    return
                }
            }
        } catch (error: ClassCastException) {
            result.error("invalid_value", "Value does not match type $type", value)
            return
        }
        editor.apply()
        result.success(null)
    }

    /// `getAll` can return `Set<String>`, which the standard codec cannot carry
    private fun readable(values: Map<String, *>): Map<String, Any?> {
        val output = HashMap<String, Any?>(values.size)
        values.forEach { (key, value) ->
            output[key] = when (value) {
                is Set<*> -> value.map { it.toString() }
                else -> value
            }
        }
        return output
    }
}
