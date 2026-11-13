package com.haoze.diting.deeplink

import android.app.Activity
import android.content.Intent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/// Native half of `com.haoze.diting/deeplink`: hands Dart the `diting://install-config?url=...`
/// link that opened the app.
///
/// A cold start carries the link on `Activity.intent`, which Dart pulls once with
/// `consumeInitialLink`; a warm start arrives through `onNewIntent` and is pushed as `onLink`. The
/// two paths never overlap, so one link is imported exactly once.
class DeepLinkBridge(private val activity: Activity) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.haoze.diting/deeplink"
        private const val SCHEME = "diting"
    }

    private var channel: MethodChannel? = null

    /// Read during engine configuration, which runs after `onCreate` set the launch intent.
    private var initialLink: String? = extractLink(activity.intent)

    fun register(messenger: BinaryMessenger) {
        val methodChannel = MethodChannel(messenger, CHANNEL)
        methodChannel.setMethodCallHandler(this)
        channel = methodChannel
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "consumeInitialLink" -> {
                val link = initialLink
                initialLink = null
                result.success(link)
            }
            else -> result.notImplemented()
        }
    }

    /// Called from `MainActivity.onNewIntent`; a non-deep-link intent is ignored.
    fun handleNewIntent(intent: Intent) {
        val link = extractLink(intent) ?: return
        channel?.invokeMethod("onLink", link)
    }

    private fun extractLink(intent: Intent?): String? {
        if (intent?.action != Intent.ACTION_VIEW) return null
        val data = intent.data ?: return null
        if (!data.scheme.equals(SCHEME, ignoreCase = true)) return null
        return data.toString()
    }
}
