package com.haoze.diting.root

import android.content.Context
import com.haoze.diting.R
import com.haoze.diting.platform.ChannelResults
import com.haoze.diting.server.ServerRoot
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class RootDnsBridge(
    private val context: Context,
    private val messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val io = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "diting-root-dns-bridge").apply { isDaemon = true }
    }

    fun register() {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> start(call, result)
            "stop" -> result.success(RootDnsService.stop(context))
            "status" -> result.success(RootDnsService.status(context))
            "trafficRates" -> result.success(RootDnsTraffic.snapshot(RootDnsRuntime.running))
            "applyDnsConfig" -> {
                val config = call.argument<String>("dnsConfig").orEmpty()
                result.success(RootDnsService.applyDnsConfig(context, config))
            }
            "reloadRules" -> {
                RootDnsService.requestReload(context)
                result.success(true)
            }
            "probeRoot" -> probeRoot(result)
            else -> result.notImplemented()
        }
    }

    private fun start(call: MethodCall, result: MethodChannel.Result) {
        val config = call.argument<String>("dnsConfig").orEmpty()
        if (config.isBlank()) {
            result.success(startResult(false, context.getString(R.string.root_dns_missing_config)))
            return
        }
        io.execute {
            val probe = ServerRoot.probe()
            if (!probe.available) {
                val message = probe.message.ifBlank {
                    context.getString(R.string.root_dns_no_root)
                }
                ChannelResults.success(result, startResult(false, message))
                return@execute
            }
            val started = RootDnsService.start(context, config)
            ChannelResults.success(result, startResult(started, null))
        }
    }

    private fun probeRoot(result: MethodChannel.Result) {
        io.execute {
            val probe = ServerRoot.probe()
            ChannelResults.success(
                result,
                mapOf(
                    "available" to probe.available,
                    "uid" to probe.uid,
                    "message" to probe.message,
                ),
            )
        }
    }

    private fun startResult(started: Boolean, error: String?): Map<String, Any?> =
        mapOf("started" to started, "needsPermission" to false, "error" to error)

    companion object {
        const val CHANNEL = "com.haoze.diting/root_dns"
    }
}
