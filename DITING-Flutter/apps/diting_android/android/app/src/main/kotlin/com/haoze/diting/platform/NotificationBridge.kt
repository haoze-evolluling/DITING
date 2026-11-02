package com.haoze.diting.platform

import android.content.Context
import com.haoze.diting.express.ExpressVpnService
import com.haoze.diting.normal.DitingVpnService
import com.haoze.diting.server.DitingDnsServerService
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/// Repaints the running foreground notification after Dart edits a setting its body is composed
/// from. Its own channel keeps `PlatformBridge` (activity-bound, crash logs) untouched.
class NotificationBridge(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.haoze.diting/notification"
    }

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            // False means no service is running; the next start reads the change anyway.
            "refresh" -> result.success(refresh())
            else -> result.notImplemented()
        }
    }

    /// The three data planes are mutually exclusive, but each guard keeps this call idempotent.
    private fun refresh(): Boolean {
        var refreshed = false
        if (DitingVpnService.isRunning) {
            refreshed = DitingVpnService.refreshNotification(context) || refreshed
        }
        if (ExpressVpnService.isRunning) {
            refreshed = ExpressVpnService.refreshNotification(context) || refreshed
        }
        if (DitingDnsServerService.isRunning) {
            refreshed = DitingDnsServerService.refreshNotification(context) || refreshed
        }
        return refreshed
    }
}
