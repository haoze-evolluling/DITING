package com.haoze.diting.net

import android.content.Context
import com.haoze.diting.platform.ChannelResults
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class DiagnosticsBridge(private val context: Context) :
    MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.haoze.diting/diagnostics"

        private val workers = Executors.newCachedThreadPool { runnable ->
            Thread(runnable, "diting-diagnostics").apply { isDaemon = true }
        }
    }

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
    }

    private fun runProbe(
        result: MethodChannel.Result,
        errorCode: String,
        probe: () -> Any?,
    ) {
        workers.execute {
            ChannelResults.ship(result, runCatching(probe), errorCode)
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "ping" -> {
                val target = call.argument<String>("target").orEmpty()
                val count = call.argument<Int>("count") ?: PingProbe.DEFAULT_COUNT
                val timeout = call.argument<Int>("timeoutSeconds")
                    ?: PingProbe.DEFAULT_TIMEOUT_SECONDS
                runProbe(result, "ping_failed") { PingProbe.ping(target, count, timeout) }
            }
            "traceRoute" -> {
                val target = call.argument<String>("target").orEmpty()
                val maxHops = call.argument<Int>("maxHops") ?: TraceProbe.DEFAULT_MAX_HOPS
                runProbe(result, "traceroute_failed") { TraceProbe.trace(target, maxHops) }
            }
            "lookupDns" -> {
                val domain = call.argument<String>("domain").orEmpty()
                val viaTunnel = call.argument<Boolean>("viaTunnel") ?: false
                val ipv4 = call.argument<Boolean>("ipv4") ?: true
                val server = call.argument<String>("server").orEmpty().trim()
                runProbe(result, "lookup_failed") {
                    if (!viaTunnel && server.isNotEmpty()) {
                        DnsLookupProbe.customServerLookup(domain, server, ipv4)
                    } else {
                        DnsLookupProbe.lookup(context, domain, viaTunnel, ipv4)
                    }
                }
            }
            "networkInfo" -> runProbe(result, "network_info_failed") {
                NetInfoProbe.snapshot(context)
            }
            else -> result.notImplemented()
        }
    }
}
