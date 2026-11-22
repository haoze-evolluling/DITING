package com.haoze.diting.server

import android.content.Context
import android.net.LocalSocket
import android.net.LocalSocketAddress
import org.json.JSONObject

object ServerControlSocket {
    fun request(
        context: Context,
        method: String,
        params: JSONObject,
        id: Long = 1,
        timeoutMs: Int = 5_000,
    ): String {
        val payload = JSONObject()
            .put("id", id)
            .put("method", method)
            .put("params", params)
            .toString()
        return transact(context, payload, timeoutMs)
    }

    fun transact(context: Context, payload: String, timeoutMs: Int = 5_000): String {
        val path = ServerPaths.socketFile(context).absolutePath
        LocalSocket().use { socket ->
            socket.connect(LocalSocketAddress(path, LocalSocketAddress.Namespace.FILESYSTEM))
            socket.soTimeout = timeoutMs
            val writer = socket.outputStream.bufferedWriter(Charsets.UTF_8)
            writer.write(payload.trim())
            writer.newLine()
            writer.flush()
            return socket.inputStream.bufferedReader(Charsets.UTF_8).readLine()
                ?: throw IllegalStateException("控制套接字未返回响应")
        }
    }
}
