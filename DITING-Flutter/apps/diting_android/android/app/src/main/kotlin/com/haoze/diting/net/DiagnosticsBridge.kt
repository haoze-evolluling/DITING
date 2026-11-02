package com.haoze.diting.net

import android.content.Context
import com.haoze.diting.platform.ChannelResults
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/// Native side of `com.haoze.diting/diagnostics`; probes run on a worker pool.
class DiagnosticsBridge(private val context: Context) :
    MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.haoze.diting/diagnostics"

        /// Unbounded pool; the UI disables the run button, so four panels bound it in practice
        private val workers = Executors.newCachedThreadPool { runnable ->
            Thread(runnable, "diting-diagnostics").apply { isDaemon = true }
        }
    }

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "ping" -> {
                val target = call.argument<String>("target").orEmpty()
                val count = call.argument<Int>("count") ?: PingProbe.DEFAULT_COUNT
                val timeout = call.argument<Int>("timeoutSeconds")
                    ?: PingProbe.DEFAULT_TIMEOUT_SECONDS
                workers.execute {
                    val value = runCatching { PingProbe.ping(target, count, timeout) }
                    ChannelResults.ship(result, value, "ping_failed")
                }
            }
            "traceRoute" -> {
                val target = call.argument<String>("target").orEmpty()
                val maxHops = call.argument<Int>("maxHops") ?: TraceProbe.DEFAULT_MAX_HOPS
                workers.execute {
                    val value = runCatching { TraceProbe.trace(target, maxHops) }
                    ChannelResults.ship(result, value, "traceroute_failed")
                }
            }
            "lookupDns" -> {
                val domain = call.argument<String>("domain").orEmpty()
                val viaTunnel = call.argument<Boolean>("viaTunnel") ?: false
                val ipv4 = call.argument<Boolean>("ipv4") ?: true
                // Empty = system resolver, non-empty = custom server: one argument serves both.
                val server = call.argument<String>("server").orEmpty().trim()
                workers.execute {
                    // A bad domain never throws: failures come back as source=error.
                    val value = runCatching {
                        if (!viaTunnel && server.isNotEmpty()) {
                            DnsLookupProbe.customServerLookup(domain, server, ipv4)
                        } else {
                            DnsLookupProbe.lookup(domain, viaTunnel, ipv4)
                        }
                    }
                    ChannelResults.ship(result, value, "lookup_failed")
                }
            }
            // One synchronous ConnectivityManager read; no pool hop needed.
            "networkInfo" -> {
                val value = runCatching { NetInfoProbe.snapshot(context) }
                ChannelResults.ship(result, value, "network_info_failed")
            }
            else -> result.notImplemented()
        }
    }
}
