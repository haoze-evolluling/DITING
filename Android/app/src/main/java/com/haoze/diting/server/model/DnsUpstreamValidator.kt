package com.haoze.diting.server.model

import java.net.URL

/**
 * Pure input validation for user-defined upstream servers. Error strings are
 * Chinese dict keys resolved through localizedText at the UI layer. Kept free
 * of Android dependencies so unit tests can exercise it directly.
 */
object DnsUpstreamValidator {

    private val hostnameRegex = Regex(
        "^(?=.{1,253}\$)([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*\\.?)\$"
    )
    private val ipv4Regex = Regex("^(\\d{1,3})(\\.\\d{1,3}){3}\$")
    private val ipv6CharsRegex = Regex("^[0-9a-fA-F:.]+\$")

    /** Returns null when acceptable, otherwise the error message key. */
    fun validateName(name: String): String? =
        if (name.trim().isEmpty()) "名称不能为空" else null

    fun validateAddress(protocol: DnsModeProtocol, address: String): String? {
        val trimmed = address.trim()
        if (trimmed.isEmpty()) return "解析地址不能为空"
        if (trimmed.contains(Regex("\\s")) || trimmed.contains('/') && protocol != DnsModeProtocol.DOH) {
            return "地址格式不正确"
        }
        return when (protocol) {
            DnsModeProtocol.DOH -> validateDohUrl(trimmed)
            DnsModeProtocol.DNS, DnsModeProtocol.DOT -> validateHost(trimmed)
        }
    }

    fun validatePort(portText: String, protocol: DnsModeProtocol): String? {
        if (protocol == DnsModeProtocol.DOH) return null
        val port = portText.trim().ifBlank { protocol.defaultPort.toString() }.toIntOrNull()
            ?: return "端口必须为数字"
        if (port !in 1..65535) return "端口必须在 1-65535 之间"
        return null
    }

    /** Parses port text to an Int, applying the protocol default when blank. */
    fun parsePort(portText: String, protocol: DnsModeProtocol): Int =
        portText.trim().ifBlank { protocol.defaultPort.toString() }.toIntOrNull()
            ?: protocol.defaultPort

    private fun validateDohUrl(url: String): String? {
        return try {
            val parsed = URL(url)
            if (parsed.protocol.equals("https", ignoreCase = true) && parsed.host.isNotBlank()) {
                null
            } else {
                "DoH 地址必须以 https:// 开头"
            }
        } catch (_: Exception) {
            "DoH 地址格式不正确"
        }
    }

    private fun validateHost(host: String): String? {
        val isValid = when {
            ipv4Regex.matches(host) -> host.split('.').all { it.toInt() in 0..255 }
            host.contains(':') -> ipv6CharsRegex.matches(host)
            else -> hostnameRegex.matches(host)
        }
        return if (isValid) null else "地址格式不正确"
    }
}
