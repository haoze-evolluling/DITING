package com.haoze.diting.proxy

import android.content.Context
import com.haoze.diting.platform.ChannelResults
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/// Native side of `com.haoze.diting/outbound_proxy`; key names stay verbatim from the legacy store.
class OutboundProxyBridge(private val context: Context) :
    MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.haoze.diting/outbound_proxy"

        /// Same container the legacy app used
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
        private const val DEFAULT_PROTOCOL = "socks5"
        private const val DEFAULT_STATUS = "disabled"
        private const val DEFAULT_SCOPE = "all"

        /// Keystore unwrap costs tens of ms and `read` runs per page build, so it runs off-thread.
        private val worker = Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "diting-outbound-proxy").apply { isDaemon = true }
        }

        /// Called by the VPN services from the engine's status callback. The service shares this
        /// process with the UI, so a plain `apply()` is visible to the next `read`.
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
            "write" -> {
                val config = configFrom(call)
                worker.execute { runCatching { write(config) }.ship(result) }
            }
            "reset" -> worker.execute { runCatching { reset() }.ship(result) }
            "setStatus" -> {
                val state = call.argument<String>("state") ?: DEFAULT_STATUS
                val message = call.argument<String>("message").orEmpty()
                worker.execute { runCatching { setStatus(state, message) }.ship(result) }
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
            "protocol" to protocolOf(preferences.getString(KEY_PROTOCOL, null)),
            "host" to (preferences.getString(KEY_HOST, DEFAULT_HOST) ?: DEFAULT_HOST),
            "port" to preferences.getInt(KEY_PORT, DEFAULT_PORT),
            // Decryption failure yields "": the page asks again, as the old password is gone.
            
            "username" to ProxySecretCodec.decrypt(
                preferences.getString(KEY_USERNAME, null),
            ),
            "password" to ProxySecretCodec.decrypt(
                preferences.getString(KEY_PASSWORD, null),
            ),
            "proxyAppPackage" to preferences.getString(KEY_APP, "").orEmpty(),
            "scope" to scopeOf(preferences.getString(KEY_SCOPE, null)),
            "targetPackages" to preferences.getStringSet(KEY_TARGET_APPS, null).orEmpty().toList(),
            "status" to status,
            "statusMessage" to (preferences.getString(KEY_STATUS_MESSAGE, "") ?: ""),
        )
    }

    /// Leaves the two `status` keys alone, so a write never blanks the last error.
    
    private fun write(config: Map<String, Any?>) {
        prefs().edit()
            .putBoolean(KEY_ENABLED, config["enabled"] == true)
            .putString(KEY_PROTOCOL, protocolOf(config["protocol"] as? String))
            .putString(KEY_HOST, config["host"] as? String ?: DEFAULT_HOST)
            .putInt(KEY_PORT, (config["port"] as? Number)?.toInt() ?: DEFAULT_PORT)
            .putString(
                KEY_USERNAME,
                ProxySecretCodec.encrypt(config["username"] as? String ?: ""),
            )
            .putString(
                KEY_PASSWORD,
                ProxySecretCodec.encrypt(config["password"] as? String ?: ""),
            )
            .putString(KEY_APP, config["proxyAppPackage"] as? String ?: "")
            .putString(KEY_SCOPE, scopeOf(config["scope"] as? String))
            .putStringSet(
                KEY_TARGET_APPS,
                (config["targetPackages"] as? List<*>).orEmpty()
                    .filterIsInstance<String>().filter { it.isNotBlank() }.toSet(),
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

    private fun setStatus(state: String, message: String) =
        publishStatus(context, state, message)

    private fun configFrom(call: MethodCall): Map<String, Any?> = mapOf(
        "enabled" to (call.argument<Boolean>("enabled") ?: false),
        "protocol" to call.argument<String>("protocol"),
        "host" to call.argument<String>("host"),
        "port" to call.argument<Int>("port"),
        "username" to call.argument<String>("username"),
        "password" to call.argument<String>("password"),
        "proxyAppPackage" to call.argument<String>("proxyAppPackage"),
        "scope" to call.argument<String>("scope"),
        "targetPackages" to call.argument<List<String>>("targetPackages"),
    )

    /// Unknown values fall back to `socks5`, never persisted as garbage Go cannot parse
    private fun protocolOf(value: String?): String = when (value) {
        "http" -> "http"
        "socks5" -> "socks5"
        else -> DEFAULT_PROTOCOL
    }

    /// `apps` proxies only the selected packages; anything else keeps the legacy whole-device scope.
    private fun scopeOf(value: String?): String = if (value == "apps") "apps" else DEFAULT_SCOPE

    private fun prefs() = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private fun <T> Result<T>.ship(result: MethodChannel.Result) =
        ChannelResults.ship(result, this, "outbound_proxy_unavailable")
}
