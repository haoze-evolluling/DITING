package com.haoze.diting.platform

import android.content.Context
import com.haoze.diting.express.ExpressVpnService
import com.haoze.diting.normal.DitingVpnService
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class NotificationBridge(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.haoze.diting/notification"
    }

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "refresh" -> result.success(refresh())
            else -> result.notImplemented()
        }
    }

    private fun refresh(): Boolean {
        var refreshed = false
        if (DitingVpnService.isRunning) {
            refreshed = DitingVpnService.refreshNotification(context) || refreshed
        }
        if (ExpressVpnService.isRunning) {
            refreshed = ExpressVpnService.refreshNotification(context) || refreshed
        }
        return refreshed
    }
}
