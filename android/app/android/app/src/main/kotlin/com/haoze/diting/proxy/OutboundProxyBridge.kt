package com.haoze.diting.proxy

import android.content.Context
import com.haoze.diting.platform.ChannelResults
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class OutboundProxyBridge(private val context: Context) :
    MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.haoze.diting/outbound_proxy"

        private const val PREFS_NAME = "dns_vpn_prefs"

        private const val KEY_ENABLED = "outbound_proxy_enabled"
        private const val KEY_PROTOCOL = "outbound_proxy_protocol"
        private const val KEY_HOST = "outbound_proxy_host"
        private const val KEY_PORT = "outbound_proxy_port"
        private const val KEY_USERNAME = "outbound_proxy_username"
        private const val KEY_PASSWORD = "outbound_proxy_password"
        private const val KEY_APP = "outbound_proxy_app"
        private const val KEY_SCOPE = "outbound_proxy_scope"
        private const val KEY_TARGET_APPS = "outbound_proxy_target_apps"
        private const val KEY_STATUS = "outbound_proxy_status"
        private const val KEY_STATUS_MESSAGE = "outbound_proxy_status_message"

        private const val DEFAULT_HOST = "127.0.0.1"
        private const val DEFAULT_PORT = 7890
        private const val DEFAULT_STATUS = "disabled"

        private val worker = Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "diting-outbound-proxy").apply { isDaemon = true }
        }

        fun publishStatus(context: Context, state: String, message: String) {
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putString(KEY_STATUS, state.ifEmpty { DEFAULT_STATUS })
                .putString(KEY_STATUS_MESSAGE, message)
                .apply()
        }
    }

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "read" -> worker.execute { runCatching { read() }.ship(result) }
            "write" -> worker.execute { runCatching { write(call) }.ship(result) }
            "reset" -> worker.execute { runCatching { reset() }.ship(result) }
            "setStatus" -> {
                val state = call.argument<String>("state") ?: DEFAULT_STATUS
                val message = call.argument<String>("message").orEmpty()
                worker.execute { runCatching { publishStatus(context, state, message) }.ship(result) }
            }
            else -> result.notImplemented()
        }
    }

    private fun read(): Map<String, Any?> {
        val preferences = prefs()
        val status = preferences.getString(KEY_STATUS, DEFAULT_STATUS)
            ?.takeIf { it.isNotEmpty() } ?: DEFAULT_STATUS
        return mapOf(
            "enabled" to preferences.getBoolean(KEY_ENABLED, false),
            "protocol" to OutboundProxyNative.protocolOf(
                preferences.getString(KEY_PROTOCOL, null),
            ),
            "host" to (preferences.getString(KEY_HOST, DEFAULT_HOST) ?: DEFAULT_HOST),
            "port" to preferences.getInt(KEY_PORT, DEFAULT_PORT),
            "username" to ProxySecretCodec.decrypt(
                preferences.getString(KEY_USERNAME, null),
            ),
            "password" to ProxySecretCodec.decrypt(
                preferences.getString(KEY_PASSWORD, null),
            ),
            "proxyAppPackage" to preferences.getString(KEY_APP, "").orEmpty(),
            "scope" to OutboundProxyNative.scopeOf(preferences.getString(KEY_SCOPE, null)),
            "targetPackages" to preferences.getStringSet(KEY_TARGET_APPS, null).orEmpty().toList(),
            "status" to status,
            "statusMessage" to (preferences.getString(KEY_STATUS_MESSAGE, "") ?: ""),
        )
    }

    private fun write(call: MethodCall) {
        prefs().edit()
            .putBoolean(KEY_ENABLED, call.argument<Boolean>("enabled") ?: false)
            .putString(KEY_PROTOCOL, OutboundProxyNative.protocolOf(call.argument<String>("protocol")))
            .putString(KEY_HOST, call.argument<String>("host") ?: DEFAULT_HOST)
            .putInt(KEY_PORT, call.argument<Int>("port") ?: DEFAULT_PORT)
            .putString(
                KEY_USERNAME,
                ProxySecretCodec.encrypt(call.argument<String>("username") ?: ""),
            )
            .putString(
                KEY_PASSWORD,
                ProxySecretCodec.encrypt(call.argument<String>("password") ?: ""),
            )
            .putString(KEY_APP, call.argument<String>("proxyAppPackage") ?: "")
            .putString(KEY_SCOPE, OutboundProxyNative.scopeOf(call.argument<String>("scope")))
            .putStringSet(
                KEY_TARGET_APPS,
                OutboundProxyNative.targetsOf(
                    call.argument<List<*>>("targetPackages").orEmpty()
                        .filterIsInstance<String>(),
                ).toSet(),
            )
            .apply()
    }

    private fun reset() {
        prefs().edit()
            .remove(KEY_ENABLED)
            .remove(KEY_PROTOCOL)
            .remove(KEY_HOST)
            .remove(KEY_PORT)
            .remove(KEY_USERNAME)
            .remove(KEY_PASSWORD)
            .remove(KEY_APP)
            .remove(KEY_SCOPE)
            .remove(KEY_TARGET_APPS)
            .remove(KEY_STATUS)
            .remove(KEY_STATUS_MESSAGE)
            .apply()
    }

    private fun prefs() = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private fun <T> Result<T>.ship(result: MethodChannel.Result) =
        ChannelResults.ship(result, this, "outbound_proxy_unavailable")
}
