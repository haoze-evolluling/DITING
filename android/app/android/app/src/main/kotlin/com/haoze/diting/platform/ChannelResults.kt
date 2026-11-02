package com.haoze.diting.platform

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

/// Marshals worker results to the platform thread: `MethodChannel.Result` is only legal there.
object ChannelResults {
    private val handler = Handler(Looper.getMainLooper())

    /// `Unit` becomes `null`: the codec cannot encode `kotlin.Unit`, so `Future<void>` would hang.
    fun success(result: MethodChannel.Result, value: Any?) {
        val payload = if (value is Unit) null else value
        handler.post { result.success(payload) }
    }

    /// Reports `error` as a channel error. A Result never settled hangs the Dart future forever
    fun error(result: MethodChannel.Result, code: String, error: Throwable) {
        val message = error.message ?: error.javaClass.simpleName
        handler.post { result.error(code, message, null) }
    }

    fun <T> ship(result: MethodChannel.Result, value: Result<T>, code: String) {
        value.fold(
            onSuccess = { success(result, it) },
            onFailure = { error(result, code, it) },
        )
    }
}
