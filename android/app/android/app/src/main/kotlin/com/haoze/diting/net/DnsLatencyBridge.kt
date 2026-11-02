package com.haoze.diting.net

import android.content.Context
import com.haoze.diting.platform.ChannelResults
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/// Native side of `com.haoze.diting/dns_latency`. Dart owns the provider catalog and
/// passes host/port/protocol down. Probes block for seconds, so they run on a worker
/// pool and every answer is posted back to the platform thread.
class DnsLatencyBridge(private val context: Context) :
    MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.haoze.diting/dns_latency"

        /// Daemon threads so a hung probe never keeps the process alive
        private val workers = Executors.newCachedThreadPool { runnable ->
            Thread(runnable, "diting-dns-latency").apply { isDaemon = true }
        }
    }

    @Suppress("unused")
    private val appContext: Context = context.applicationContext

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "probe" -> probe(call, result)
            else -> result.notImplemented()
        }
    }

    private fun probe(call: MethodCall, result: MethodChannel.Result) {
        val rawProviders = call.argument<List<Map<String, Any?>>>("providers")
        if (rawProviders.isNullOrEmpty()) {
            result.error("invalid_args", "providers 不能为空", null)
            return
        }
        val domain = call.argument<String>("domain").orEmpty().ifBlank { "www.google.com" }
        val attempts = call.argument<Int>("attempts") ?: 3
        val specs = rawProviders.mapNotNull { toSpec(it) }
        if (specs.isEmpty()) {
            result.error("invalid_args", "providers 里没有合法条目", null)
            return
        }
        workers.execute {
            // Each probe is isolated: one failing provider must not abort the run.
            val samples = specs.map { spec ->
                runCatching { DnsLatencyTester.probeAverage(spec, domain, attempts) }
                    .getOrElse { error ->
                        DnsLatencyTester.Sample(
                            providerId = spec.id,
                            providerName = spec.name,
                            protocol = spec.protocol,
                            elapsedMs = 0L,
                            success = false,
                            message = error.message ?: error.javaClass.simpleName,
                            attempts = attempts.coerceAtLeast(1),
                            successCount = 0,
                            elapsedSamplesMs = emptyList(),
                        )
                    }
            }
            ChannelResults.success(result, samples.map { it.toMap() })
        }
    }

    private fun toSpec(map: Map<String, Any?>): DnsLatencyTester.Spec? {
        val id = (map["id"] as? String)?.takeIf { it.isNotBlank() } ?: return null
        val url = (map["url"] as? String).orEmpty()
        // DoH may carry only a url; plain DNS and DoT need a host to open a socket.
        val host = (map["host"] as? String).orEmpty()
        if (host.isBlank() && url.isBlank()) return null
        return DnsLatencyTester.Spec(
            id = id,
            name = (map["name"] as? String)?.takeIf { it.isNotBlank() } ?: id,
            host = host,
            port = (map["port"] as? Number)?.toInt() ?: 0,
            protocol = DnsLatencyTester.Protocol.fromWire(map["protocol"] as? String),
            url = url,
        )
    }
}
