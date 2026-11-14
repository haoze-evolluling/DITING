package com.haoze.diting

import android.content.Context
import com.haoze.diting.net.NetworkContextProbe
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/// N1 网络档案的当前网络上下文通道：`com.haoze.diting/network_profile`。
///
/// 只暴露 `context`；档案求值在 `diting-netprofile-core`，不在这里重复判定逻辑。
class NetworkProfileBridge(
    private val context: Context,
    messenger: BinaryMessenger,
) {
    private val channel = MethodChannel(messenger, CHANNEL)

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "context" -> result.success(NetworkContextProbe.snapshot(context))
                else -> result.notImplemented()
            }
        }
    }

    companion object {
        private const val CHANNEL = "com.haoze.diting/network_profile"
    }
}
