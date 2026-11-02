package com.haoze.diting

import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat
import com.haoze.diting.server.DitingDnsServerService
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/// Dart-facing control plane for the standalone LAN DNS server
class DnsServerBridge(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, CHANNEL)

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> result.success(start(call))
            "stop" -> {
                stop(context)
                result.success(true)
            }
            "status" -> result.success(DitingDnsServerService.status(context))
            "clearCache" -> result.success(clearCache())
            else -> result.notImplemented()
        }
    }

    /// Clears the running engine's DNS cache; false when no engine is running
    private fun clearCache(): Boolean {
        val engine = DitingDnsServerService.engineForDiagnostics() ?: return false
        return runCatching {
            engine.clearDNSCache()
            true
        }.getOrDefault(false)
    }

    private fun start(call: MethodCall): Map<String, Any?> {
        val dnsConfig = call.argument<String>("dnsConfig").orEmpty()
        val port = call.argument<Int>("port") ?: 1053
        if (dnsConfig.isBlank()) {
            return mapOf("started" to false, "error" to "缺少 DNS 配置")
        }
        val intent = DitingDnsServerService.startIntent(
            context = context,
            port = port,
            dnsConfig = dnsConfig,
            adBlockEnabled = call.argument<Boolean>("adBlockEnabled") ?: false,
        )
        return try {
            ContextCompat.startForegroundService(context, intent)
            mapOf("started" to true, "error" to null)
        } catch (t: Throwable) {
            mapOf("started" to false, "error" to (t.message ?: t.javaClass.simpleName))
        }
    }

    private fun stop(context: Context) {
        if (DitingDnsServerService.isRunning) {
            runCatching { context.startService(DitingDnsServerService.stopIntent(context)) }
        } else {
            runCatching { context.stopService(Intent(context, DitingDnsServerService::class.java)) }
            DitingDnsServerService.setServiceActive(context, false)
        }
    }

    companion object {
        const val CHANNEL = "com.haoze.diting/dns_server"
    }
}
