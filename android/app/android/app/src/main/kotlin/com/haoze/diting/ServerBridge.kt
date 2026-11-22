package com.haoze.diting

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.haoze.diting.platform.ChannelResults
import com.haoze.diting.server.ServerControlSocket
import com.haoze.diting.server.ServerDnsService
import com.haoze.diting.server.ServerPaths
import com.haoze.diting.server.ServerPreference
import com.haoze.diting.server.ServerProcessState
import com.haoze.diting.server.ServerRoot
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger
import org.json.JSONObject

class ServerBridge(
    private val context: Context,
    private val messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val threadId = AtomicInteger(1)
    private val io = Executors.newFixedThreadPool(4) { runnable ->
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
            "read_config" -> readConfig(result)
            "write_config" -> writeConfig(call, result)
            "request" -> request(call, result)
            else -> result.notImplemented()
        }
    }

    private fun start(call: MethodCall, result: MethodChannel.Result) {
        val preferRoot = call.argument<Boolean>("preferRoot") ?: true
        result.success(ServerDnsService.start(context, preferRoot))
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

    private fun readConfig(result: MethodChannel.Result) {
        io.execute {
            runCatching {
                val file = ServerPaths.configFile(context)
                if (file.isFile) file.readText() else null
            }.fold(
                onSuccess = { ChannelResults.success(result, it) },
                onFailure = { ChannelResults.error(result, "config_read_failed", it) },
            )
        }
    }

    private fun writeConfig(call: MethodCall, result: MethodChannel.Result) {
        if (ServerProcessState.active) {
            result.error("server_running", "服务运行时请通过控制协议保存配置", null)
            return
        }
        val json = call.argument<String>("config")
        if (json.isNullOrBlank()) {
            result.error("invalid_config", "缺少配置内容", null)
            return
        }
        io.execute {
            runCatching {
                val parsed = JSONObject(json)
                val root = parsed.optJSONObject("listen")?.optBoolean("root") ?: false
                val file = ServerPaths.configFile(context)
                file.parentFile?.mkdirs()
                val temporary = File(file.parentFile, "config.json.tmp")
                temporary.writeText(json)
                if (file.exists() && !file.delete()) {
                    error("无法替换旧配置")
                }
                if (!temporary.renameTo(file)) {
                    error("无法提交配置")
                }
                ServerPreference.setPreferRoot(context, root)
            }.fold(
                onSuccess = { ChannelResults.success(result, true) },
                onFailure = { ChannelResults.error(result, "config_write_failed", it) },
            )
        }
    }

    private fun request(call: MethodCall, result: MethodChannel.Result) {
        val payload = call.argument<String>("request")
        if (payload.isNullOrBlank()) {
            result.error("invalid_request", "缺少控制请求", null)
            return
        }
        io.execute {
            runCatching { ServerControlSocket.transact(context, payload) }.fold(
                onSuccess = { ChannelResults.success(result, it) },
                onFailure = { ChannelResults.error(result, "control_failed", it) },
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
