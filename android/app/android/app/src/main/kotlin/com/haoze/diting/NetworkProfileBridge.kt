package com.haoze.diting

import android.content.Context
import com.haoze.diting.net.NetworkContextProbe
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

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
