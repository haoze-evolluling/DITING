package com.haoze.diting

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.haoze.diting.platform.ChannelResults
import com.haoze.diting.server.ServerDnsService
import com.haoze.diting.server.ServerPreference
import com.haoze.diting.server.ServerProcessState
import com.haoze.diting.server.ServerRoot
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

/**
 * 服务器模式的原生入口。
 *
 * 只负责进程内 DNS 服务的生命周期、Root 探测与启动偏好；配置、订阅、日志和
 * 统计分别由 Flutter 侧复用普通/简洁模式的偏好、规则库与日志库完成。
 */
class ServerBridge(
    private val context: Context,
    private val messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val threadId = AtomicInteger(1)
    private val io = Executors.newFixedThreadPool(2) { runnable ->
        Thread(runnable, "diting-server-bridge-${threadId.getAndIncrement()}").apply {
            isDaemon = true
        }
    }
    private val mainHandler = Handler(Looper.getMainLooper())

    fun register() {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
        EventChannel(messenger, STATUS_CHANNEL).setStreamHandler(StatusStreamHandler())
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> start(call, result)
            "stop" -> result.success(ServerDnsService.stop(context))
            "status" -> result.success(ServerDnsService.status())
            "probe_root" -> probeRoot(result)
            "launch_settings" -> result.success(launchSettings())
            "set_launch_settings" -> setLaunchSettings(call, result)
            "apply_dns_config" -> applyDnsConfig(call, result)
            "cache_dns_config" -> cacheDnsConfig(call, result)
            "reload_rules" -> result.success(ServerDnsService.reloadRules(context))
            "clear_cache" -> result.success(ServerDnsService.clearCache())
            else -> result.notImplemented()
        }
    }

    private fun start(call: MethodCall, result: MethodChannel.Result) {
        val preferRoot = call.argument<Boolean>("preferRoot") ?: false
        val dnsConfig = call.argument<String>("dnsConfig")
        result.success(ServerDnsService.start(context, preferRoot, dnsConfig))
    }

    private fun applyDnsConfig(call: MethodCall, result: MethodChannel.Result) {
        val dnsConfig = call.argument<String>("dnsConfig")
        if (dnsConfig.isNullOrBlank()) {
            result.error("invalid_config", "缺少 DNS 配置", null)
            return
        }
        result.success(ServerDnsService.applyConfig(context, dnsConfig))
    }

    /** 只缓存内核配置，供下次开机自启或进程内重启复用，不改变运行状态。 */
    private fun cacheDnsConfig(call: MethodCall, result: MethodChannel.Result) {
        val dnsConfig = call.argument<String>("dnsConfig")
        if (dnsConfig.isNullOrBlank()) {
            result.error("invalid_config", "缺少 DNS 配置", null)
            return
        }
        ServerPreference.setLastDnsConfig(context, dnsConfig)
        result.success(true)
    }

    private fun launchSettings(): Map<String, Any?> = mapOf(
        "autoStart" to ServerPreference.autoStart(context),
        "autoRestart" to ServerPreference.autoRestart(context),
    )

    private fun setLaunchSettings(call: MethodCall, result: MethodChannel.Result) {
        call.argument<Boolean>("autoStart")?.let {
            ServerPreference.setAutoStart(context, it)
        }
        call.argument<Boolean>("autoRestart")?.let {
            ServerPreference.setAutoRestart(context, it)
        }
        result.success(launchSettings())
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

    private inner class StatusStreamHandler : EventChannel.StreamHandler {
        private var listener: ((Map<String, Any?>) -> Unit)? = null

        override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
            val callback: (Map<String, Any?>) -> Unit = { snapshot ->
                mainHandler.post { runCatching { events.success(snapshot) } }
            }
            listener = callback
            ServerProcessState.addListener(callback)
            callback(ServerProcessState.snapshot())
        }

        override fun onCancel(arguments: Any?) {
            listener?.let { ServerProcessState.removeListener(it) }
            listener = null
        }
    }

    companion object {
        const val CHANNEL = "com.haoze.diting/server"
        const val STATUS_CHANNEL = "com.haoze.diting/server_status"
    }
}
