package com.haoze.dnssr.ui

import android.content.Context
import org.json.JSONObject

enum class OutboundProxyProtocol(val storageValue: String, val displayName: String) {
    SOCKS5("socks5", "SOCKS5"),
    HTTP("http", "HTTP CONNECT");

    companion object {
        fun fromStorageValue(value: String?): OutboundProxyProtocol =
            entries.firstOrNull { it.storageValue == value } ?: SOCKS5
    }
}

data class OutboundProxyConfig(
    val enabled: Boolean = false,
    val protocol: OutboundProxyProtocol = OutboundProxyProtocol.SOCKS5,
    val host: String = "127.0.0.1",
    val port: Int = 7890,
    val username: String = "",
    val password: String = "",
    val proxyAppPackage: String = ""
) {
    fun validationError(context: Context): String? {
        if (host != "127.0.0.1" && host != "::1") return "代理地址仅支持 127.0.0.1 或 ::1"
        if (port !in 1..65535) return "代理端口必须在 1 到 65535 之间"
        if (proxyAppPackage.isBlank()) return "请选择提供本地代理端口的应用"
        if (proxyAppPackage == context.packageName) return "不能选择 DNSSR 自身作为代理应用"
        if (runCatching { context.packageManager.getApplicationInfo(proxyAppPackage, 0) }.isFailure) return "所选代理应用未安装"
        if (username.toByteArray().size > 255 || password.toByteArray().size > 255) return "代理账号或密码过长"
        return null
    }

    fun toNativeJson(): String = JSONObject()
        .put("enabled", enabled)
        .put("protocol", protocol.storageValue)
        .put("host", host)
        .put("port", port)
        .put("username", username)
        .put("password", password)
        .toString()
}
