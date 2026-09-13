package com.haoze.dnssr.vpn

import java.net.InetAddress
import java.util.Locale

data class BootstrapIpEntry(
    val id: String,
    val name: String,
    val ip: String,
    val isPreset: Boolean,
    val enabled: Boolean = true
)

object BootstrapIpDefaults {
    val PRESETS = listOf(
        BootstrapIpEntry("preset_alidns", "阿里云", "223.5.5.5", isPreset = true),
        BootstrapIpEntry("preset_dnspod", "腾讯云", "119.29.29.29", isPreset = true),
        BootstrapIpEntry("preset_volcengine", "字节跳动", "180.184.1.1", isPreset = true),
        BootstrapIpEntry("preset_cnnic", "CNNIC DNS", "1.2.4.8", isPreset = true),
        BootstrapIpEntry("preset_114dns", "114DNS", "114.114.114.114", isPreset = true),
        BootstrapIpEntry("preset_cloudflare", "Cloudflare", "1.1.1.1", isPreset = true),
        BootstrapIpEntry("preset_google", "Google", "8.8.8.8", isPreset = true)
    )
}

object BootstrapIpValidator {
    fun isValidIp(ip: String?): Boolean {
        if (ip.isNullOrBlank()) return false
        val trimmed = ip.trim()
        if (!isIpLiteral(trimmed)) return false
        return try {
            InetAddress.getByName(trimmed) != null
        } catch (_: Exception) {
            false
        }
    }

    private fun isIpLiteral(value: String): Boolean {
        val trimmed = value.trim()
        val ipv4 = Regex("""^(\d{1,3}\.){3}\d{1,3}$""")
        if (ipv4.matches(trimmed)) {
            return trimmed.split(".").all { part -> part.toIntOrNull() in 0..255 }
        }
        if (trimmed.contains(":")) {
            val normalized = trimmed.lowercase(Locale.US)
            return normalized.all { it.isDigit() || it in 'a'..'f' || it == ':' || it == '.' || it == '%' }
        }
        return false
    }
}
