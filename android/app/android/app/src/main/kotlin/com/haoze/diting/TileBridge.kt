package com.haoze.diting

import android.app.Activity
import android.content.Intent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class TileBridge(private val activity: Activity) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.haoze.diting/tile"
    }

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "consumeStartRequest" -> result.success(consumeStartRequest())
            else -> result.notImplemented()
        }
    }

    private fun consumeStartRequest(): Boolean {
        val intent: Intent = activity.intent ?: return false
        if (!intent.getBooleanExtra(MainActivity.EXTRA_AUTO_START_VPN, false)) return false
        intent.removeExtra(MainActivity.EXTRA_AUTO_START_VPN)
        return true
    }
}
