package com.haoze.diting

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.VpnService
import androidx.core.content.ContextCompat
import com.haoze.diting.express.ExpressVpnService
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/// Dart-facing control plane for the express-mode (narrow-route) tunnel
class ExpressVpnBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, CHANNEL)

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "prepare" -> result.success(prepare())
            "start" -> result.success(start(call))
            "stop" -> {
                stop(activity)
                result.success(true)
            }
            "status" -> result.success(ExpressVpnService.status(activity))
            // Express collects no traffic stats: answer with zeros, not a MissingPluginException.
            "trafficRates" -> result.success(
                mapOf(
                    "running" to ExpressVpnService.isRunning,
                    "txBps" to 0L,
                    "rxBps" to 0L,
                    "unsupported" to true,
                )
            )
            // Null on success, otherwise the error text.
            "applyDnsConfig" -> result.success(
                RuntimeDnsConfig.applyExpress(
                    activity,
                    call.argument<String>("dnsConfig").orEmpty(),
                )
            )
            else -> result.notImplemented()
        }
    }

    private fun prepare(): Boolean {
        val intent = VpnService.prepare(activity)
        if (intent == null) return true
        activity.startActivityForResult(intent, REQUEST_PREPARE)
        return false
    }

    private fun start(call: MethodCall): Map<String, Any?> {
        val dnsConfig = call.argument<String>("dnsConfig").orEmpty()
        if (dnsConfig.isBlank()) {
            return mapOf("started" to false, "needsPermission" to false, "error" to "缺少 DNS 配置")
        }
        val intent = ExpressVpnService.startIntent(
            context = activity,
            dnsConfig = dnsConfig,
            proxyJson = call.argument<String>("outboundProxy").orEmpty(),
            // Kept out of the TUN: a proxied DNS query would otherwise re-enter the proxy.
            proxyAppPackage = call.argument<String>("proxyAppPackage").orEmpty(),
            ipv6Mode = call.argument<String>("ipv6Mode") ?: "auto",
            excludedPackages = call.argument<List<String>>("excludedPackages").orEmpty(),
            // Blocked/inspection packages are not forwarded: this TUN has no firewall or MITM.
        )
        return try {
            ContextCompat.startForegroundService(activity, intent)
            mapOf("started" to true, "needsPermission" to false, "error" to null)
        } catch (t: Throwable) {
            mapOf(
                "started" to false,
                "needsPermission" to false,
                "error" to (t.message ?: t.javaClass.simpleName),
            )
        }
    }

    private fun stop(context: Context) {
        if (ExpressVpnService.isRunning) {
            runCatching { context.startService(ExpressVpnService.stopIntent(context)) }
        } else {
            runCatching { context.stopService(Intent(context, ExpressVpnService::class.java)) }
            ExpressVpnService.setPersistedRunning(context, false)
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int): Boolean {
        if (requestCode != REQUEST_PREPARE) return false
        channel.invokeMethod("onPrepareResult", resultCode == Activity.RESULT_OK)
        return true
    }

    companion object {
        const val CHANNEL = "com.haoze.diting/express_vpn"
        const val REQUEST_PREPARE = 0x5651
    }
}
