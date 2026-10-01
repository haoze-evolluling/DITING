package com.haoze.diting.dnsmode.model

/**
 * Pure input validation for the DNS mode local listen port. Error strings are
 * Chinese dict keys resolved through localizedText at the UI layer. Kept free
 * of Android dependencies so unit tests can exercise it directly.
 */
object DnsListenPortValidator {
    const val DEFAULT_PORT = 1053
    const val MIN_PORT = 1024
    const val MAX_PORT = 65535

    /** Returns null when acceptable, otherwise the error message key. */
    fun validate(portText: String): String? {
        val port = portText.trim().toIntOrNull() ?: return "端口必须为数字"
        if (port !in MIN_PORT..MAX_PORT) return "端口必须在 $MIN_PORT-$MAX_PORT 之间"
        return null
    }

    fun parse(portText: String): Int = portText.trim().toIntOrNull() ?: DEFAULT_PORT
}
