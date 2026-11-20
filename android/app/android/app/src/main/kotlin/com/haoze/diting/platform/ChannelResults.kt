package com.haoze.diting.platform

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

object ChannelResults {
    private val handler = Handler(Looper.getMainLooper())

    fun success(result: MethodChannel.Result, value: Any?) {
        val payload = if (value is Unit) null else value
        handler.post { result.success(payload) }
    }

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
